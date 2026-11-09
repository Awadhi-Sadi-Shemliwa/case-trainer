"""P50 · Analyse: does an inverted yield curve warn of a US recession in the next 12 months?

Reads the cleaned monthly panel (clean.py) and writes every number to expected_results.json,
the real printed outputs to captured_outputs.json and four charts to charts/.

Design choices (each one is taught in the case and logged in docs/knowledge/cases/p50_yield_curve.md):
* Target: rec_next12[t] = 1 if NBER recession in ANY month t+1..t+12 (stated in clean.py).
* "Inverted" = the MONTHLY MEAN spread is below zero (daily one-day dips are ignored).
* Inversion episodes: runs of inverted months, merged when separated by <= MERGE_GAP normal months.
* A recession is "signalled" if the spread was inverted in the LEAD_WINDOW months before it began.
* Modelling sample: months NOT already in recession (clean.py `model_sample`). A first attempt that
  kept recession months failed (weak fit, negative out-of-sample skill); its numbers are kept as
  *_all_months results so the case can show why the plan was changed.
* Models: univariate probit (Estrella-Mishkin / NY Fed style); HAC (Newey-West) standard errors with
  maxlags = HORIZON because overlapping 12-month targets make neighbouring errors correlated.
* Out-of-sample: expanding window. At forecast month t the model may only use rows s <= t - HORIZON,
  because the target of row s needs USREC up to s + HORIZON. Using later rows leaks the future.
* Primary model for the decision is the 10y-3m spread, chosen BEFORE looking at test results because
  it is the literature benchmark (NY Fed). 2s10s is the owner's question and is reported alongside.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy.stats import norm
from sklearn.metrics import brier_score_loss, roc_auc_score, roc_curve

from common.charts import Axis, Chart, ReferenceLine, export_chart, make_series, regions_from_indicator
from common.io import capture_output
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
HORIZON = 12        # months ahead (must match clean.py)
LEAD_WINDOW = 24    # months before a recession start in which an inversion counts as a warning
MERGE_GAP = 3       # normal months allowed inside one inversion episode
HAC_LAGS = HORIZON
SPLIT_FROM, SPLIT_BEFORE = "2022-01", "2021-12"   # diagnostic split only (see oos())
THRESHOLD_GRID =np.round(np.arange(0.05, 0.951, 0.05), 2)
SPREADS = {"T10Y2Y": "2s10s", "T10Y3M": "10y-3m"}
SOURCE_NOTE = "Data: FRED T10Y2Y, T10Y3M, USREC (Federal Reserve Bank of St. Louis); NBER recession dates."


def load_panel() -> pd.DataFrame:
    p = pd.read_csv(CASE_DIR / "clean_panel.csv", parse_dates=["observation_date"], index_col="observation_date")
    p.index.freq = "MS"
    p["model_sample"] = p["model_sample"].astype(bool)
    return p


def month_diff(a: pd.Timestamp, b: pd.Timestamp) -> int:
    return (a.year - b.year) * 12 + (a.month - b.month)


def runs(flag: pd.Series) -> list[tuple[pd.Timestamp, pd.Timestamp]]:
    """Contiguous runs where flag is True -> [(first_month, last_month)]."""
    out, start, prev = [], None, None
    for d, v in flag.items():
        if v and start is None:
            start = d
        if not v and start is not None:
            out.append((start, prev))
            start = None
        prev = d
    if start is not None:
        out.append((start, prev))
    return out


def recession_episodes(p: pd.DataFrame) -> list[tuple[pd.Timestamp, pd.Timestamp]]:
    return runs(p["USREC"] == 1)


def inversion_episodes(spread: pd.Series) -> list[tuple[pd.Timestamp, pd.Timestamp]]:
    raw = runs(spread.dropna() < 0)
    merged: list[list[pd.Timestamp]] = []
    for s, e in raw:
        if merged and month_diff(s, merged[-1][1]) - 1 <= MERGE_GAP:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    return [(s, e) for s, e in merged]


# --------------------------------------------------------------------------- 1. descriptives
def descriptives(p: pd.DataFrame, rs: ResultStore) -> None:
    known = p.dropna(subset=["rec_next12"])
    recs = recession_episodes(p)
    rs.put("sample_start", p.index.min().strftime("%Y-%m"), "month", "First month with both 2s10s and USREC")
    rs.put("sample_end", p.index.max().strftime("%Y-%m"), "month", "Last month with USREC (latest data)")
    rs.put("n_months", len(p), "months", "Months in the cleaned panel")
    rs.put("n_months_known_target", len(known), "months", "Months whose 12-month-ahead target is known")
    rs.put("last_known_target_month", known.index.max().strftime("%Y-%m"), "month",
           "Last month whose full 12-month future is observed")
    rs.put("n_recessions", len(recs), "recessions", "NBER recessions that start inside the panel window")
    rs.put("recession_months", int(p["USREC"].sum()), "months", "Months in recession (USREC = 1)")
    rs.put("recession_share", float(p["USREC"].mean()), "share", "Share of panel months in recession",
           decimals=1, pct=True)
    model = p[p["model_sample"]]
    rs.put("n_model_months", len(model), "months", "Expansion months with a known target (modelling sample)")
    rs.put("n_recession_months_excluded", int((known["USREC"] == 1).sum()), "months",
           "Months already in recession, excluded from fitting and scoring")
    rs.put("base_rate_next12", float(model["rec_next12"].mean()), "share",
           "Share of expansion months followed by a recession within 12 months (the base rate)", decimals=1, pct=True)
    rs.put("t10y3m_start", p["T10Y3M"].first_valid_index().strftime("%Y-%m"), "month",
           "First month of the 10y-3m series")
    for col, tag in (("T10Y2Y", "2s10s"), ("T10Y3M", "10y3m")):
        rs.put(f"inverted_months_{tag}", int((p[col] < 0).sum()), "months",
               f"Months with a negative monthly-mean {SPREADS[col]} spread")
        rs.put(f"spread_mean_{tag}", float(p[col].mean()), "percentage points",
               f"Average {SPREADS[col]} spread over the sample")
        rs.put(f"spread_min_{tag}", float(p[col].min()), "percentage points", f"Lowest monthly {SPREADS[col]} spread")
        rs.put(f"spread_min_month_{tag}", p[col].idxmin().strftime("%Y-%m"), "month",
               f"Month of the lowest {SPREADS[col]} spread")


# --------------------------------------------------------------------------- 2. lead times
def lead_table(p: pd.DataFrame, col: str) -> pd.DataFrame:
    spread = p[col]
    first = spread.first_valid_index()
    rows = []
    # >>> snippet: lead_table
    for start, end in recession_episodes(p):
        window = spread[start - pd.DateOffset(months=LEAD_WINDOW): start - pd.DateOffset(months=1)]
        if start - pd.DateOffset(months=LEAD_WINDOW) < first:
            rows.append({"recession_start": start, "first_inverted": None, "lead_months": None,
                         "status": "no data before"})
            continue
        inverted = window[window < 0]
        if inverted.empty:
            rows.append({"recession_start": start, "first_inverted": None, "lead_months": None,
                         "status": "MISSED"})
        else:
            first_inv = inverted.index.min()
            rows.append({"recession_start": start, "first_inverted": first_inv,
                         "lead_months": month_diff(start, first_inv), "status": "signalled"})
    table = pd.DataFrame(rows)
    # <<< snippet
    return table


def false_alarms(p: pd.DataFrame, col: str) -> pd.DataFrame:
    starts = [s for s, _ in recession_episodes(p)]
    last_usrec = p.index.max()
    rows = []
    for s, e in inversion_episodes(p[col]):
        followed = [r for r in starts if 0 <= month_diff(r, s) <= LEAD_WINDOW]
        window_end = s + pd.DateOffset(months=LEAD_WINDOW)
        status = "followed by recession" if followed else (
            "FALSE ALARM" if window_end <= last_usrec else "FALSE ALARM so far (window still open)")
        rows.append({"inversion_start": s, "inversion_end": e,
                     "months_inverted": month_diff(e, s) + 1, "status": status})
    return pd.DataFrame(rows)


def leads(p: pd.DataFrame, rs: ResultStore) -> dict[str, pd.DataFrame]:
    out = {}
    for col, tag in (("T10Y2Y", "2s10s"), ("T10Y3M", "10y3m")):
        with capture_output(CASE_DIR, f"lead_table_{tag}"):
            t = lead_table(p, col)
            print(t.assign(recession_start=t.recession_start.dt.strftime("%Y-%m"),
                           first_inverted=pd.to_datetime(t.first_inverted).dt.strftime("%Y-%m"),
                           lead_months=t.lead_months.astype("Int64").astype(str).replace("<NA>", "-"))
                  .fillna("-").to_string(index=False))
        with capture_output(CASE_DIR, f"inversion_episodes_{tag}"):
            fa = false_alarms(p, col)
            print(fa.assign(inversion_start=fa.inversion_start.dt.strftime("%Y-%m"),
                            inversion_end=fa.inversion_end.dt.strftime("%Y-%m")).to_string(index=False))
        sig = t[t.status == "signalled"]
        evaluable = t[t.status != "no data before"]
        suffix = "" if tag == "2s10s" else f"_{tag}"
        rs.put(f"median_lead_months{suffix}", float(sig.lead_months.median()), "months",
               f"Median months from first {SPREADS[col]} inversion to recession start (signalled recessions)",
               decimals=0)
        rs.put(f"min_lead_months{suffix}", int(sig.lead_months.min()), "months",
               f"Shortest {SPREADS[col]} inversion-to-recession lead")
        rs.put(f"max_lead_months{suffix}", int(sig.lead_months.max()), "months",
               f"Longest {SPREADS[col]} inversion-to-recession lead")
        rs.put(f"recessions_signalled_{tag}", len(sig), "recessions",
               f"Recessions preceded by a {SPREADS[col]} inversion within {LEAD_WINDOW} months")
        rs.put(f"recessions_evaluable_{tag}", len(evaluable), "recessions",
               f"Recessions with {LEAD_WINDOW} months of {SPREADS[col]} data before them")
        rs.put(f"inversion_episodes_{tag}", len(fa), "episodes", f"Separate {SPREADS[col]} inversion episodes")
        rs.put(f"false_alarm_episodes_{tag}", int(fa.status.str.startswith("FALSE").sum()), "episodes",
               f"{SPREADS[col]} inversion episodes NOT followed by a recession within {LEAD_WINDOW} months")
        out[tag] = t
    rs.put("lead_window_months", LEAD_WINDOW, "months", "How far before a recession an inversion counts as a warning")
    return out


# --------------------------------------------------------------------------- 3. in-sample models
def fit_probit(y: pd.Series, x: pd.Series, hac: bool = True):
    X = sm.add_constant(x.rename("spread"))
    # >>> snippet: probit_hac
    model = sm.Probit(y, X)
    if hac:
        res = model.fit(disp=0, cov_type="HAC", cov_kwds={"maxlags": HAC_LAGS})
    else:
        res = model.fit(disp=0)
    # <<< snippet
    return res


def in_sample(p: pd.DataFrame, rs: ResultStore) -> dict:
    allm = p.dropna(subset=["rec_next12", "T10Y3M"])
    common = allm[allm["model_sample"]]
    rs.put("common_sample_start", common.index.min().strftime("%Y-%m"), "month",
           "Start of the sample where both spreads exist (model comparison)")
    rs.put("n_common", len(common), "months", "Months in the common model-comparison sample")
    fits = {}
    with capture_output(CASE_DIR, "probit_summary"):
        for col, tag in (("T10Y2Y", "2s10s"), ("T10Y3M", "10y3m")):
            y = common["rec_next12"].astype(int)
            r = fit_probit(y, common[col])
            naive = fit_probit(y, common[col], hac=False)
            auc = roc_auc_score(y, r.predict())
            print(f"{SPREADS[col]:>7}: slope {r.params['spread']:+.3f}  HAC se {r.bse['spread']:.3f}  "
                  f"naive se {naive.bse['spread']:.3f}  p(HAC) {r.pvalues['spread']:.4f}  "
                  f"pseudo-R2 {r.prsquared:.3f}  in-sample AUC {auc:.3f}")
            rs.put(f"probit_const_{tag}", float(r.params["const"]), "index", f"Probit intercept, {SPREADS[col]}", decimals=3)
            rs.put(f"probit_slope_{tag}", float(r.params["spread"]), "per percentage point",
                   f"Probit slope on the {SPREADS[col]} spread", decimals=3)
            rs.put(f"probit_se_hac_{tag}", float(r.bse["spread"]), "per percentage point",
                   f"HAC (Newey-West, {HAC_LAGS} lags) standard error of the {SPREADS[col]} slope", decimals=3)
            rs.put(f"probit_se_naive_{tag}", float(naive.bse["spread"]), "per percentage point",
                   f"Naive (non-robust) standard error of the {SPREADS[col]} slope", decimals=3)
            rs.put(f"se_ratio_{tag}", float(r.bse["spread"] / naive.bse["spread"]), "ratio",
                   f"HAC / naive standard error, {SPREADS[col]}: how much overlap inflates uncertainty", decimals=1)
            rs.put(f"probit_p_hac_{tag}", float(r.pvalues["spread"]), "p-value",
                   f"HAC p-value of the {SPREADS[col]} slope", decimals=4)
            rs.put(f"pseudo_r2_{tag}", float(r.prsquared), "McFadden R2", f"Pseudo R-squared, {SPREADS[col]} probit", decimals=3)
            rs.put(f"auc_insample_{tag}", float(auc), "AUC", f"In-sample AUC, {SPREADS[col]} probit (optimistic)", decimals=3)
            fits[tag] = r
            # The first plan (keep months already in recession) - kept to show why it was rejected.
            ya = allm["rec_next12"].astype(int)
            ra = fit_probit(ya, allm[col], hac=False)
            auc_a = roc_auc_score(ya, ra.predict())
            print(f"{'':>7}  first plan incl. recession months: pseudo-R2 {ra.prsquared:.3f}  AUC {auc_a:.3f}")
            rs.put(f"pseudo_r2_all_months_{tag}", float(ra.prsquared), "McFadden R2",
                   f"Pseudo R-squared when months already in recession are kept (rejected plan), {SPREADS[col]}",
                   decimals=3)
            rs.put(f"auc_insample_all_months_{tag}", float(auc_a), "AUC",
                   f"In-sample AUC when months already in recession are kept (rejected plan), {SPREADS[col]}",
                   decimals=3)
        logit = sm.Logit(common["rec_next12"].astype(int), sm.add_constant(common["T10Y3M"].rename("spread"))).fit(
            disp=0, cov_type="HAC", cov_kwds={"maxlags": HAC_LAGS})
        print(f" logit 10y-3m slope {logit.params['spread']:+.3f} (probit x ~1.6-1.8 is normal: different link scale)")
    rs.put("logit_slope_10y3m", float(logit.params["spread"]), "per percentage point",
           "Logit slope on 10y-3m (for comparison with probit)", decimals=3)
    rs.put("hac_lags", HAC_LAGS, "months", "Newey-West lag length used for HAC standard errors")
    return fits


# --------------------------------------------------------------------------- 4. expanding-window OOS
def first_oos_month(p: pd.DataFrame, train_start: pd.Timestamp) -> pd.Timestamp:
    """First forecast month t at which >= 2 recession episodes are complete and visible to training
    (episode ends <= t and overlaps the training sample), so the model has seen more than one event."""
    complete = [e for s, e in recession_episodes(p) if e > train_start]
    return complete[1] + pd.DateOffset(months=1)


def expanding_oos(p: pd.DataFrame, col: str, start: pd.Timestamp, train_start: pd.Timestamp) -> pd.DataFrame:
    data = p.loc[train_start:]
    rows = []
    # >>> snippet: expanding_oos
    for t in data.loc[start:].index:
        cutoff = t - pd.DateOffset(months=HORIZON)        # embargo: row s needs USREC up to s+12
        train = data.loc[:cutoff]
        train = train[train["model_sample"]].dropna(subset=[col])
        res = sm.Probit(train["rec_next12"].astype(int), sm.add_constant(train[col])).fit(disp=0)
        prob = float(res.predict([1.0, data.at[t, col]])[0])
        rows.append({"month": t, "prob": prob, "actual": data.at[t, "rec_next12"],
                     "scored": bool(data.at[t, "model_sample"]),
                     "climatology": float(train["rec_next12"].mean()), "n_train": len(train)})
    # <<< snippet
    return pd.DataFrame(rows).set_index("month")


def oos(p: pd.DataFrame, rs: ResultStore) -> dict[str, pd.DataFrame]:
    train_start = p["T10Y3M"].first_valid_index()
    start = first_oos_month(p, train_start)
    rs.put("oos_start", start.strftime("%Y-%m"), "month",
           "First out-of-sample forecast month (two complete recessions already in training)")
    rs.put("split_from", SPLIT_FROM, "month",
           "Start of the post-hoc diagnostic split: the latest inversion cycle, not followed by a recession so far")
    out = {}
    with capture_output(CASE_DIR, "oos_metrics"):
        print(f"forecast months from {start:%Y-%m}; training rows end 12 months before each forecast")
        for col, tag in (("T10Y2Y", "2s10s"), ("T10Y3M", "10y3m")):
            f = expanding_oos(p, col, start, train_start)
            ev = f[f["scored"]]
            y = ev["actual"].astype(int)
            auc = roc_auc_score(y, ev["prob"])
            brier = brier_score_loss(y, ev["prob"])
            brier_clim = brier_score_loss(y, ev["climatology"])
            bss = 1 - brier / brier_clim
            print(f"{SPREADS[col]:>7}: OOS AUC {auc:.3f}  Brier {brier:.4f}  climatology Brier {brier_clim:.4f}  "
                  f"skill {bss:+.3f}")
            # Post-hoc diagnostic (NOT model selection): where does the lost skill come from?
            # Split at the start of the latest inversion cycle, which (so far) has no recession after it.
            pre, post = ev.loc[:SPLIT_BEFORE], ev.loc[SPLIT_FROM:]
            bss_pre = 1 - brier_score_loss(pre["actual"].astype(int), pre["prob"]) / brier_score_loss(
                pre["actual"].astype(int), pre["climatology"])
            print(f"{'':>7}  split diagnostic: skill before {SPLIT_FROM[:4]} {bss_pre:+.3f} | from {SPLIT_FROM[:4]}: "
                  f"{len(post)} months, {int(post['actual'].sum())} followed by recession, mean P {post['prob'].mean():.3f}")
            rs.put(f"bss_oos_pre_split_{tag}", float(bss_pre), "skill score",
                   f"Brier skill score for forecasts before {SPLIT_FROM[:4]}, {SPREADS[col]} (post-hoc diagnostic)",
                   decimals=3)
            rs.put(f"mean_prob_post_split_{tag}", float(post["prob"].mean()), "probability",
                   f"Average forecast probability from {SPLIT_FROM[:4]} on, {SPREADS[col]} (no recession followed)",
                   decimals=0, pct=True)
            rs.put(f"n_post_split_months_{tag}", len(post), "months",
                   f"Scored months from {SPLIT_FROM[:4]} on, {SPREADS[col]}")
            rs.put(f"n_post_split_positive_{tag}", int(post["actual"].sum()), "months",
                   f"Scored months from {SPLIT_FROM[:4]} on that were followed by a recession, {SPREADS[col]}")
            rs.put(f"auc_oos_{tag}", float(auc), "AUC", f"Out-of-sample AUC, {SPREADS[col]} probit", decimals=3)
            rs.put(f"brier_oos_{tag}", float(brier), "Brier", f"Out-of-sample Brier score, {SPREADS[col]}", decimals=4)
            rs.put(f"brier_clim_{tag}", float(brier_clim), "Brier",
                   "Brier score of always forecasting the historical base rate (climatology)", decimals=4)
            rs.put(f"bss_oos_{tag}", float(bss), "skill score",
                   f"Brier skill score vs climatology, {SPREADS[col]} (>0 = better than base rate)", decimals=3)
            out[tag] = f
        ev = out["10y3m"][out["10y3m"]["scored"]]
        print(f"evaluated months {len(ev)}, of which followed by recession {int(ev.actual.sum())}")
    rs.put("n_oos_months", len(ev), "months", "Out-of-sample expansion months with a known target (scored)")
    rs.put("n_oos_positive", int(ev["actual"].sum()), "months", "Out-of-sample months followed by a recession")
    oos_recs = [s for s, _ in recession_episodes(p) if s > start]
    rs.put("n_oos_recessions", len(oos_recs), "recessions", "Recessions that start in the out-of-sample period")
    return out


# --------------------------------------------------------------------------- 5. decision threshold
def choose_threshold(p: pd.DataFrame, oos_start: pd.Timestamp) -> float:
    """Pick the threshold using ONLY data known at the first forecast month (no peeking at the test).
    Rule: maximise Youden's J = hit rate - false-alarm rate on the training-period fit."""
    train_start = p["T10Y3M"].first_valid_index()
    train = p.loc[train_start: oos_start - pd.DateOffset(months=HORIZON)]
    train = train[train["model_sample"]].dropna(subset=["T10Y3M"])
    y = train["rec_next12"].astype(int)
    prob = fit_probit(y, train["T10Y3M"], hac=False).predict()
    # >>> snippet: choose_threshold
    best, best_j = None, -1.0
    for th in THRESHOLD_GRID:
        signal = prob >= th
        hit_rate = (signal & (y == 1)).sum() / (y == 1).sum()
        false_alarm_rate = (signal & (y == 0)).sum() / (y == 0).sum()
        if hit_rate - false_alarm_rate > best_j:
            best, best_j = float(th), hit_rate - false_alarm_rate
    # <<< snippet
    return best


