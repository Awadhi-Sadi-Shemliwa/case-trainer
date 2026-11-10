"""P3 · Clean: 12 monthly BTS files -> small aggregate tables (committed) that the analysis reads.

Raw zips (~350 MB) are not committed, so this step turns millions of flights into:
  aggregates/flights_month.csv    flights, cancelled, diverted, delayed (15+), cause minutes per month
  aggregates/hub_hour.csv         departures and late-aircraft minutes per origin airport x scheduled hour
  aggregates/rotations.csv        sufficient statistics of (inbound arrival delay -> outbound departure delay)
                                  per month x scheduled-turn band x inbound-delay bin
Every row filter is logged with counts and a reason (spec §2).

Rotation = the same aircraft (Tail_Number) arriving at an airport and its NEXT scheduled departure from that airport
on the same date. Times are local hhmm; both legs of a turn are at the same airport, so the turn time is in one
time zone. Overnight inbound legs (scheduled arrival clock time earlier than departure clock time) are dropped
because their arrival date is ambiguous without time zones.
"""

from __future__ import annotations

import io
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

from common.io import capture_output
from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
RAW = CASE_DIR / "raw"
AGG = CASE_DIR / "aggregates"
YEAR = 2025
COLS = ["FlightDate", "Reporting_Airline", "Tail_Number", "Origin", "Dest", "CRSDepTime", "CRSArrTime",
        "DepDelay", "ArrDelay", "ArrDel15", "Cancelled", "Diverted",
        "CarrierDelay", "WeatherDelay", "NASDelay", "SecurityDelay", "LateAircraftDelay"]
CAUSES = ["CarrierDelay", "WeatherDelay", "NASDelay", "SecurityDelay", "LateAircraftDelay"]
TURN_BANDS = [20, 45, 60, 75, 90, 120, 240]          # scheduled turn minutes; outside 20-240 is not a normal turn
DELAY_BINS = list(range(0, 181, 15))         # inbound arrival delay bins (minutes); > 180 excluded as extreme


def load_month(m: int) -> pd.DataFrame:
    path = RAW / f"ontime_{YEAR}_{m:02d}.zip"
    with zipfile.ZipFile(path) as z:
        name = next(n for n in z.namelist() if n.lower().endswith(".csv"))
        # >>> snippet: load_month
        df = pd.read_csv(io.BytesIO(z.read(name)), usecols=COLS,
                         dtype={"CRSDepTime": "Int64", "CRSArrTime": "Int64", "Tail_Number": "string"})
        # <<< snippet
    df["month"] = m
    return df


