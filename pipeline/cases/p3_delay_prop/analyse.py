"""P3 · Analyse: how much US flight delay is propagated from earlier flights, where, and how much buffer stops it?

Reads only the committed aggregate tables (aggregates/), so it runs without the 350 MB of raw data.
* Cause shares of delay minutes (BTS: "each cause is prorated based on delayed minutes it is responsible for").
* Where late-aircraft delay builds up: busiest airports x scheduled departure hour.
* Propagation: for the same aircraft, how many minutes of inbound arrival delay show up as outbound departure delay,
  by scheduled turn time. Exact OLS slopes are rebuilt from the sufficient statistics (n, sums, cross-products).
* Validation: slopes estimated on Jan-Sep, checked on Oct-Dec (time split).
Cause categories are carrier-reported labels, not measured causes.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from common.charts import Axis, Chart, Heatmap, ReferenceLine, export_chart, make_series
from common.io import capture_output
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
AGG = CASE_DIR / "aggregates"
SOURCE = "Data: US Bureau of Transportation Statistics, Reporting Carrier On-Time Performance, 2025."
CAUSES = {"CarrierDelay": "Air carrier", "WeatherDelay": "Extreme weather", "NASDelay": "National Aviation System",
          "SecurityDelay": "Security", "LateAircraftDelay": "Late-arriving aircraft"}
TOP_HUBS = 10
TRAIN_MONTHS = range(1, 10)      # Jan-Sep estimate, Oct-Dec check
PASS_TARGET = 0.5                # buffer rule: less than half of a one-hour-late arrival passes to the next departure
REF_BIN = "[60, 75)"             # inbound delays of 60-74 minutes: the "one hour late" reference bin
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def ols_from_sums(g: pd.DataFrame) -> tuple[float, float, int]:
    # >>> snippet: ols_from_sums
    n, sx, sy, sxx, sxy = g.n.sum(), g.sx.sum(), g.sy.sum(), g.sxx.sum(), g.sxy.sum()
    slope = (n * sxy - sx * sy) / (n * sxx - sx ** 2)
    intercept = (sy - slope * sx) / n
    # <<< snippet
    return float(slope), float(intercept), int(n)


def band_order(bands) -> list[str]:
    return sorted(set(bands), key=lambda b: float(b.strip("[)").split(",")[0]))


def overview(fm: pd.DataFrame, rs: ResultStore) -> None:
    rs.put("analysis_year_label", "2025", "year", "Calendar year of the flight data")
    rs.put("n_flights", int(fm.flights.sum()), "flights", "Flights reported by carriers in 2025")
    rs.put("cancel_rate", float(fm.cancelled.sum() / fm.flights.sum()), "share", "Share of flights cancelled", decimals=1, pct=True)
    rs.put("divert_rate", float(fm.diverted.sum() / fm.flights.sum()), "share", "Share of flights diverted", decimals=2, pct=True)
    rs.put("delay15_rate", float(fm.delayed15.sum() / (fm.flights - fm.cancelled - fm.diverted).sum()), "share",
           "Share of operated flights arriving 15+ minutes late", decimals=1, pct=True)
    rs.put("n_delayed15", int(fm.delayed15.sum()), "flights", "Flights arriving 15+ minutes late")
    rs.put("cause_missing", int(fm.cause_missing_on_delayed.sum()), "flights", "Delayed flights with any cause field missing")


def causes(fm: pd.DataFrame, rs: ResultStore) -> pd.DataFrame:
    # >>> snippet: cause_shares
    minutes = fm[list(CAUSES)].sum()
    shares = minutes / minutes.sum()
    # <<< snippet
    with capture_output(CASE_DIR, "cause_shares"):
        print((shares.rename(CAUSES) * 100).round(1).to_string())
    for c, label in CAUSES.items():
        tag = c.replace("Delay", "").lower()
        rs.put(f"share_{tag}", float(shares[c]), "share", f"Share of 2025 delay minutes coded '{label}'", decimals=1, pct=True)
    rs.put("cause_minutes_total", float(minutes.sum()), "minutes", "Total cause-coded delay minutes (delayed flights)", decimals=0)
    rs.put("proration_gap", float(minutes.sum() / fm.arr_delay_minutes_delayed.sum()), "ratio",
           "Cause minutes divided by arrival delay minutes of delayed flights (prorated, should be close to one)", decimals=3)
    monthly = fm.set_index("month")[list(CAUSES)].div(fm.set_index("month")[list(CAUSES)].sum(axis=1), axis=0)
    la = monthly["LateAircraftDelay"]
    rs.put("la_share_min_month", MONTHS[int(la.idxmin()) - 1], "month", "Month with the lowest late-aircraft share")
    rs.put("la_share_max_month", MONTHS[int(la.idxmax()) - 1], "month", "Month with the highest late-aircraft share")
    rs.put("la_share_min", float(la.min()), "share", "Lowest monthly late-aircraft share", decimals=1, pct=True)
    rs.put("la_share_max", float(la.max()), "share", "Highest monthly late-aircraft share", decimals=1, pct=True)
    rs.put("busiest_delay_month", MONTHS[int(fm.set_index('month').delayed15.idxmax()) - 1], "month",
           "Month with the most flights 15+ minutes late")
    return monthly


def hubs(hh: pd.DataFrame, rs: ResultStore) -> pd.DataFrame:
    top = hh.groupby("Origin").departures.sum().nlargest(TOP_HUBS).index.tolist()
    # >>> snippet: hub_hour
    t = hh[hh.Origin.isin(top) & hh.hour.between(5, 23)].copy()
    t["la_per_dep"] = t.late_aircraft_min / t.departures       # late-aircraft minutes per scheduled departure
    grid = t.pivot(index="Origin", columns="hour", values="la_per_dep").loc[top]
    # <<< snippet
    morning = t[t.hour.between(6, 9)]
    evening = t[t.hour.between(17, 21)]
    m = morning.late_aircraft_min.sum() / morning.departures.sum()
    e = evening.late_aircraft_min.sum() / evening.departures.sum()
    rs.put("la_morning", float(m), "minutes per departure", "Busiest airports: late-aircraft minutes per departure, 06-09h", decimals=1)
    rs.put("la_evening", float(e), "minutes per departure", "Busiest airports: late-aircraft minutes per departure, 17-21h", decimals=1)
    rs.put("la_evening_ratio", float(e / m), "ratio", "Evening vs morning late-aircraft minutes per departure", decimals=1)
    rs.put("top_hub", top[0], "airport", "Airport with the most departures in 2025")
    worst = t.loc[t.la_per_dep.idxmax()]
    rs.put("worst_cell_airport", str(worst.Origin), "airport", "Busiest-ten airport x hour cell with most late-aircraft minutes per departure")
    rs.put("worst_cell_hour", int(worst.hour), "hour", "Scheduled departure hour of that worst cell")
    rs.put("worst_cell_value", float(worst.la_per_dep), "minutes per departure", "Late-aircraft minutes per departure in that cell", decimals=1)
    rs.put("worst_cell_deps", int(worst.departures), "departures", "Scheduled departures behind that worst cell in 2025")
    rs.put("hub_median_cell_deps", int(t.departures.median()), "departures", "Median departures per busiest-ten airport x hour cell")
    rs.put("n_top_hubs", TOP_HUBS, "airports", "Number of busiest airports shown")
    return grid


def propagation(rot: pd.DataFrame, rs: ResultStore) -> pd.DataFrame:
    rows = []
    for band in band_order(rot.band):
        g = rot[rot.band == band]
        b_all, a_all, n_all = ols_from_sums(g)
        b_tr, a_tr, _ = ols_from_sums(g[g.month.isin(TRAIN_MONTHS)])
        b_te, a_te, _ = ols_from_sums(g[~g.month.isin(TRAIN_MONTHS)])
        # >>> snippet: pass_through
        ref = g[g.bin == REF_BIN]
        ref_tr = ref[ref.month.isin(TRAIN_MONTHS)]
        pass_all = ref.sy.sum() / ref.sx.sum()          # outbound delay / inbound delay, for ~one-hour-late arrivals
        pass_tr = ref_tr.sy.sum() / ref_tr.sx.sum()
        # <<< snippet
        rows.append({"band": band, "slope": b_all, "intercept": a_all, "n": n_all,
                     "slope_train": b_tr, "slope_test": b_te,
                     "mean_turn": g.turn_sum.sum() / g.n.sum(),
                     "pass": pass_all, "pass_train": pass_tr,
                     "out_ref": ref.sy.sum() / ref.n.sum(), "in_ref": ref.sx.sum() / ref.n.sum()})
    t = pd.DataFrame(rows).rename(columns={"pass": "pass_"})
    with capture_output(CASE_DIR, "propagation_table"):
        print(t[["band", "n", "mean_turn", "slope", "intercept", "pass_", "pass_train"]]
              .rename(columns={"pass_": "pass_through", "pass_train": "pass_jan_sep"}).round(3).to_string(index=False))
    names = [f"b{i + 1}" for i in range(len(t))]
    for nm, r in zip(names, t.itertuples()):
        rs.put(f"slope_{nm}", r.slope, "minutes out per minute in", f"Propagation slope, scheduled turn {r.band} min", decimals=2)
        rs.put(f"slope_{nm}_train", r.slope_train, "minutes out per minute in", f"Slope {r.band} estimated Jan-Sep", decimals=2)
        rs.put(f"slope_{nm}_test", r.slope_test, "minutes out per minute in", f"Slope {r.band} re-estimated Oct-Dec", decimals=2)
        rs.put(f"pass_{nm}", r.pass_, "share", f"Pass-through of a one-hour-late arrival, turn {r.band} min", decimals=0, pct=True)
        rs.put(f"absorbed_{nm}", r.in_ref - r.out_ref, "minutes", f"Minutes of a one-hour-late arrival absorbed, turn {r.band}", decimals=0)
        rs.put(f"mean_turn_{nm}", r.mean_turn, "minutes", f"Average scheduled turn in band {r.band}", decimals=0)
        rs.put(f"n_pairs_{nm}", r.n, "turns", f"Aircraft turns in band {r.band} with a late inbound arrival")
        rs.put(f"band_{nm}", r.band.replace("[", "").replace(")", "").replace(", ", "-"), "minutes", f"Turn band {nm} label (minutes)")
    rs.put("n_pairs", int(t.n.sum()), "turns", "Aircraft turns analysed (late inbound arrival, normal turn)")
    rs.put("max_slope_shift", float((t.slope_test - t.slope_train).abs().max()), "minutes out per minute in",
           "Largest change in a band's slope between Jan-Sep and Oct-Dec", decimals=2)
    # decision: the shortest turn band where less than half of a one-hour-late arrival passes on (Jan-Sep only)
    # >>> snippet: buffer_rule
    ok = t[t.pass_train < PASS_TARGET]
    pick = ok.iloc[0] if len(ok) else t.iloc[-1]
    # <<< snippet
    idx = int(t.index[t.band == pick.band][0])
    rs.put("pass_target", PASS_TARGET, "share", "Target: less than this share of a one-hour-late arrival passes on", decimals=0, pct=True)
    rs.put("buffer_band", names[idx], "band", "Turn band chosen by the buffer rule")
    rs.put("buffer_min_turn", int(float(pick.band.strip("[)").split(",")[0])), "minutes",
           "Shortest scheduled turn that meets the target (lower edge of the chosen band)")
    rs.put("buffer_pass_test", float(pick.pass_), "share",
           "Pass-through in the chosen band over the whole year (check)", decimals=0, pct=True)
    rs.put("buffer_saving_ref", float(t.out_ref.iloc[0] - pick.out_ref), "minutes",
           "Outbound delay avoided after a one-hour-late arrival: shortest band vs chosen band", decimals=0)
    rs.put("n_bands", len(t), "bands", "Scheduled turn bands analysed")
    return t


def charts(monthly: pd.DataFrame, grid: pd.DataFrame, rot: pd.DataFrame, t: pd.DataFrame) -> None:
    out = CASE_DIR / "charts"
    export_chart(Chart(
        id="p3_cause_share_by_month", type="stacked_bar",
        title="What delay minutes are coded as, by month",
        subtitle="Share of each month's cause-coded delay minutes (flights 15+ min late)",
        x_axis=Axis(title="Month (2025)", kind="category"),
        y_axis=Axis(title="Share of delay minutes", unit="share", min=0, max=1),
        series=[make_series(label, MONTHS, monthly[c], unit="share", downsample=False) for c, label in CAUSES.items()],
        source_note=SOURCE, result_keys=["share_lateaircraft", "share_nas", "share_carrier", "share_weather"],
    ), out)
    export_chart(Chart(
        id="p3_hub_hour_heatmap", type="heatmap",
        title="Where late-aircraft delay builds up",
        subtitle="Late-aircraft delay minutes per scheduled departure, ten busiest airports, by departure hour",
        x_axis=Axis(title="Scheduled departure hour (local)", kind="category"),
        y_axis=Axis(title="Airport", kind="category"),
        heatmap=Heatmap(x_categories=[f"{h:02d}" for h in grid.columns], y_categories=list(grid.index),
                        values=[[None if pd.isna(v) else float(v) for v in row] for row in grid.values],
                        value_unit="minutes per departure"),
        source_note=SOURCE, result_keys=["la_morning", "la_evening", "la_evening_ratio", "worst_cell_airport"],
    ), out)
    series = []
    for band in band_order(rot.band):
        g = rot[rot.band == band].groupby("bin")[["n", "sx", "sy"]].sum()
        g = g.loc[band_order(g.index)]
        series.append(make_series(f"Turn {band.strip('[)').replace(', ', '-')} min", g.sx / g.n, g.sy / g.n,
                                  unit="minutes", downsample=False))
    series.append(make_series("Full propagation (out = in)", [0, 180], [0, 180], role="benchmark", downsample=False))
    export_chart(Chart(
        id="p3_propagation_by_turn", type="line",
        title="How much inbound delay passes to the next departure",
        subtitle="Same aircraft; average outbound departure delay by inbound arrival delay, per scheduled turn time",
        x_axis=Axis(title="Inbound arrival delay", unit="minutes", min=0, max=180),
        y_axis=Axis(title="Outbound departure delay", unit="minutes", min=0),
        series=series, reference_lines=[ReferenceLine(axis="y", value=0, label="on time")],
        source_note=SOURCE, result_keys=["slope_b1", "slope_b2", "slope_b3", "slope_b4", "buffer_min_turn"],
    ), out)


def analyse() -> ResultStore:
    fm = pd.read_csv(AGG / "flights_month.csv")
    hh = pd.read_csv(AGG / "hub_hour.csv")
    rot = pd.read_csv(AGG / "rotations.csv")
    rs = ResultStore(CASE_DIR)
    overview(fm, rs)
    monthly = causes(fm, rs)
    grid = hubs(hh, rs)
    t = propagation(rot, rs)
    charts(monthly, grid, rot, t)
    rs.save()
    return rs


if __name__ == "__main__":
    analyse()
