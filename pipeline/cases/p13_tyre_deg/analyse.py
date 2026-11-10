"""P13 · Where is the tyre degradation cliff? Reads only the committed aggregates (aggregates/*.csv*).

Identification (the case's plan_challenge): within one stint, tyre_age = lap_number - constant, so a stint fixed
effect plus lap number cannot separate fuel burn from tyre wear. We use a driver-race fixed effect instead: across
a pit stop tyre age resets while lap number keeps rising, which separates the two. The lap-number slope still mixes
fuel burn with track evolution (both make laps faster over a race); that cannot be split with these data.

Cliff: a hinge term max(0, age - k) per compound, k chosen by grid search over ages with enough laps on both sides,
judged by leave-one-race-out (LORO) error against the straight line. Decision: split a stint when the wear saved
by an extra stop beats the pit loss: with linear wear s per lap, L* = 2 * sqrt(pit_loss / s).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy.stats import binomtest

from common.charts import Axis, Chart, ReferenceLine, export_chart, make_series
from common.io import capture_output
from common.results import ResultStore

from cases.p13_tyre_deg.clean import INCIDENT_S, TRAFFIC_GAP_S

CASE_DIR = Path(__file__).resolve().parent
AGG = CASE_DIR / "aggregates"
COMPOUNDS = ["SOFT", "MEDIUM", "HARD"]
MIN_LAPS_SIDE = 300       # a hinge at age k needs this many clean laps of the compound on EACH side of k
MIN_LAPS_AT_AGE = 30      # chart points: ages with at least this many laps
MIN_CIRCUIT_LAPS = 300    # circuit-level wear slope only with this many clean laps of the compound
FIXED_SET_MARGIN = 10     # fixed-set check: stints that reach at least break age + this many laps
MIN_FIXED_SET_STINTS = 20
MAX_STOPS = 4
EXAMPLE_MIN_LAPS = 30     # example stint: drawn from hard stints with at least this many clean laps
TRAIN_YEARS = (2023, 2024)
TEST_YEAR = 2025
SOURCE_NOTE = "Source: OpenF1 (openf1.org), CC BY-NC-SA 4.0. Dry races 2023-2025, clean green-flag laps."


# ----------------------------------------------------------------------------------------------- data
def load() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    laps = pd.read_csv(AGG / "laps.csv.gz")
    races = pd.read_csv(AGG / "races.csv")
    stints = pd.read_csv(AGG / "stints.csv")
    stops = pd.read_csv(AGG / "pit_stops.csv")
    laps = laps.merge(races[["session_key", "year", "circuit"]], on="session_key")
    return laps, races, stints, stops


def clean_laps(laps: pd.DataFrame) -> pd.DataFrame:
    c = laps[laps["drop_reason"].isna()].copy()
    c["group"] = c["session_key"].astype(str) + "_" + c["driver_number"].astype(str)
    return c.reset_index(drop=True)


def design(c: pd.DataFrame, hinges: dict[str, float] | None = None, lap: bool = True) -> pd.DataFrame:
    """Regressors before the fixed-effect transformation."""
    X = pd.DataFrame(index=c.index)
    if lap:
        X["lap_number"] = c["lap_number"].astype(float)
    for comp in COMPOUNDS[1:]:                        # SOFT is the base compound (offset absorbed with the FE)
        X[f"is_{comp}"] = (c["compound"] == comp).astype(float)
    for comp in COMPOUNDS:
        X[f"age_{comp}"] = c["tyre_age"].where(c["compound"] == comp, 0.0).astype(float)
    for comp, k in (hinges or {}).items():
        X[f"hinge_{comp}"] = (c["tyre_age"] - k).clip(lower=0).where(c["compound"] == comp, 0.0).astype(float)
    return X


def within(df: pd.DataFrame, groups: pd.Series) -> pd.DataFrame:
    return df - df.groupby(groups.values).transform("mean")


def fit_fe(c: pd.DataFrame, X: pd.DataFrame, groups: pd.Series):
    """OLS on within-transformed data (fixed effect = `groups`). SEs clustered by RACE: drivers in one race share
    track temperature and rubber, so their laps are not independent evidence."""
    # >>> snippet: fit_fe
    y = within(c[["lap_duration"]], groups)["lap_duration"]
    Xd = within(X, groups)
    keep = Xd.columns[(Xd.abs().sum() > 1e-9)]
    codes = pd.factorize(c["session_key"])[0]
    return sm.OLS(y, Xd[keep]).fit(cov_type="cluster", cov_kwds={"groups": codes})
    # <<< snippet


def race_lap_design(c: pd.DataFrame) -> pd.DataFrame:
    """Main design but with a separate lap-number slope per race (fuel per lap differs by circuit)."""
    X = design(c, lap=False)
    for sk in c["session_key"].unique():
        X[f"lap_{sk}"] = c["lap_number"].where(c["session_key"] == sk, 0).astype(float)
    return X


def lstsq_resid(y: np.ndarray, X: np.ndarray, train: np.ndarray) -> np.ndarray:
    beta, *_ = np.linalg.lstsq(X[train], y[train], rcond=None)
    return y - X @ beta


# ----------------------------------------------------------------------------------------------- steps
def overview(laps: pd.DataFrame, races: pd.DataFrame, c: pd.DataFrame, rs: ResultStore) -> None:
    rs.put("traffic_gap_s", TRAFFIC_GAP_S, "s", "Traffic rule: median gap to the car ahead below this", decimals=1)
    rs.put("incident_s", INCIDENT_S, "s", "Incident rule: slower than the stint median by more than this", decimals=0)
    rs.put("n_races", len(races), "races", "Completed Grand Prix races 2023-2025 in OpenF1")
    rs.put("n_wet_races", int(races["wet"].sum()), "races", "Races excluded as wet (intermediate or wet tyres used)")
    rs.put("n_incomplete_races", int((races["incomplete"] & ~races["wet"]).sum()), "races",
           "Dry races excluded because the lap feed is incomplete")
    rs.put("n_dry_races", int((~races["wet"] & ~races["incomplete"]).sum()), "races", "Dry races analysed")
    rs.put("n_laps_dry", len(laps), "laps", "All laps in dry races")
    rs.put("n_laps_clean", len(c), "laps", "Clean green-flag laps used for modelling")
    rs.put("share_clean", len(c) / len(laps), "share", "Share of dry-race laps kept", pct=True)
    for r, n in laps["drop_reason"].value_counts().items():
        rs.put(f"n_drop_{r}", int(n), "laps", f"Laps dropped as {r}")
    rs.put("share_drop_traffic", float((laps["drop_reason"] == "traffic").mean()), "share",
           "Share of dry-race laps dropped as traffic", pct=True)
    for comp in COMPOUNDS:
        rs.put(f"n_clean_{comp.lower()}", int((c["compound"] == comp).sum()), "laps", f"Clean laps on {comp}")
    g = c.groupby("group")["stint_number"].nunique()
    rs.put("n_driver_races", int(len(g)), "driver-races", "Driver-race combinations with clean laps")
    rs.put("share_multi_stint", float((g >= 2).mean()), "share",
           "Driver-races with clean laps in 2+ stints (only these separate fuel from wear)", pct=True)
    rs.put("share_stints_used_tyres", float((c.groupby(["group", "stint_number"])["tyre_age"].min() > 2).mean()),
           "share", "Stints whose first clean lap is on tyres already 3+ laps old (used sets)", pct=True)


def identification(c: pd.DataFrame, rs: ResultStore) -> dict:
    stint = c["group"] + "_" + c["stint_number"].astype(int).astype(str)
    d = within(c[["tyre_age", "lap_number"]].astype(float), stint)
    corr = float(np.corrcoef(d["tyre_age"], d["lap_number"])[0, 1])
    rs.put("within_stint_corr_age_lap", corr, "correlation",
           "Correlation of tyre age and lap number after removing stint means (1 = cannot be separated)", decimals=3)
    X = design(c)[["lap_number", "age_SOFT", "age_MEDIUM", "age_HARD"]]
    rank = int(np.linalg.matrix_rank(within(X, stint).to_numpy(), tol=1e-6))
    rs.put("stint_fe_rank", rank, "columns", "Rank of [lap number, age by compound] after stint demeaning")
    rs.put("stint_fe_columns", X.shape[1], "columns", "Columns in that design")
    naive = fit_fe(c, design(c, lap=False)[["age_SOFT", "age_MEDIUM", "age_HARD"]], stint)
    for comp in COMPOUNDS:
        rs.put(f"naive_slope_{comp.lower()}", float(naive.params[f"age_{comp}"]), "s per lap",
               f"{comp}: stint-FE slope on tyre age WITHOUT a fuel control (fuel + wear mixed)", decimals=3)
    return {"naive": naive}


def main_model(c: pd.DataFrame, rs: ResultStore) -> dict:
    m = fit_fe(c, design(c), c["group"])
    rs.put("fuel_slope", float(m.params["lap_number"]), "s per lap",
           "Lap-number slope (fuel burn + track evolution), driver-race FE", decimals=3)
    lo, hi = m.conf_int().loc["lap_number"]
    rs.put("fuel_slope_lo", float(lo), "s per lap", "95% CI lower, lap-number slope", decimals=3)
    rs.put("fuel_slope_hi", float(hi), "s per lap", "95% CI upper, lap-number slope", decimals=3)
    for comp in COMPOUNDS:
        k = f"age_{comp}"
        lo, hi = m.conf_int().loc[k]
        rs.put(f"deg_{comp.lower()}", float(m.params[k]), "s per lap of age",
               f"{comp}: lap-time loss per lap of tyre age, fuel-controlled (driver-race FE)", decimals=3)
        rs.put(f"deg_{comp.lower()}_lo", float(lo), "s per lap of age", f"{comp}: 95% CI lower", decimals=3)
        rs.put(f"deg_{comp.lower()}_hi", float(hi), "s per lap of age", f"{comp}: 95% CI upper", decimals=3)
        rs.put(f"deg_{comp.lower()}_p", float(m.pvalues[k]), "p-value", f"{comp}: p-value of the wear slope", decimals=4)
    rs.put("rsq_within", float(m.rsquared), "R-squared", "Within R-squared of the main model", decimals=3)
    with capture_output(CASE_DIR, "wear_table"):
        print(f"{'compound':<8} {'no fuel control':>16} {'fuel-controlled':>16} {'95% CI':>18}  (s per lap of tyre age)")
        for comp in COMPOUNDS:
            lc = comp.lower()
            print(f"{comp:<8} {rs.results[f'naive_slope_{lc}']['display']:>16} {rs.results[f'deg_{lc}']['display']:>16} "
                  f"{rs.results[f'deg_{lc}_lo']['display'] + ' to ' + rs.results[f'deg_{lc}_hi']['display']:>18}")
        print(f"lap-number slope (fuel burn + track evolution): {rs.results['fuel_slope']['display']} s per lap")
    return {"main": m}


def hinge_grid(c: pd.DataFrame, comp: str) -> list[int]:
    ages = c.loc[c["compound"] == comp, "tyre_age"]
    return [int(k) for k in range(int(ages.min()) + 2, int(ages.max()))
            if (ages <= k).sum() >= MIN_LAPS_SIDE and (ages > k).sum() >= MIN_LAPS_SIDE]


def cliff(c: pd.DataFrame, rs: ResultStore) -> dict:
    """Per compound: best hinge in-sample, then LORO comparison of line vs hinge (hinge re-chosen in each fold)."""
    groups = c["group"]
    y = within(c[["lap_duration"]], groups)["lap_duration"].to_numpy()
    base = within(design(c), groups)
    races = c["session_key"].to_numpy()
    out = {}
    for comp in COMPOUNDS:
        grid = hinge_grid(c, comp)
        rs.put(f"cliff_grid_n_{comp.lower()}", len(grid), "ages", f"{comp}: candidate break ages with enough laps both sides")
        if not grid:
            out[comp] = None
            continue
        H = {k: within(design(c, {comp: k})[[f"hinge_{comp}"]], groups).to_numpy() for k in grid}
        B = base.to_numpy()
        sse = {k: float((lstsq_resid(y, np.hstack([B, H[k]]), np.ones(len(y), bool)) ** 2).sum()) for k in grid}
        k_best = min(sse, key=sse.get)
        full = fit_fe(c, design(c, {comp: k_best}), groups)
        mask_c = (c["compound"] == comp).to_numpy()
        lin_err, hin_err, wins, n_races = [], [], 0, 0
        for r in np.unique(races[mask_c]):
            test = races == r
            train = ~test
            e_lin = lstsq_resid(y, B, train)[test & mask_c]
            # choose k on training races only (nested), then score the held-out race
            k_tr = min(grid, key=lambda k: float((lstsq_resid(y, np.hstack([B, H[k]]), train)[train] ** 2).sum()))
            e_hin = lstsq_resid(y, np.hstack([B, H[k_tr]]), train)[test & mask_c]
            lin_err.append(e_lin ** 2); hin_err.append(e_hin ** 2)
            n_races += 1
            wins += int((e_hin ** 2).mean() < (e_lin ** 2).mean())
        rmse_lin = float(np.sqrt(np.concatenate(lin_err).mean()))
        rmse_hin = float(np.sqrt(np.concatenate(hin_err).mean()))
        extra = float(full.params[f"hinge_{comp}"])
        sign_p = float(binomtest(wins, n_races, 0.5, alternative="greater").pvalue)
        # a cliff = the break helps out of sample, in more races than chance, AND steepens the curve. (No in-sample
        # p-value: the break age was picked on the same data, so that p-value would be optimistic.)
        supported = bool(rmse_hin < rmse_lin and sign_p < 0.05 and extra > 0)
        lc = comp.lower()
        rs.put(f"cliff_age_{lc}", k_best, "laps of age", f"{comp}: best break age in-sample")
        rs.put(f"cliff_extra_slope_{lc}", extra, "s per lap of age", f"{comp}: extra wear per lap after the break", decimals=3)
        pre = float(full.params[f"age_{comp}"])
        rs.put(f"cliff_pre_slope_{lc}", pre, "s per lap of age", f"{comp}: wear slope before the break", decimals=3)
        rs.put(f"cliff_post_slope_{lc}", pre + extra, "s per lap of age", f"{comp}: wear slope after the break", decimals=3)
        rs.put(f"loro_sign_p_{lc}", sign_p, "p-value", f"{comp}: sign test, break wins more held-out races than chance",
               decimals=2)
        rs.put(f"loro_rmse_line_{lc}", rmse_lin, "s", f"{comp}: LORO RMSE, straight line", decimals=3)
        rs.put(f"loro_rmse_hinge_{lc}", rmse_hin, "s", f"{comp}: LORO RMSE, line with a break", decimals=3)
        rs.put(f"loro_gain_{lc}", 1 - rmse_hin / rmse_lin, "share", f"{comp}: LORO error reduction from the break", pct=True, decimals=2)
        rs.put(f"loro_wins_{lc}", wins, "races", f"{comp}: held-out races where the break model had lower error")
        rs.put(f"loro_races_{lc}", n_races, "races", f"{comp}: held-out races with laps on this compound")
        rs.put(f"cliff_supported_{lc}", "yes" if supported else "no", "",
               f"{comp}: break lowers held-out error, wins more races than chance, and steepens the curve")
        fixed_set(c, comp, k_best, rs)
        out[comp] = {"k": k_best, "supported": supported, "model": full}
    rs.put("n_compounds_with_cliff", sum(1 for v in out.values() if v and v["supported"]), "compounds",
           "Compounds where a steepening break holds out of sample (lower error, more race wins than chance)")
    return out


def fixed_set(c: pd.DataFrame, comp: str, k: int, rs: ResultStore) -> None:
    """Survivor-selection check: keep only stints that reach age k + FIXED_SET_MARGIN, so the same stints are present
    on both sides of the break. Fuel is removed with the main lap slope; stint fixed effect; hinge at the same k."""
    d = c[c["compound"] == comp].copy()
    d["stint"] = d["group"] + "_" + d["stint_number"].astype(int).astype(str)
    reach = d.groupby("stint")["tyre_age"].transform("max")
    d = d[reach >= k + FIXED_SET_MARGIN]
    n = d["stint"].nunique()
    lc = comp.lower()
    rs.put(f"fixedset_n_stints_{lc}", int(n), "stints", f"{comp}: stints reaching break age + {FIXED_SET_MARGIN} laps")
    if n < MIN_FIXED_SET_STINTS:
        rs.put(f"fixedset_extra_slope_{lc}", "too few stints", "", f"{comp}: fixed-set extra slope not estimated")
        return
    y = d["lap_duration"] - rs.results["fuel_slope"]["value"] * d["lap_number"]
    X = pd.DataFrame({"age": d["tyre_age"].astype(float), "hinge": (d["tyre_age"] - k).clip(lower=0).astype(float)})
    yd, Xd = within(y.to_frame("y"), d["stint"])["y"], within(X, d["stint"])
    m = sm.OLS(yd, Xd).fit(cov_type="cluster", cov_kwds={"groups": pd.factorize(d["session_key"])[0]})
    rs.put(f"fixedset_extra_slope_{lc}", float(m.params["hinge"]), "s per lap of age",
           f"{comp}: extra slope after the break using only stints that run well past it (same stints both sides)",
           decimals=3)
    rs.put(f"fixedset_extra_p_{lc}", float(m.pvalues["hinge"]), "p-value", f"{comp}: p-value of that extra slope",
           decimals=3)


def out_of_time(c: pd.DataFrame, rs: ResultStore) -> None:
    tr, te = c[c["year"].isin(TRAIN_YEARS)], c[c["year"] == TEST_YEAR]
    mt, me = fit_fe(tr, design(tr), tr["group"]), fit_fe(te, design(te), te["group"])
    for comp in COMPOUNDS:
        k = f"age_{comp}"
        rs.put(f"deg_{comp.lower()}_train", float(mt.params[k]), "s per lap of age", f"{comp}: wear slope 2023-24", decimals=3)
        rs.put(f"deg_{comp.lower()}_test", float(me.params[k]), "s per lap of age", f"{comp}: wear slope 2025 (refit)", decimals=3)
    rs.put("fuel_slope_train", float(mt.params["lap_number"]), "s per lap", "Lap slope 2023-24", decimals=3)
    rs.put("fuel_slope_test", float(me.params["lap_number"]), "s per lap", "Lap slope 2025", decimals=3)
    # predictive check: 2023-24 coefficients on 2025 vs an intercept-only (FE-only) benchmark
    y = within(te[["lap_duration"]], te["group"])["lap_duration"]
    Xd = within(design(te), te["group"])[mt.params.index]
    rmse_model = float(np.sqrt(((y - Xd @ mt.params) ** 2).mean()))
    rmse_fe = float(np.sqrt((y ** 2).mean()))
    rs.put("oot_rmse_model", rmse_model, "s", "2025 within-race RMSE with 2023-24 coefficients", decimals=3)
    rs.put("oot_rmse_fe_only", rmse_fe, "s", "2025 within-race RMSE with driver-race means only", decimals=3)
    rs.put("oot_gain", 1 - rmse_model / rmse_fe, "share", "Error reduction from fuel + wear terms out of time", pct=True)


def circuits(c: pd.DataFrame, rs: ResultStore) -> pd.DataFrame:
    """Per circuit: the full model on ALL that circuit's laps (every compound, so pit stops still separate fuel from
    wear), point estimates only (some circuits have one race, too few clusters for a standard error)."""
    rows = []
    for circ, g in c.groupby("circuit"):
        X = within(design(g), g["group"])
        X = X.loc[:, X.abs().sum() > 1e-9]
        y = within(g[["lap_duration"]], g["group"])["lap_duration"]
        beta = pd.Series(np.linalg.lstsq(X.to_numpy(), y.to_numpy(), rcond=None)[0], index=X.columns)
        if np.linalg.matrix_rank(X.to_numpy()) < X.shape[1]:
            continue                                          # not identified at this circuit
        for comp in ("MEDIUM", "HARD"):
            n = int((g["compound"] == comp).sum())
            if n >= MIN_CIRCUIT_LAPS and f"age_{comp}" in beta:
                rows.append({"circuit": circ, "compound": comp, "laps": n, "races": g["session_key"].nunique(),
                             "deg": float(beta[f"age_{comp}"])})
    t = pd.DataFrame(rows)
    with capture_output(CASE_DIR, "circuit_table"):
        print(f"Wear slope by circuit (s per lap of tyre age), circuits with {MIN_CIRCUIT_LAPS}+ clean laps:")
        print(t.sort_values(["compound", "deg"]).to_string(index=False, float_format=lambda v: f"{v:.3f}"))
    for comp in ("MEDIUM", "HARD"):
        s = t[t.compound == comp].sort_values("deg")
        lc = comp.lower()
        rs.put(f"n_circuits_{lc}", len(s), "circuits", f"{comp}: circuits with enough laps for their own slope")
        rs.put(f"circuit_max_{lc}", s.iloc[-1]["circuit"], "", f"{comp}: highest-wear circuit")
        rs.put(f"circuit_max_deg_{lc}", float(s.iloc[-1]["deg"]), "s per lap of age", f"{comp}: its wear slope", decimals=3)
        rs.put(f"circuit_min_{lc}", s.iloc[0]["circuit"], "", f"{comp}: lowest-wear circuit")
        rs.put(f"circuit_min_deg_{lc}", float(s.iloc[0]["deg"]), "s per lap of age", f"{comp}: its wear slope", decimals=3)
    return t


def km_curve(length: pd.Series, event: pd.Series) -> pd.Series:
    """Kaplan-Meier survival S(L) of stint length; stints that end at the flag (event False) are censored."""
    out, s = {}, 1.0
    for L in range(0, int(length.max()) + 1):
        at_risk = int((length >= L).sum())
        d = int(((length == L) & event).sum())
        if at_risk:
            s *= 1 - d / at_risk
        out[L] = s
    return pd.Series(out)


def km_median(S: pd.Series) -> float:
    below = S[S <= 0.5]
    return float(below.index[0]) if len(below) else float("nan")


def best_stops(s: float, P: float, R: float) -> int:
    """Stops that minimise wear + pit time for a race of R laps with linear wear s (equal stints)."""
    cost = {n: s * R ** 2 / (2 * (n + 1)) + n * P for n in range(MAX_STOPS + 1)}
    return min(cost, key=cost.get)


def decision(c: pd.DataFrame, stints: pd.DataFrame, stops: pd.DataFrame, laps: pd.DataFrame, circ: pd.DataFrame,
             rs: ResultStore) -> dict:
    s = stops[~stops["neutralised"]]
    per_race = s.groupby("session_key")["pit_loss"].median()
    P = float(per_race.median())
    rs.put("n_pit_stops_green", len(s), "stops", "Green-flag pit stops used for pit loss")
    rs.put("pit_loss", P, "s", "Median pit-stop time loss (median of race medians, green-flag stops)", decimals=1)
    rs.put("pit_loss_q25", float(per_race.quantile(0.25)), "s", "Pit loss, 25th percentile of race medians", decimals=1)
    rs.put("pit_loss_q75", float(per_race.quantile(0.75)), "s", "Pit loss, 75th percentile of race medians", decimals=1)
    R = float(laps.groupby("session_key")["race_laps"].first().median())
    rs.put("race_laps_median", R, "laps", "Median race length in laps", decimals=0)
    circ_of = c.groupby("session_key")["circuit"].first()
    circ_pit = per_race.groupby(per_race.index.map(circ_of)).median()
    out = {"pit_loss": P}
    for comp in COMPOUNDS:
        lc = comp.lower()
        sl, lo, hi = (rs.results[f"deg_{lc}"]["value"], rs.results[f"deg_{lc}_lo"]["value"], rs.results[f"deg_{lc}_hi"]["value"])
        # >>> snippet: split_length
        # linear wear s: a stint of L laps loses s*L^2/2; two stints of L/2 lose s*L^2/4; split when s*L^2/4 > P
        L = 2 * np.sqrt(P / sl)
        # <<< snippet
        rs.put(f"split_len_{lc}", float(L), "laps", f"{comp}: stint length above which an extra stop saves time (2*sqrt(P/s))", decimals=0)
        q25, q75 = rs.results["pit_loss_q25"]["value"], rs.results["pit_loss_q75"]["value"]
        rs.put(f"split_len_{lc}_short", float(2 * np.sqrt(q25 / hi)), "laps",
               f"{comp}: pooled-uncertainty low end (fast wear, cheap stop)", decimals=0)
        rs.put(f"split_len_{lc}_long", float(2 * np.sqrt(q75 / max(lo, 1e-6))), "laps",
               f"{comp}: pooled-uncertainty high end (slow wear, expensive stop)", decimals=0)
        rs.put(f"stops_wear_{lc}", best_stops(sl, P, R), "stops",
               f"{comp}: stops that minimise wear + pit time over a median-length race (wear alone)")
        st = stints[stints["compound"] == comp]
        S = km_curve(st["length"], st["ended_in_pit"].astype(bool))
        rs.put(f"stint_len_median_{lc}", km_median(S), "laps",
               f"{comp}: Kaplan-Meier median stint length (stints ending at the flag are censored)", decimals=0)
        rs.put(f"share_stints_to_flag_{lc}", float((~st["ended_in_pit"].astype(bool)).mean()), "share",
               f"{comp}: share of stints that ran to the chequered flag (censored)", pct=True)
        rs.put(f"km_running_at_split_{lc}", float(S.get(int(round(L)), S.iloc[-1])), "share",
               f"{comp}: Kaplan-Meier share of stints not yet pitted at the split length", pct=True)
        out[comp] = {"L": L, "km": S}
        if comp in ("MEDIUM", "HARD"):
            g = circ[(circ.compound == comp) & (circ.deg > 0)].copy()
            g["pit"] = g["circuit"].map(circ_pit)
            g = g.dropna(subset=["pit"])
            g["L"] = 2 * np.sqrt(g["pit"] / g["deg"])
            g = g.sort_values("L")
            rs.put(f"split_len_{lc}_circ_n", len(g), "circuits", f"{comp}: circuits with their own split length")
            rs.put(f"split_len_{lc}_circ_min", float(g["L"].iloc[0]), "laps", f"{comp}: shortest circuit split length", decimals=0)
            rs.put(f"split_len_{lc}_circ_min_at", g["circuit"].iloc[0], "", f"{comp}: circuit with the shortest split length")
            rs.put(f"split_len_{lc}_circ_median", float(g["L"].median()), "laps", f"{comp}: median circuit split length", decimals=0)
            rs.put(f"split_len_{lc}_circ_max", float(g["L"].iloc[-1]), "laps", f"{comp}: longest circuit split length", decimals=0)
            rs.put(f"split_len_{lc}_circ_max_at", g["circuit"].iloc[-1], "", f"{comp}: circuit with the longest split length")
    return out


def sensitivity(laps: pd.DataFrame, rs: ResultStore) -> None:
    """Re-fit the main model with a looser/stricter traffic gap and incident threshold (from the stored lap fields),
    and with a separate lap slope per race."""
    c0 = clean_laps(laps)
    m = fit_fe(c0, race_lap_design(c0), c0["group"])
    slopes = m.params[[k for k in m.params.index if k.startswith("lap_")]]
    for comp in COMPOUNDS:
        rs.put(f"deg_{comp.lower()}_racelap", float(m.params[f"age_{comp}"]), "s per lap of age",
               f"{comp}: wear slope with a separate lap slope per race", decimals=3)
    rs.put("fuel_slope_race_q25", float(slopes.quantile(0.25)), "s per lap", "Per-race lap slope, 25th percentile", decimals=3)
    rs.put("fuel_slope_race_q75", float(slopes.quantile(0.75)), "s per lap", "Per-race lap slope, 75th percentile", decimals=3)
    # compound offset per race; the pooled is_MEDIUM / is_HARD dummies are their sum, so they are dropped
    X = design(c0).drop(columns=[f"is_{k}" for k in COMPOUNDS[1:]])
    # In a race with no soft laps the medium and hard offsets sum to one, so only medium (vs hard) is kept there.
    present = c0.groupby("session_key")["compound"].agg(set)
    offs = {f"off_{comp}_{sk}": ((c0["compound"] == comp) & (c0["session_key"] == sk)).astype(float)
            for sk, comps in present.items() for comp in COMPOUNDS[1:]
            if comp in comps and not ("SOFT" not in comps and comp == "HARD")}
    X = pd.concat([X, pd.DataFrame(offs, index=c0.index)], axis=1)
    m = fit_fe(c0, X, c0["group"])
    for comp in COMPOUNDS:
        rs.put(f"deg_{comp.lower()}_raceoffset", float(m.params[f"age_{comp}"]), "s per lap of age",
               f"{comp}: wear slope with a compound offset per race", decimals=3)
    temp = c0["track_temp"].fillna(c0.groupby("session_key")["track_temp"].transform("mean"))
    ok = temp.notna().to_numpy()
    ct = c0[ok].reset_index(drop=True)
    X = design(ct).assign(track_temp=temp[ok].to_numpy())
    m = fit_fe(ct, X, ct["group"])
    rs.put("temp_slope", float(m.params["track_temp"]), "s per degree C",
           "Lap-time change per degree of track temperature (within race)", decimals=3)
    for comp in COMPOUNDS:
        rs.put(f"deg_{comp.lower()}_temp", float(m.params[f"age_{comp}"]), "s per lap of age",
               f"{comp}: wear slope controlling for track temperature", decimals=3)
    base = laps[laps["drop_reason"].isna() | laps["drop_reason"].isin(["traffic", "incident"])]
    for tag, gap, inc in (("gap05", 0.5, 5.0), ("gap20", 2.0, 5.0), ("inc3", 1.0, 3.0), ("inc8", 1.0, 8.0)):
        keep = base[~(base["median_gap_ahead"] < gap)].copy()
        med = keep.groupby(["session_key", "driver_number", "stint_number"])["lap_duration"].transform("median")
        keep = keep[(keep["lap_duration"] - med) <= inc]
        c = clean_laps(keep.assign(drop_reason=np.nan))
        m = fit_fe(c, design(c), c["group"])
        for comp in COMPOUNDS:
            rs.put(f"deg_{comp.lower()}_{tag}", float(m.params[f"age_{comp}"]), "s per lap of age",
                   f"{comp}: wear slope with traffic gap {gap:g} s and incident {inc:g} s", decimals=3)
        rs.put(f"n_laps_{tag}", len(c), "laps", f"Clean laps with traffic gap {gap:g} s and incident {inc:g} s")


# ----------------------------------------------------------------------------------------------- charts
def charts(c: pd.DataFrame, stints: pd.DataFrame, fits: dict, cl: dict, dec: dict, rs: ResultStore) -> None:
    out = CASE_DIR / "charts"
    fuel = fits["main"].params["lap_number"]
    # 1. a TYPICAL long HARD stint (rule, not a hand pick): among hard stints with EXAMPLE_MIN_LAPS+ clean laps,
    #    the one whose fuel-corrected slope is the median. (The single longest stint was Monaco 2024, a go-slow race.)
    hs = c[c.compound == "HARD"].groupby(["group", "stint_number"])
    long_keys = [k for k, n in hs.size().items() if n >= EXAMPLE_MIN_LAPS]

    def corrected_slope(g: pd.DataFrame) -> float:
        g = g.sort_values("lap_number")
        return float(np.polyfit(g["tyre_age"], g["lap_duration"] - fuel * g["lap_number"], 1)[0])

    slopes = pd.Series({k: corrected_slope(hs.get_group(k)) for k in long_keys}).sort_values()
    key = slopes.index[(len(slopes) - 1) // 2]
    rs.put("n_long_hard_stints", len(slopes), "stints", f"Hard stints with {EXAMPLE_MIN_LAPS}+ clean laps")
    s = hs.get_group(key).sort_values("lap_number")
    corr = s["lap_duration"] - fuel * (s["lap_number"] - s["lap_number"].iloc[0])
    rs.put("example_stint_laps", len(s), "laps", "Clean laps in the example HARD stint")
    rs.put("example_stint_circuit", c.loc[s.index[0], "circuit"], "", "Circuit of the example stint")
    rs.put("example_stint_year", int(c.loc[s.index[0], "year"]), "", "Year of the example stint")
    rs.put("example_raw_slope", float(np.polyfit(s["tyre_age"], s["lap_duration"], 1)[0]), "s per lap",
           "Example stint: raw lap-time trend per lap", decimals=3)
    rs.put("example_corrected_slope", float(np.polyfit(s["tyre_age"], corr, 1)[0]), "s per lap",
           "Example stint: trend after removing the lap-number effect", decimals=3)
    export_chart(Chart(
        id="p13_example_stint", type="line", title="A typical long hard-tyre stint: raw vs fuel-corrected",
        subtitle=f"The median-wear stint among hard stints with {EXAMPLE_MIN_LAPS}+ clean laps. Raw times fall as fuel burns; remove the lap effect and wear appears",
        x_axis=Axis(title="Tyre age", unit="laps"), y_axis=Axis(title="Lap time", unit="s"),
        series=[make_series("Raw lap time", s["tyre_age"], s["lap_duration"], downsample=False),
                make_series("Fuel-corrected lap time", s["tyre_age"], corr, role="fitted", downsample=False)],
        source_note=SOURCE_NOTE,
        result_keys=["example_raw_slope", "example_corrected_slope", "fuel_slope"],
    ), out)

    # 2. wear curves: partial residual (lap effect, FE and compound offset removed), mean by age, vs fresh
    m = fits["main"]
    X = design(c)
    fe = (c["lap_duration"] - X[m.params.index] @ m.params).groupby(c["group"]).transform("mean")
    offset = sum(m.params.get(f"is_{k}", 0) * X[f"is_{k}"] for k in COMPOUNDS[1:])
    pr = c["lap_duration"] - fe - fuel * c["lap_number"] - offset
    series = []
    for comp in COMPOUNDS:
        g = pr[c.compound == comp].groupby(c.loc[c.compound == comp, "tyre_age"]).agg(["mean", "size"])
        g = g[g["size"] >= MIN_LAPS_AT_AGE]
        if g.empty:
            continue
        ref = g["mean"].iloc[0]
        series.append(make_series(f"{comp.title()} (observed)", g.index, g["mean"] - ref, unit="s", downsample=False))
        ages = np.arange(g.index.min(), g.index.max() + 1)
        fit = m.params[f"age_{comp}"] * (ages - ages[0])
        series.append(make_series(f"{comp.title()} (straight line)", ages, fit, unit="s", role="fitted", downsample=False))
    export_chart(Chart(
        id="p13_wear_curves", type="line", title="Lap-time loss vs tyre age, fuel-corrected",
        subtitle=f"Mean partial residual by age (ages with {MIN_LAPS_AT_AGE}+ laps), relative to the freshest age shown",
        x_axis=Axis(title="Tyre age", unit="laps"), y_axis=Axis(title="Loss vs fresh tyre", unit="s"),
        series=series, source_note=SOURCE_NOTE,
        result_keys=["deg_soft", "deg_medium", "deg_hard"],
    ), out)

    # 3. Kaplan-Meier: share of stints not yet pitted at each stint length (stints run to the flag are censored)
    series = []
    for comp in COMPOUNDS:
        S = dec[comp]["km"]
        S = S[S.index <= int(stints.loc[stints.compound == comp, "length"].quantile(0.99))]
        series.append(make_series(comp.title(), S.index, S.to_numpy(), unit="share", downsample=False))
    export_chart(Chart(
        id="p13_stint_survival", type="line", title="How long a stint lasts before the pit stop (Kaplan-Meier)",
        subtitle="Stints that ran to the chequered flag count as censored, not as stops. Few stints reach old tyre ages",
        x_axis=Axis(title="Stint length", unit="laps"), y_axis=Axis(title="Stints not yet pitted", unit="share", min=0, max=1),
        series=series, source_note=SOURCE_NOTE,
        reference_lines=[ReferenceLine(axis="y", value=0.5, label="half of stints have pitted")],
        result_keys=["stint_len_median_hard", "stint_len_median_medium", "stint_len_median_soft"],
    ), out)

    # 4. LORO error: line vs break, per compound
    comps = [k for k in COMPOUNDS if cl.get(k)]
    export_chart(Chart(
        id="p13_loro", type="bar", title="Leave-one-race-out error: straight line vs line with a break",
        subtitle="Lower is better. The break is chosen on the other races each time",
        x_axis=Axis(title="Compound", kind="category"), y_axis=Axis(title="Held-out RMSE", unit="s"),
        series=[make_series("Straight line", [k.title() for k in comps],
                            [rs.results[f"loro_rmse_line_{k.lower()}"]["value"] for k in comps], downsample=False),
                make_series("Line with break", [k.title() for k in comps],
                            [rs.results[f"loro_rmse_hinge_{k.lower()}"]["value"] for k in comps], downsample=False)],
        source_note=SOURCE_NOTE,
        result_keys=[f"loro_rmse_line_{k.lower()}" for k in comps] + [f"loro_rmse_hinge_{k.lower()}" for k in comps],
    ), out)


def analyse() -> ResultStore:
    laps, races, stints, stops = load()
    c = clean_laps(laps)
    rs = ResultStore(CASE_DIR)
    overview(laps, races, c, rs)
    fits = {**identification(c, rs), **main_model(c, rs)}
    cl = cliff(c, rs)
    out_of_time(c, rs)
    circ = circuits(c, rs)
    dec = decision(c, stints, stops, laps, circ, rs)
    sensitivity(laps, rs)
    charts(c, stints, fits, cl, dec, rs)
    for k in sorted(rs.results):
        print(f"{k:<34} {rs.results[k]['display']}")
    rs.save()
    return rs


if __name__ == "__main__":
    analyse()