def decision(p: pd.DataFrame, f: pd.DataFrame, fits: dict, rs: ResultStore) -> float:
    oos_start = f.index.min()
    th = choose_threshold(p, oos_start)
    rs.put("threshold", th, "probability", "Signal threshold chosen on training data only (max Youden J)",
           decimals=0, pct=True)
    ev = f[f["scored"]]
    signal = ev["prob"] >= th
    y = ev["actual"].astype(int)
    rs.put("oos_hit_rate", float((signal & (y == 1)).sum() / (y == 1).sum()), "share",
           "Share of pre-recession months (target = 1) where the 10y-3m signal was on (OOS)", decimals=0, pct=True)
    rs.put("oos_false_alarm_rate", float((signal & (y == 0)).sum() / (y == 0).sum()), "share",
           "Share of calm months (target = 0) where the 10y-3m signal was on anyway (OOS)", decimals=0, pct=True)
    rs.put("oos_signal_precision", float((signal & (y == 1)).sum() / max(signal.sum(), 1)), "share",
           "When the 10y-3m signal was on, share of months a recession did follow within 12 months (OOS)",
           decimals=0, pct=True)
    # episode view: did the signal fire in the 18 months before each OOS recession, and how early?
    rows = []
    for s, _ in recession_episodes(p):
        if s <= oos_start:
            continue
        pre = f.loc[s - pd.DateOffset(months=18): s - pd.DateOffset(months=1), "prob"]
        on = pre[pre >= th]
        rows.append({"recession_start": s.strftime("%Y-%m"),
                     "first_signal": on.index.min().strftime("%Y-%m") if len(on) else "-",
                     "lead_months": month_diff(s, on.index.min()) if len(on) else None})
    table = pd.DataFrame(rows)
    with capture_output(CASE_DIR, "threshold_episodes"):
        print(f"threshold {th:.2f} (10y-3m probit, out-of-sample)")
        print(table.fillna("-").to_string(index=False))
    caught = table.dropna(subset=["lead_months"])
    rs.put("oos_recessions_caught", len(caught), "recessions",
           "OOS recessions with the 10y-3m signal on in the 18 months before they began")
    if len(caught):
        rs.put("oos_signal_median_lead", float(caught["lead_months"].median()), "months",
               "Median months from first 10y-3m signal to recession start (OOS)", decimals=0)
    # Translate the probability trigger into the spread level the desk can watch (full-sample fit).
    r = fits["10y3m"]
    trigger = (norm.ppf(th) - r.params["const"]) / r.params["spread"]
    rs.put("trigger_spread_10y3m", float(trigger), "percentage points",
           "10y-3m spread at which the full-sample probit probability equals the threshold", decimals=2)
    return th


