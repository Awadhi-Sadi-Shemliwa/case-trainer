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


def rotations(df: pd.DataFrame, counts: dict) -> pd.DataFrame:
    flown = df[(df.Cancelled == 0) & (df.Diverted == 0) & df.Tail_Number.notna()].copy()
    flown["dep_min"] = hhmm_to_min(flown.CRSDepTime)
    flown["arr_min"] = hhmm_to_min(flown.CRSArrTime)
    # >>> snippet: build_rotations
    flown = flown.sort_values(["Tail_Number", "FlightDate", "dep_min"])
    nxt = flown.groupby(["Tail_Number", "FlightDate"]).shift(-1)
    pairs = pd.DataFrame({
        "month": flown.month, "airport": flown.Dest, "next_origin": nxt.Origin,
        "in_arr_delay": flown.ArrDelay, "out_dep_delay": nxt.DepDelay,
        "turn": nxt.dep_min - flown.arr_min, "overnight": flown.arr_min < flown.dep_min,
    }).dropna(subset=["next_origin", "in_arr_delay", "out_dep_delay"])
    pairs = pairs[(pairs.airport == pairs.next_origin) & ~pairs.overnight]
    # <<< snippet
    n0 = len(pairs)
    keep = pairs.turn.between(TURN_BANDS[0], TURN_BANDS[-1], inclusive="left")
    pairs = pairs[keep]
    counts["turn_before"] += n0
    counts["turn_after"] += len(pairs)
    n1 = len(pairs)
    pairs = pairs[pairs.in_arr_delay.between(DELAY_BINS[0], DELAY_BINS[-1], inclusive="left")]
    counts["delay_after"] += len(pairs)
    pairs["band"] = pd.cut(pairs.turn, TURN_BANDS, right=False).astype(str)
    pairs["bin"] = pd.cut(pairs.in_arr_delay, DELAY_BINS, right=False).astype(str)
    x, y = pairs.in_arr_delay, pairs.out_dep_delay
    pairs = pairs.assign(x=x, y=y, xx=x * x, xy=x * y, yy=y * y)
    # sufficient statistics: exact OLS slopes can be rebuilt from n, sums and cross-products
    agg = pairs.groupby(["month", "band", "bin"]).agg(n=("x", "size"), sx=("x", "sum"), sy=("y", "sum"),
                                                     sxx=("xx", "sum"), sxy=("xy", "sum"), syy=("yy", "sum"),
                                                     turn_sum=("turn", "sum")).reset_index()
    return agg, len(pairs)


def clean() -> None:
    AGG.mkdir(exist_ok=True)
    prov = Provenance(CASE_DIR)
    months, hubs, rots = [], [], []
    n_rows = n_flown = 0
    counts = {"turn_before": 0, "turn_after": 0, "delay_after": 0}
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
    rr = pd.concat(rots).groupby(["month", "band", "bin"], as_index=False).sum()
    rr.to_csv(AGG / "rotations.csv", index=False)
    prov.log_transform("bts_all", "rotation_turn_window", counts["turn_before"], counts["turn_after"],
                       reason=(f"Keep turns of {TURN_BANDS[0]}-{TURN_BANDS[-1]} scheduled minutes. Shorter is a data error or a "
                               "through-flight; longer is an aircraft parked for hours, not a turn. Counts over all 12 months."),
                       details={"dropped": counts["turn_before"] - counts["turn_after"]})
    prov.log_transform("bts_all", "rotation_delay_range", counts["turn_after"], counts["delay_after"],
                       reason=(f"Model only late inbound arrivals of {DELAY_BINS[0]}-{DELAY_BINS[-1]} minutes: early arrivals cannot "
                               "propagate lateness and extreme delays (over three hours) are rare and often involve aircraft swaps."),
                       details={"dropped_early_or_extreme": counts["turn_after"] - counts["delay_after"]})
    prov.log_transform("bts_all", "cancelled_diverted_excluded", n_rows, n_flown,
                       reason=("Cancelled and diverted flights have no arrival delay or cause minutes, so they are excluded from "
                               "delay statistics and counted separately (this removes some of the worst disruption)."),
                       details={"cancelled": int(fm.cancelled.sum()), "diverted": int(fm.diverted.sum())})
    prov.save()


if __name__ == "__main__":
    with capture_output(CASE_DIR, "clean_log"):
        clean()
