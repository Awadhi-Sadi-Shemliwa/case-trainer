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
PASS_TARGET = 0.5                # buffer rule: less than half of the EXTRA delay of a one-hour-late arrival passes on
REF_BIN = "[60, 75)"             # inbound delays of 60-74 minutes: the "one hour late" reference bin
BASE_BIN = "[0, 15)"             # on-time-ish inbound: its outbound delay is the baseline that is NOT propagation
MIN_CELL_DEPS = 500              # heatmap cells with fewer departures are masked (rates from tiny samples mislead)
MIN_CARRIER_N = 200              # a carrier needs this many pairs in both bins of a band to enter the weighted curve
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
    t.loc[t.departures < MIN_CELL_DEPS, "la_per_dep"] = np.nan  # mask rates resting on very few departures
    grid = t.pivot(index="Origin", columns="hour", values="la_per_dep").loc[top]
    # <<< snippet
    night = hh[hh.Origin.isin(top) & ~hh.hour.between(5, 23)]
    rs.put("hub_deps_hours_0_4", int(night.departures.sum()), "departures",
           "Busiest-ten departures scheduled 00-04h (not shown on the heatmap)")
    rs.put("min_cell_deps", MIN_CELL_DEPS, "departures", "Heatmap cells with fewer departures are masked")
    rs.put("n_masked_cells", int((t.departures < MIN_CELL_DEPS).sum()), "cells", "Heatmap cells masked for small samples")
    morning = t[t.hour.between(6, 9)]
    evening = t[t.hour.between(17, 21)]
    m = morning.late_aircraft_min.sum() / morning.departures.sum()
    e = evening.late_aircraft_min.sum() / evening.departures.sum()
    rs.put("la_morning", float(m), "minutes per departure", "Busiest airports: late-aircraft minutes per departure, 06-09h", decimals=1)
    rs.put("la_evening", float(e), "minutes per departure", "Busiest airports: late-aircraft minutes per departure, 17-21h", decimals=1)
    rs.put("la_evening_ratio", float(e / m), "ratio", "Evening vs morning late-aircraft minutes per departure", decimals=1)
    ev = evening.groupby("Origin")[["late_aircraft_min", "departures"]].sum()
    ev = (ev.late_aircraft_min / ev.departures).sort_values(ascending=False)
    rs.put("evening_worst_airport", str(ev.index[0]), "airport", "Busiest-ten airport with most late-aircraft minutes per departure, 17-21h")
    rs.put("evening_worst_value", float(ev.iloc[0]), "minutes per departure", "Its evening late-aircraft minutes per departure", decimals=1)
    rs.put("evening_second_airport", str(ev.index[1]), "airport", "Second-worst busiest-ten airport in the evening")
    # the raw (unmasked) extreme cell: kept as the small-denominator lesson
    raw = hh[hh.Origin.isin(top) & hh.hour.between(5, 23)].assign(r=lambda d: d.late_aircraft_min / d.departures)
    worst = raw.loc[raw.r.idxmax()]
    rs.put("worst_cell_airport", str(worst.Origin), "airport", "Unmasked busiest-ten airport x hour cell with the highest rate")
    rs.put("worst_cell_hour", int(worst.hour), "hour", "Scheduled departure hour of that cell")
    rs.put("worst_cell_value", float(worst.r), "minutes per departure", "Late-aircraft minutes per departure in that cell", decimals=1)
    rs.put("worst_cell_deps", int(worst.departures), "departures", "Scheduled departures behind that cell in 2025")
    rs.put("hub_median_cell_deps", int(t.departures.median()), "departures", "Median departures per busiest-ten airport x hour cell")
    rs.put("n_top_hubs", TOP_HUBS, "airports", "Number of busiest airports shown")
    rs.put("top_hub", top[0], "airport", "Airport with the most departures in 2025")
    return grid


def excess_pass(g: pd.DataFrame) -> tuple[float, float, float, float]:
    """Excess pass-through: extra outbound delay per extra inbound minute, between the on-time-ish bin and the
    one-hour-late bin. Removes the baseline delay the outbound flight would have had anyway."""
    # >>> snippet: pass_through
    base, ref = g[g.bin == BASE_BIN], g[g.bin == REF_BIN]
    y_base, x_base = base.sy.sum() / base.n.sum(), base.sx.sum() / base.n.sum()
    y_ref, x_ref = ref.sy.sum() / ref.n.sum(), ref.sx.sum() / ref.n.sum()
    excess = (y_ref - y_base) / (x_ref - x_base)     # 1.0 = every extra inbound minute is passed on
    raw = y_ref / x_ref                              # includes the baseline: can exceed 1 without any amplification
    # <<< snippet
    return float(excess), float(raw), float(y_base), float(y_ref)