# --------------------------------------------------------------------------- 6. today's reading
def today(p: pd.DataFrame, forecasts: dict[str, pd.DataFrame], th: float, rs: ResultStore) -> None:
    last = p.index.max()
    rs.put("latest_month", last.strftime("%Y-%m"), "month", "Latest month in the data")
    with capture_output(CASE_DIR, "today_signal"):
        for col, tag in (("T10Y2Y", "2s10s"), ("T10Y3M", "10y3m")):
            prob = float(forecasts[tag].at[last, "prob"])
            print(f"{last:%Y-%m}  {SPREADS[col]:>7} spread {p.at[last, col]:+.2f} pp  -> P(recession within 12m) {prob:.1%}")
            rs.put(f"latest_spread_{tag}", float(p.at[last, col]), "percentage points",
                   f"Latest monthly {SPREADS[col]} spread")
            rs.put(f"latest_prob_{tag}", prob, "probability",
                   f"Model probability of a recession in the next 12 months, latest month, {SPREADS[col]}",
                   decimals=1, pct=True)
    rs.put("latest_signal_10y3m", "ON" if forecasts["10y3m"].at[last, "prob"] >= th else "OFF", "flag",
           "Is the 10y-3m signal above the threshold in the latest month?")


# --------------------------------------------------------------------------- 7. charts
def charts(p: pd.DataFrame, fits: dict, forecasts: dict[str, pd.DataFrame], th: float) -> None:
    out = CASE_DIR / "charts"
    shaded = regions_from_indicator(p.index, p["USREC"], "NBER recession")
    export_chart(Chart(
        id="p50_spread_recessions", type="line",
        title="US yield-curve spreads and recessions",
        subtitle="Monthly mean spreads; grey = NBER recession months",
        x_axis=Axis(title="Month", kind="date"),
        y_axis=Axis(title="Spread", unit="percentage points"),
        series=[make_series("10y minus 2y (2s10s)", p.index, p["T10Y2Y"], unit="pp"),
                make_series("10y minus 3m", p.index, p["T10Y3M"], unit="pp")],
        shaded_regions=shaded,
        reference_lines=[ReferenceLine(axis="y", value=0, label="below zero = inverted")],
        source_note=SOURCE_NOTE,
        result_keys=["median_lead_months", "median_lead_months_10y3m", "false_alarm_episodes_2s10s",
                     "inverted_months_2s10s", "spread_min_2s10s"],
    ), out)

    known = p.dropna(subset=["rec_next12"])
    common = known[known["model_sample"]].dropna(subset=["T10Y3M"])
    grid = np.linspace(common["T10Y2Y"].min(), common["T10Y2Y"].max(), 120)
    r = fits["2s10s"]
    fitted = norm.cdf(r.params["const"] + r.params["spread"] * grid)
    bins = pd.cut(common["T10Y2Y"], bins=np.arange(-2.5, 3.01, 0.5))
    binned = common.groupby(bins, observed=True)["rec_next12"].agg(["mean", "count"])
    binned = binned[binned["count"] >= 5]
    export_chart(Chart(
        id="p50_spread_vs_forward", type="scatter",
        title="Spread today vs recession in the next 12 months",
        subtitle="Expansion months only. Dots: 1 = recession followed. Dashed: probit fit and share per half-point bin",
        x_axis=Axis(title="2s10s spread this month", unit="percentage points"),
        y_axis=Axis(title="Recession within 12 months", unit="0/1 or probability", min=-0.05, max=1.05),
        series=[make_series("Months (0 = no, 1 = yes)", common["T10Y2Y"], common["rec_next12"], downsample=False),
                make_series("Probit fitted probability", grid, fitted, role="fitted", downsample=False),
                make_series("Observed share in spread bin", [iv.mid for iv in binned.index], binned["mean"],
                            role="benchmark", downsample=False)],
        reference_lines=[ReferenceLine(axis="x", value=0, label="inversion")],
        source_note=SOURCE_NOTE,
        result_keys=["probit_slope_2s10s", "base_rate_next12", "pseudo_r2_2s10s"],
    ), out)

    f2, f3 = forecasts["2s10s"], forecasts["10y3m"]
    shaded_oos = regions_from_indicator(p.loc[f3.index.min():].index, p.loc[f3.index.min():, "USREC"], "NBER recession")
    export_chart(Chart(
        id="p50_oos_probability", type="line",
        title="Out-of-sample recession probability (next 12 months)",
        subtitle="Each month uses only data available then (12-month embargo)",
        x_axis=Axis(title="Forecast month", kind="date"),
        y_axis=Axis(title="Probability", unit="0-1", min=0, max=1),
        series=[make_series("10y-3m probit", f3.index, f3["prob"]),
                make_series("2s10s probit", f2.index, f2["prob"])],
        shaded_regions=shaded_oos,
        reference_lines=[ReferenceLine(axis="y", value=th, label="signal threshold")],
        source_note=SOURCE_NOTE,
        result_keys=["threshold", "auc_oos_10y3m", "auc_oos_2s10s", "latest_prob_10y3m", "oos_start"],
    ), out)

    series = []
    for tag, f in (("10y3m", f3), ("2s10s", f2)):
        ev = f[f["scored"]]
        fpr, tpr, _ = roc_curve(ev["actual"].astype(int), ev["prob"])
        series.append(make_series(f"{'10y-3m' if tag == '10y3m' else '2s10s'} (OOS)", fpr, tpr, downsample=False))
    series.append(make_series("Coin flip", [0, 1], [0, 1], role="benchmark", downsample=False))
    export_chart(Chart(
        id="p50_roc", type="line",
        title="Out-of-sample ROC curves",
        subtitle="Hit rate vs false-alarm rate across all thresholds",
        x_axis=Axis(title="False-alarm rate", unit="share of calm months", min=0, max=1),
        y_axis=Axis(title="Hit rate", unit="share of pre-recession months", min=0, max=1),
        series=series, source_note=SOURCE_NOTE,
        result_keys=["auc_oos_10y3m", "auc_oos_2s10s"],
    ), out)


def analyse() -> ResultStore:
    p = load_panel()
    rs = ResultStore(CASE_DIR)
    rs.put("horizon_months", HORIZON, "months", "Forecast horizon of the target")
    descriptives(p, rs)
    leads(p, rs)
    fits = in_sample(p, rs)
    forecasts = oos(p, rs)
    th = decision(p, forecasts["10y3m"], fits, rs)
    today(p, forecasts, th, rs)
    charts(p, fits, forecasts, th)
    rs.save()
    return rs


if __name__ == "__main__":
    analyse()