def hhmm_to_min(x: pd.Series) -> pd.Series:
    # >>> snippet: hhmm
    x = x.where(x != 2400, 0)                    # BTS writes midnight as 2400
    return (x // 100) * 60 + (x % 100)           # hhmm -> minutes after midnight
    # <<< snippet


STAGES = ["operated", "with_tail", "has_next_leg", "same_airport", "not_overnight", "turn_window", "delay_range"]
STAGE_REASONS = {
    "with_tail": "Flights without a tail number cannot be linked to the aircraft's next flight.",
    "has_next_leg": ("The aircraft's last flight of the day, or a next leg with a missing delay, has no outbound flight "
                     "to pair with."),
    "same_airport": ("The next leg must leave from the airport where the aircraft landed; otherwise the record is broken "
                     "or the aircraft was repositioned without a reported flight."),
    "not_overnight": ("Inbound legs whose scheduled arrival clock time is earlier than their departure clock time are "
                      "treated as overnight and dropped (dates are ambiguous without time zones). This also drops some "
                      "short westbound flights that cross a time zone: a known limitation."),
    "turn_window": ("Keep scheduled turns of 20 to 240 minutes. Shorter is below any realistic minimum turn (a data "
                    "error); longer is an aircraft parked for hours, not a turn."),
    "delay_range": ("Keep inbound arrival delays from 0 up to 180 minutes (on time to three hours late, including "
                    "0-14 minutes, which BTS does not call late). Early arrivals are excluded; extreme delays are rare "
                    "and often involve aircraft swaps."),
}


def rotations(df: pd.DataFrame, counts: dict) -> pd.DataFrame:
    # tail-days with any cancellation or diversion: aircraft swaps and re-pairing are likely (sensitivity flag)
    disrupted = df[(df.Cancelled == 1) | (df.Diverted == 1)].groupby(["Tail_Number", "FlightDate"]).size()
    flown = df[(df.Cancelled == 0) & (df.Diverted == 0)].copy()
    counts["operated"] += len(flown)
    flown = flown[flown.Tail_Number.notna()]
    counts["with_tail"] += len(flown)
    flown["dep_min"] = hhmm_to_min(flown.CRSDepTime)
    flown["arr_min"] = hhmm_to_min(flown.CRSArrTime)
    # >>> snippet: build_rotations
    flown = flown.sort_values(["Tail_Number", "FlightDate", "dep_min"])
    nxt = flown.groupby(["Tail_Number", "FlightDate"]).shift(-1)
    pairs = pd.DataFrame({
        "month": flown.month, "carrier": flown.Reporting_Airline, "airport": flown.Dest, "next_origin": nxt.Origin,
        "in_arr_delay": flown.ArrDelay, "out_dep_delay": nxt.DepDelay,
        "turn": nxt.dep_min - flown.arr_min, "overnight": flown.arr_min < flown.dep_min,
        "clean_day": ~pd.MultiIndex.from_frame(flown[["Tail_Number", "FlightDate"]]).isin(disrupted.index),
    }).dropna(subset=["next_origin", "in_arr_delay", "out_dep_delay"])
    counts["has_next_leg"] += len(pairs)
    pairs = pairs[pairs.airport == pairs.next_origin]
    counts["same_airport"] += len(pairs)
    pairs = pairs[~pairs.overnight]
    # <<< snippet
    counts["not_overnight"] += len(pairs)
    pairs = pairs[pairs.turn.between(TURN_BANDS[0], TURN_BANDS[-1], inclusive="left")]
    counts["turn_window"] += len(pairs)
    pairs = pairs[pairs.in_arr_delay.between(DELAY_BINS[0], DELAY_BINS[-1], inclusive="left")]
    counts["delay_range"] += len(pairs)
    pairs["band"] = pd.cut(pairs.turn, TURN_BANDS, right=False).astype(str)
    pairs["bin"] = pd.cut(pairs.in_arr_delay, DELAY_BINS, right=False).astype(str)
    x, y = pairs.in_arr_delay, pairs.out_dep_delay
    pairs = pairs.assign(x=x, y=y, xx=x * x, xy=x * y, yy=y * y)
    # sufficient statistics: exact OLS slopes can be rebuilt from n, sums and cross-products
    agg = pairs.groupby(["month", "carrier", "clean_day", "band", "bin"]).agg(
        n=("x", "size"), sx=("x", "sum"), sy=("y", "sum"), sxx=("xx", "sum"), sxy=("xy", "sum"),
        syy=("yy", "sum"), turn_sum=("turn", "sum")).reset_index()
    return agg, len(pairs)


def clean() -> None:
    AGG.mkdir(exist_ok=True)
    prov = Provenance(CASE_DIR)
    months, hubs, rots = [], [], []
    n_rows = n_flown = 0
    counts = {k: 0 for k in STAGES}
    for m in range(1, 13):
        df = load_month(m)
        n_rows += len(df)
        dl = df[df.ArrDel15 == 1]
        months.append({"month": m, "flights": len(df), "cancelled": int(df.Cancelled.sum()),
                       "diverted": int(df.Diverted.sum()), "delayed15": len(dl),
                       "arr_delay_minutes_delayed": float(dl.ArrDelay.sum()),
                       **{c: float(dl[c].sum()) for c in CAUSES},
                       "cause_missing_on_delayed": int(dl[CAUSES].isna().any(axis=1).sum())})
        dep = df[df.Cancelled == 0].assign(hour=lambda d: (d.CRSDepTime.where(d.CRSDepTime != 2400, 0) // 100).astype(int))
        hubs.append(dep.groupby(["Origin", "hour"]).agg(departures=("month", "size"),
                                                        late_aircraft_min=("LateAircraftDelay", "sum"),
                                                        delayed15=("ArrDel15", "sum")).reset_index().assign(month=m))
        r, n = rotations(df, counts)
        rots.append(r)
        n_flown += int(((df.Cancelled == 0) & (df.Diverted == 0)).sum())
        print(f"month {m:>2}: {len(df):,} flights, {len(dl):,} delayed 15+, {n:,} rotation pairs")
    fm = pd.DataFrame(months)
    fm.to_csv(AGG / "flights_month.csv", index=False)
    hh = pd.concat(hubs).groupby(["Origin", "hour"], as_index=False)[["departures", "late_aircraft_min", "delayed15"]].sum()
    hh.to_csv(AGG / "hub_hour.csv", index=False)
    rr = pd.concat(rots).groupby(["month", "carrier", "clean_day", "band", "bin"], as_index=False).sum()
    rr.to_csv(AGG / "rotations.csv", index=False)
    for prev, stage in zip(STAGES, STAGES[1:]):
        prov.log_transform("bts_all", f"rotation_{stage}", counts[prev], counts[stage],
                           reason=STAGE_REASONS[stage] + " Counts over all 12 months.")
    prov.log_transform("bts_all", "cancelled_diverted_excluded", n_rows, n_flown,
                       reason=("Cancelled and diverted flights have no arrival delay or cause minutes, so they are excluded from "
                               "delay statistics and counted separately (this removes some of the worst disruption)."),
                       details={"cancelled": int(fm.cancelled.sum()), "diverted": int(fm.diverted.sum())})
    prov.save()


if __name__ == "__main__":
    with capture_output(CASE_DIR, "clean_log"):
        clean()