def carrier_weighted(rot: pd.DataFrame, bands: list[str]) -> pd.Series:
    """Average of within-carrier excess pass-through per band, using one fixed set of carrier weights (each
    carrier's total pairs), so bands are compared with the same airline mix rather than different airlines."""
    # >>> snippet: carrier_weighted
    weights = rot.groupby("carrier").n.sum()
    out = {}
    for band in bands:
        vals, w = [], []
        for c, gc in rot[rot.band == band].groupby("carrier"):
            nb, nr = gc.loc[gc.bin == BASE_BIN, "n"].sum(), gc.loc[gc.bin == REF_BIN, "n"].sum()
            if nb >= MIN_CARRIER_N and nr >= MIN_CARRIER_N:
                vals.append(excess_pass(gc)[0])
                w.append(weights[c])
        out[band] = float(np.average(vals, weights=w)) if vals else np.nan
    # <<< snippet
    return pd.Series(out)


def interp_turn(turns: pd.Series, passes: pd.Series, target: float) -> float:
    """Scheduled turn (minutes) at which the curve crosses the target, by linear interpolation between band means."""
    for (t0, p0), (t1, p1) in zip(zip(turns, passes), list(zip(turns, passes))[1:]):
        if p0 >= target > p1:
            return float(t0 + (p0 - target) * (t1 - t0) / (p0 - p1))
    return float("nan")


def interp_pass(turns: pd.Series, passes: pd.Series, turn: float) -> float:
    return float(np.interp(turn, turns, passes))


