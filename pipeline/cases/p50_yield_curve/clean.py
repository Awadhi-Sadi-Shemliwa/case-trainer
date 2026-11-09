"""P50 · Clean: daily spreads -> monthly means, aligned with the monthly NBER recession indicator,
plus the forward-looking target. Every row dropped is logged with a reason (spec §2).

Target (stated in the case): rec_next12[t] = 1 if USREC == 1 in ANY month t+1 .. t+12.
Modelling sample: months with a known target that are NOT already in recession (model_sample).
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from common.io import capture_output
from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
RAW = CASE_DIR / "raw"
HORIZON = 12  # months ahead; the decision is about the next year


def load_daily(prov: Provenance, key: str, col: str) -> pd.Series:
    # >>> snippet: load_daily
    df = pd.read_csv(RAW / f"{col}.csv", parse_dates=["observation_date"])
    blanks = df[col].isna()
    print(f"{col}: {len(df)} rows, {blanks.sum()} blank")
    print(df.loc[blanks, "observation_date"].dt.strftime("%m-%d").value_counts().head(4).to_string())
    daily = df.loc[~blanks].set_index("observation_date")[col]
    # <<< snippet
    prov.log_transform(
        key, f"drop_blank_{col.lower()}", len(df), len(daily),
        reason=("Blank values fall on US bond-market holidays (Nov-11, Jul-04, Dec-25, Jan-01 most common); "
                "no trading -> no yield. Dropped, not filled: forward-filling would invent a trading day."),
        details={"top_blank_month_days": df.loc[blanks, "observation_date"].dt.strftime("%m-%d")
                 .value_counts().head(8).to_dict()},
    )
    return daily


def to_monthly(prov: Provenance, key: str, daily: pd.Series) -> pd.DataFrame:
    # >>> snippet: to_monthly
    monthly = daily.resample("MS").agg(["mean", "count"])
    monthly = monthly.rename(columns={"mean": daily.name, "count": f"{daily.name}_days"})
    # <<< snippet
    prov.log_transform(
        key, f"monthly_mean_{daily.name.lower()}", len(daily), len(monthly),
        reason=("Recession indicator is monthly, so daily spreads are averaged within each calendar month. "
                "Mean (not month-end) smooths day-to-day noise, matching Estrella-Mishkin style monthly averages."),
        details={"min_trading_days_in_a_month": int(monthly[f"{daily.name}_days"].min())},
    )
    return monthly


def build_panel(prov: Provenance) -> pd.DataFrame:
    # One captured output per series, so each code_predict step shows exactly what its code printed.
    with capture_output(CASE_DIR, "load_daily_t10y2y"):
        d2 = load_daily(prov, "fred_T10Y2Y", "T10Y2Y")
    with capture_output(CASE_DIR, "load_daily_t10y3m"):
        d3 = load_daily(prov, "fred_T10Y3M", "T10Y3M")
    s2 = to_monthly(prov, "fred_T10Y2Y", d2)
    s3 = to_monthly(prov, "fred_T10Y3M", d3)
    rec = pd.read_csv(RAW / "USREC.csv", parse_dates=["observation_date"]).set_index("observation_date")["USREC"]

    # Inner join on months where the 2s10s spread AND the recession indicator both exist.
    panel = s2.join(s3, how="left").join(rec, how="inner")
    n_rec_total = len(rec)
    prov.log_transform(
        "fred_USREC", "align_months", n_rec_total, len(panel),
        reason=("Keep only months where both the 2s10s spread and USREC exist: USREC starts 1854 but the spread "
                "starts mid-1976; the current month has spreads but no USREC value yet."),
        details={"first_month": panel.index.min().strftime("%Y-%m"), "last_month": panel.index.max().strftime("%Y-%m")},
    )

    # >>> snippet: make_target
    future = pd.concat([panel["USREC"].shift(-k) for k in range(1, HORIZON + 1)], axis=1)
    panel["rec_next12"] = future.max(axis=1)
    panel.loc[future.isna().any(axis=1), "rec_next12"] = pd.NA
    # <<< snippet
    n_unknown = int(panel["rec_next12"].isna().sum())
    prov.log_transform(
        "fred_USREC", "target_unknown_last_months", len(panel), len(panel) - n_unknown,
        reason=(f"The last {HORIZON} months do not yet have a full {HORIZON}-month future, so their target is "
                "unknown. They are excluded from model fitting/evaluation but kept for the 'signal today' reading."),
        details={"rows_flagged_unknown": n_unknown},
    )

    # >>> snippet: model_sample
    known = panel["rec_next12"].notna()
    panel["model_sample"] = known & (panel["USREC"] == 0)
    # <<< snippet
    prov.log_transform(
        "fred_USREC", "exclude_current_recession", int(known.sum()), int(panel["model_sample"].sum()),
        reason=("Months already IN a recession are excluded from fitting and scoring. The decision is made during "
                "expansions; inside a recession the target is trivially 1 while the curve has re-steepened (rate "
                "cuts), which teaches the model the opposite relationship. First attempt kept them: in-sample "
                "pseudo-R2 was about 0.05 and out-of-sample skill was negative (kept as results *_all_months)."),
        details={"recession_months_excluded": int((known & (panel["USREC"] == 1)).sum())},
    )
    return panel


def clean() -> pd.DataFrame:
    prov = Provenance(CASE_DIR)
    panel = build_panel(prov)
    with capture_output(CASE_DIR, "panel_tail"):
        print(panel[["T10Y2Y", "T10Y3M", "USREC", "rec_next12"]].tail(14).round(2).to_string())
    prov.save()
    panel.to_csv(CASE_DIR / "clean_panel.csv")
    return panel


if __name__ == "__main__":
    clean()