def propagation(rot: pd.DataFrame, rs: ResultStore) -> pd.DataFrame:
    bands = band_order(rot.band)
    train, test = rot[rot.month.isin(TRAIN_MONTHS)], rot[~rot.month.isin(TRAIN_MONTHS)]
    clean_days = rot[rot.clean_day]
    rows = []
    for band in bands:
        g = rot[rot.band == band]
        slope, intercept, n = ols_from_sums(g)
        ex, raw, y_base, y_ref = excess_pass(g)
        rows.append({"band": band, "n": n, "mean_turn": g.turn_sum.sum() / g.n.sum(), "slope": slope,
                     "pass_raw": raw, "pass_excess": ex, "base_out": y_base,
                     "pass_excess_train": excess_pass(train[train.band == band])[0],
                     "pass_excess_test": excess_pass(test[test.band == band])[0],
                     "pass_excess_clean_days": excess_pass(clean_days[clean_days.band == band])[0],
                     "slope_train": ols_from_sums(train[train.band == band])[0],
                     "slope_test": ols_from_sums(test[test.band == band])[0]})
    t = pd.DataFrame(rows)
    t["pass_carrier_w"] = carrier_weighted(rot, bands).values
    t["pass_carrier_w_train"] = carrier_weighted(train, bands).values
    t["pass_carrier_w_test"] = carrier_weighted(test, bands).values
    # carrier mix of the shortest and longest bands (the confounder)
    mix = rot.groupby(["band", "carrier"]).n.sum()
    for nm, band in (("short", bands[0]), ("long", bands[-1])):
        share = (mix.loc[band] / mix.loc[band].sum()).sort_values(ascending=False)
        rs.put(f"top_carrier_{nm}", str(share.index[0]), "carrier code", f"Carrier with most pairs in turn band {band}")
        rs.put(f"top_carrier_{nm}_share", float(share.iloc[0]), "share", f"Its share of pairs in band {band}", decimals=0, pct=True)
    with capture_output(CASE_DIR, "propagation_table"):
        print(t[["band", "n", "mean_turn", "slope", "pass_raw", "pass_excess", "pass_carrier_w", "pass_excess_clean_days"]]
              .round(3).to_string(index=False))
    names = [f"b{i + 1}" for i in range(len(t))]
    for nm, r in zip(names, t.itertuples()):
        lab = r.band.replace("[", "").replace(")", "").replace(", ", "-")
        rs.put(f"band_{nm}", lab, "minutes", f"Turn band {nm} label (minutes)")
        rs.put(f"n_pairs_{nm}", r.n, "turns", f"Aircraft turns in band {r.band} (inbound 0-180 min late)")
        rs.put(f"mean_turn_{nm}", r.mean_turn, "minutes", f"Average scheduled turn in band {r.band}", decimals=0)
        rs.put(f"slope_{nm}", r.slope, "minutes out per minute in", f"OLS slope, turn {r.band}", decimals=2)
        rs.put(f"slope_{nm}_train", r.slope_train, "minutes out per minute in", f"OLS slope {r.band}, Jan-Sep", decimals=2)
        rs.put(f"slope_{nm}_test", r.slope_test, "minutes out per minute in", f"OLS slope {r.band}, Oct-Dec", decimals=2)
        rs.put(f"pass_raw_{nm}", r.pass_raw, "share", f"Raw pass-through (includes baseline), turn {r.band}", decimals=0, pct=True)
        rs.put(f"pass_{nm}", r.pass_excess, "share", f"Excess pass-through of a one-hour-late arrival, turn {r.band}", decimals=0, pct=True)
        rs.put(f"pass_cw_{nm}", r.pass_carrier_w, "share", f"Carrier-weighted excess pass-through, turn {r.band}", decimals=0, pct=True)
        rs.put(f"pass_clean_{nm}", r.pass_excess_clean_days, "share",
               f"Excess pass-through on tail-days without cancellations or diversions, turn {r.band}", decimals=0, pct=True)
        rs.put(f"base_out_{nm}", r.base_out, "minutes", f"Outbound delay when the inbound was on time (0-14 min late), turn {r.band}", decimals=1)
    rs.put("n_pairs", int(t.n.sum()), "turns", "Aircraft turns analysed (inbound on time to three hours late, normal turn)")
    rs.put("n_bands", len(t), "bands", "Scheduled turn bands analysed")
    rs.put("max_slope_shift", float((t.slope_test - t.slope_train).abs().max()), "minutes out per minute in",
           "Largest change in a band's slope between Jan-Sep and Oct-Dec", decimals=2)
    rs.put("max_pass_shift", float((t.pass_carrier_w_test - t.pass_carrier_w_train).abs().max()), "share",
           "Largest change in a band's carrier-weighted pass-through between Jan-Sep and Oct-Dec", decimals=0, pct=True)

    # decision: turn length where the carrier-weighted excess pass-through crosses the target (Jan-Sep only)
    # >>> snippet: buffer_rule
    turn_star = interp_turn(t.mean_turn, t.pass_carrier_w_train, PASS_TARGET)
    buffer_turn = int(np.ceil(turn_star / 5) * 5)                    # round UP to a schedulable 5 minutes
    # <<< snippet
    rs.put("pass_target", PASS_TARGET, "share", "Target: less than this share of the extra delay passes on", decimals=0, pct=True)
    rs.put("buffer_turn_exact", turn_star, "minutes", "Turn where the Jan-Sep carrier-weighted curve crosses the target", decimals=0)
    rs.put("buffer_min_turn", buffer_turn, "minutes", "Recommended minimum scheduled turn on targeted turns (rounded up to 5)")
    rs.put("buffer_pass_octdec", interp_pass(t.mean_turn, t.pass_carrier_w_test, buffer_turn), "share",
           "Carrier-weighted pass-through at that turn, Oct-Dec (out-of-time check)", decimals=0, pct=True)
    turn_test = interp_turn(t.mean_turn, t.pass_carrier_w_test, PASS_TARGET)
    rs.put("buffer_turn_octdec", turn_test, "minutes", "Turn where the Oct-Dec carrier-weighted curve crosses the target", decimals=0)
    rs.put("buffer_rule_holds_octdec", "yes" if interp_pass(t.mean_turn, t.pass_carrier_w_test, buffer_turn) < PASS_TARGET else "no",
           "flag", "Does the Jan-Sep rule still meet the target on Oct-Dec?")
    rs.put("buffer_pass_year", interp_pass(t.mean_turn, t.pass_carrier_w, buffer_turn), "share",
           "Carrier-weighted pass-through at that turn, whole year", decimals=0, pct=True)
    # what one added minute buys, for a one-hour-late arrival, moving from the shortest band's typical turn
    p_short, turn_short = float(t.pass_carrier_w.iloc[0]), float(t.mean_turn.iloc[0])
    p_buf = interp_pass(t.mean_turn, t.pass_carrier_w, buffer_turn)
    saved = (p_short - p_buf) * 60
    rs.put("buffer_added_minutes", buffer_turn - turn_short, "minutes", "Scheduled minutes added per turn moving from the shortest band's average turn", decimals=0)
    rs.put("buffer_saving_ref", saved, "minutes", "Outbound delay avoided for a one-hour-late arrival (carrier-weighted curve)", decimals=0)
    rs.put("saving_per_added_minute", saved / (buffer_turn - turn_short), "minutes per minute",
           "Delay avoided per scheduled minute added, for a one-hour-late arrival", decimals=2)
    ref_share = rot.loc[rot.bin == REF_BIN, "n"].sum() / rot.n.sum()
    rs.put("share_pairs_ref_bin", float(ref_share), "share", "Share of analysed turns whose inbound was 60-74 minutes late", decimals=1, pct=True)
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
        subtitle="Late-aircraft minutes per scheduled departure, ten busiest airports; blank = fewer than 500 departures",
        x_axis=Axis(title="Scheduled departure hour (local)", kind="category"),
        y_axis=Axis(title="Airport", kind="category"),
        heatmap=Heatmap(x_categories=[f"{h:02d}" for h in grid.columns], y_categories=list(grid.index),
                        values=[[None if pd.isna(v) else float(v) for v in row] for row in grid.values],
                        value_unit="minutes per departure"),
        source_note=SOURCE, result_keys=["la_morning", "la_evening", "la_evening_ratio", "evening_worst_airport", "min_cell_deps"],
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
        source_note=SOURCE, result_keys=["pass_b1", "pass_b5", "base_out_b1", "buffer_min_turn"],
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
