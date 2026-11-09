"""P34 · Analyse: did empty stadiums shrink home advantage, and did referees change how they card away teams?

Natural experiment: COVID forced matches behind closed doors. Compare fans vs ghost (and fans_back as a reversal check).
* KPI 1 home win rate; KPI 2 home goal difference per match; KPI 3 yellow cards per foul, home vs away.
* Per-league differences in proportions with Holm correction (4 leagues = 4 tests).
* Cards: Poisson GLM, yellow cards per team-match with log(fouls) offset, league fixed effects,
  home x ghost interaction (difference-in-differences), standard errors clustered by match.
* Confounder check: rest days between matches (ghost period was congested).
Yellow cards are counted differently in England vs Europe (football-data notes.txt), so every comparison is
within a league (fixed effects); levels are never compared across leagues.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
from statsmodels.stats.multitest import multipletests

from common.charts import Axis, Chart, ReferenceLine, ShadedRegion, export_chart, make_series
from common.io import capture_output
from common.provenance import Provenance
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
SOURCE = "Data: football-data.co.uk (Premier League, Bundesliga, La Liga, Serie A, 2017/18-2021/22)."
LEAGUE_ORDER = ["Premier League", "Bundesliga", "La Liga", "Serie A"]
TAG = {"Premier League": "epl", "Bundesliga": "bund", "La Liga": "liga", "Serie A": "seria"}
ALPHA = 0.05


def load() -> pd.DataFrame:
    df = pd.read_csv(CASE_DIR / "matches_clean.csv", parse_dates=["Date"])
    df["home_win"] = (df["FTR"] == "H").astype(int)
    df["home_gd"] = df["FTHG"] - df["FTAG"]
    return df


def diff_prop(a: pd.Series, b: pd.Series) -> tuple[float, float, float, float]:
    """b - a for two 0/1 samples: difference, 95% CI low/high (Wald), two-sided p (pooled z test)."""
    p1, p2, n1, n2 = a.mean(), b.mean(), len(a), len(b)
    d = p2 - p1
    se = np.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2)
    pp = (a.sum() + b.sum()) / (n1 + n2)
    z = d / np.sqrt(pp * (1 - pp) * (1 / n1 + 1 / n2))
    return d, d - 1.96 * se, d + 1.96 * se, 2 * stats.norm.sf(abs(z))


def descriptives(df: pd.DataFrame, rs: ResultStore) -> None:
    rs.put("n_matches", len(df), "matches", "Matches in the cleaned table (4 leagues, 5 seasons)")
    for p in ["fans", "ghost", "fans_back"]:
        rs.put(f"n_{p}", int((df.period == p).sum()), "matches", f"Matches in period '{p}'")
    rs.put("n_strict_ghost", int(df.strict_ghost.sum()), "matches", "Ghost matches in the strict window (2019/20 restart only)")
    rs.put("n_leagues", df.league.nunique(), "leagues", "Leagues analysed")


def win_rates(df: pd.DataFrame, rs: ResultStore) -> pd.DataFrame:
    rows = []
    # >>> snippet: league_tests
    for lg in LEAGUE_ORDER:
        d = df[df.league == lg]
        diff, lo, hi, p = diff_prop(d.loc[d.period == "fans", "home_win"], d.loc[d.period == "ghost", "home_win"])
        rows.append({"league": lg, "fans": d.loc[d.period == "fans", "home_win"].mean(),
                     "ghost": d.loc[d.period == "ghost", "home_win"].mean(),
                     "fans_back": d.loc[d.period == "fans_back", "home_win"].mean(),
                     "change": diff, "ci_low": lo, "ci_high": hi, "p": p})
    table = pd.DataFrame(rows)
    table["p_holm"] = multipletests(table["p"], method="holm")[1]
    # <<< snippet
    with capture_output(CASE_DIR, "league_tests"):
        print(table.round(3).to_string(index=False))
    for r in table.itertuples():
        t = TAG[r.league]
        rs.put(f"hw_fans_{t}", float(r.fans), "share", f"{r.league}: home win rate with fans", decimals=1, pct=True)
        rs.put(f"hw_ghost_{t}", float(r.ghost), "share", f"{r.league}: home win rate in ghost games", decimals=1, pct=True)
        rs.put(f"hw_back_{t}", float(r.fans_back), "share", f"{r.league}: home win rate when fans returned", decimals=1, pct=True)
        rs.put(f"hw_change_{t}", float(r.change), "share", f"{r.league}: change in home win rate, ghost minus fans",
               decimals=1, pct=True)
        rs.put(f"p_holm_{t}", float(r.p_holm), "p-value", f"{r.league}: Holm-adjusted p-value for the change", decimals=3)
    rs.put("n_leagues_significant", int((table.p_holm < ALPHA).sum()), "leagues",
           "Leagues whose home-win-rate drop is significant after Holm correction (5%)")
    rs.put("n_leagues_unadjusted_sig", int((table.p < ALPHA).sum()), "leagues",
           "Leagues significant at 5% WITHOUT correcting for 4 tests")

    # pooled
    f, g, b = (df.loc[df.period == p, "home_win"] for p in ["fans", "ghost", "fans_back"])
    diff, lo, hi, p = diff_prop(f, g)
    rs.put("hw_fans", float(f.mean()), "share", "Pooled home win rate with fans", decimals=1, pct=True)
    rs.put("hw_ghost", float(g.mean()), "share", "Pooled home win rate in ghost games", decimals=1, pct=True)
    rs.put("hw_back", float(b.mean()), "share", "Pooled home win rate when fans returned", decimals=1, pct=True)
    rs.put("hw_change", float(diff), "share", "Pooled change in home win rate, ghost minus fans", decimals=1, pct=True)
    rs.put("hw_change_lo", float(lo), "share", "95% CI lower bound of the pooled change", decimals=1, pct=True)
    rs.put("hw_change_hi", float(hi), "share", "95% CI upper bound of the pooled change", decimals=1, pct=True)
    rs.put("hw_change_p", float(p), "p-value", "Two-sided p-value of the pooled change", decimals=4)
    aw_f = (df.loc[df.period == "fans", "FTR"] == "A").mean()
    aw_g = (df.loc[df.period == "ghost", "FTR"] == "A").mean()
    rs.put("aw_fans", float(aw_f), "share", "Pooled away win rate with fans", decimals=1, pct=True)
    rs.put("aw_ghost", float(aw_g), "share", "Pooled away win rate in ghost games", decimals=1, pct=True)

    # strict window robustness
    s = df[df.strict_ghost]
    d2, lo2, hi2, p2 = diff_prop(f, s["home_win"])
    rs.put("hw_strict_ghost", float(s["home_win"].mean()), "share",
           "Home win rate in the strict ghost window (2019/20 after restart)", decimals=1, pct=True)
    rs.put("hw_change_strict", float(d2), "share", "Change vs fans using only the strict ghost window", decimals=1, pct=True)
    return table


def goal_diff(df: pd.DataFrame, rs: ResultStore) -> None:
    gd = {p: df.loc[df.period == p, "home_gd"] for p in ["fans", "ghost", "fans_back"]}
    t = stats.ttest_ind(gd["ghost"], gd["fans"], equal_var=False)
    diff = gd["ghost"].mean() - gd["fans"].mean()
    ci = t.confidence_interval(0.95)
    rs.put("gd_fans", float(gd["fans"].mean()), "goals per match", "Average home goal difference with fans", decimals=3)
    rs.put("gd_ghost", float(gd["ghost"].mean()), "goals per match", "Average home goal difference in ghost games", decimals=3)
    rs.put("gd_back", float(gd["fans_back"].mean()), "goals per match", "Average home goal difference when fans returned", decimals=3)
    rs.put("gd_change", float(diff), "goals per match", "Change in home goal difference, ghost minus fans", decimals=3)
    rs.put("gd_change_lo", float(ci.low), "goals per match", "95% CI lower bound (Welch)", decimals=3)
    rs.put("gd_change_hi", float(ci.high), "goals per match", "95% CI upper bound (Welch)", decimals=3)
    rs.put("gd_change_p", float(t.pvalue), "p-value", "Welch t-test p-value for the goal-difference change", decimals=4)
    rs.put("gd_share_lost", float(-diff / gd["fans"].mean()), "share",
           "Share of the with-fans home goal edge that disappeared in ghost games", decimals=0, pct=True)


def cards(df: pd.DataFrame, rs: ResultStore) -> None:
    # one row per team per match: yellow cards, fouls committed, home flag
    home = df.assign(yellows=df.HY, fouls=df.HF, home=1)
    away = df.assign(yellows=df.AY, fouls=df.AF, home=0)
    tm = pd.concat([home, away])[["league", "period", "Date", "HomeTeam", "AwayTeam", "yellows", "fouls", "home"]]
    tm["match_id"] = tm.groupby(["league", "Date", "HomeTeam", "AwayTeam"]).ngroup()
    zero_fouls = int((tm.fouls == 0).sum())
    prov = Provenance(CASE_DIR)
    prov.log_transform("fd_all", "drop_zero_foul_rows", len(tm), len(tm) - zero_fouls,
                       reason=("The card model uses log(fouls) as an offset (cards per foul); log(0) is undefined. "
                               "Team-match rows with zero recorded fouls are dropped from the card model only."),
                       details={"rows_dropped": zero_fouls})
    prov.save()
    tm = tm[tm.fouls > 0]
    rs.put("zero_foul_rows", zero_fouls, "team-matches", "Team-match rows with zero fouls recorded (dropped: log offset)")
    sub = tm[tm.period.isin(["fans", "ghost"])].copy()
    sub["ghost"] = (sub.period == "ghost").astype(int)

    # descriptive yellows per 10 fouls
    for p in ["fans", "ghost", "fans_back"]:
        for side, h in (("home", 1), ("away", 0)):
            x = tm[(tm.period == p) & (tm.home == h)]
            rs.put(f"ypf_{side}_{p}", float(10 * x.yellows.sum() / x.fouls.sum()), "yellows per 10 fouls",
                   f"{side.title()} team yellow cards per 10 fouls committed, period '{p}'", decimals=2)

    # >>> snippet: card_model
    model = smf.glm("yellows ~ home * ghost + C(league)", data=sub,
                    family=sm.families.Poisson(), offset=np.log(sub["fouls"]))
    res = model.fit(cov_type="cluster", cov_kwds={"groups": sub["match_id"]})
    did = res.params["home:ghost"]                      # change in home-vs-away card rate per foul
    lo, hi = res.conf_int().loc["home:ghost"]
    # <<< snippet
    with capture_output(CASE_DIR, "card_model"):
        print(res.summary2().tables[1].loc[["home", "ghost", "home:ghost"], ["Coef.", "Std.Err.", "P>|z|"]].round(4).to_string())
        print(f"rate ratio home:ghost = {np.exp(did):.3f}  (95% CI {np.exp(lo):.3f} to {np.exp(hi):.3f})")
    rs.put("rr_home_fans", float(np.exp(res.params["home"])), "rate ratio",
           "With fans: home team's yellow-per-foul rate relative to the away team's", decimals=3)
    rs.put("rr_did", float(np.exp(did)), "rate ratio",
           "Difference-in-differences: change in home/away card-per-foul ratio in ghost games", decimals=3)
    rs.put("rr_did_lo", float(np.exp(lo)), "rate ratio", "95% CI lower bound (match-clustered)", decimals=3)
    rs.put("rr_did_hi", float(np.exp(hi)), "rate ratio", "95% CI upper bound (match-clustered)", decimals=3)
    rs.put("rr_did_p", float(res.pvalues["home:ghost"]), "p-value", "p-value of the home x ghost interaction", decimals=4)


def congestion(df: pd.DataFrame, rs: ResultStore) -> None:
    # >>> snippet: rest_days
    long = pd.concat([df[["league", "Date", "period", "HomeTeam"]].rename(columns={"HomeTeam": "team"}),
                      df[["league", "Date", "period", "AwayTeam"]].rename(columns={"AwayTeam": "team"})])
    long = long.sort_values(["league", "team", "Date"])
    long["rest"] = long.groupby(["league", "team"])["Date"].diff().dt.days
    rest = long[long.rest.between(1, 21)].groupby("period")["rest"].median()   # ignore summer/COVID breaks
    # <<< snippet
    rs.put("rest_fans", float(rest["fans"]), "days", "Median days between a team's matches, with fans", decimals=1)
    rs.put("rest_ghost", float(rest["ghost"]), "days", "Median days between a team's matches, ghost period", decimals=1)
    rs.put("rest_window_max", 21, "days", "Gaps longer than this are breaks, not rest, and are ignored")


def decision(rs: ResultStore) -> None:
    # The betting-model adjustment: how much home goal edge to remove when crowds are absent (point + CI).
    rs.put("adj_goals", float(-rs.get("gd_change")), "goals per match",
           "Recommended reduction of the model's home goal edge when crowds are absent (point estimate)", decimals=2)
    rs.put("adj_goals_lo", float(-rs.get("gd_change_hi")), "goals per match", "Lower end of the adjustment range", decimals=2)
    rs.put("adj_goals_hi", float(-rs.get("gd_change_lo")), "goals per match", "Upper end of the adjustment range", decimals=2)


def charts(df: pd.DataFrame, table: pd.DataFrame, rs: ResultStore) -> None:
    out = CASE_DIR / "charts"
    export_chart(Chart(
        id="p34_home_win_by_period", type="bar",
        title="Home win rate: fans, ghost games, fans back",
        subtitle="Share of matches won by the home team",
        x_axis=Axis(title="League", kind="category"),
        y_axis=Axis(title="Home win rate", unit="share of matches", min=0, max=0.6),
        series=[make_series("With fans", table.league, table.fans, unit="share", downsample=False),
                make_series("Ghost games", table.league, table.ghost, unit="share", downsample=False),
                make_series("Fans back", table.league, table.fans_back, unit="share", downsample=False)],
        source_note=SOURCE, result_keys=["hw_fans", "hw_ghost", "hw_back", "n_leagues_significant"],
    ), out)

    # rolling pooled home goal difference over time, ghost window shaded
    d = df.sort_values("Date").reset_index(drop=True)
    roll = d["home_gd"].rolling(380, min_periods=380).mean()
    ghost = d[d.period == "ghost"]
    export_chart(Chart(
        id="p34_home_gd_timeline", type="line",
        title="Home goal difference over time (rolling 380 matches)",
        subtitle="All four leagues pooled; grey = ghost-game period",
        x_axis=Axis(title="Match date", kind="date"),
        y_axis=Axis(title="Home minus away goals", unit="goals per match"),
        series=[make_series("Rolling home goal difference", d["Date"], roll, unit="goals")],
        shaded_regions=[ShadedRegion(start=ghost.Date.min().strftime("%Y-%m-%d"), end=ghost.Date.max().strftime("%Y-%m-%d"),
                                     label="Ghost games (no or very limited crowds)")],
        reference_lines=[ReferenceLine(axis="y", value=0, label="no home edge")],
        source_note=SOURCE, result_keys=["gd_fans", "gd_ghost", "gd_back"],
    ), out)

    periods = ["fans", "ghost", "fans_back"]
    labels = ["With fans", "Ghost games", "Fans back"]
    export_chart(Chart(
        id="p34_cards_per_foul", type="bar",
        title="Yellow cards per 10 fouls, home vs away teams",
        subtitle="Cards are counted per foul committed, so more fouls alone cannot explain a gap",
        x_axis=Axis(title="Period", kind="category"),
        y_axis=Axis(title="Yellow cards", unit="per 10 fouls", min=0),
        series=[make_series("Home teams", labels, [rs.get(f"ypf_home_{p}") for p in periods], downsample=False),
                make_series("Away teams", labels, [rs.get(f"ypf_away_{p}") for p in periods], downsample=False)],
        source_note=SOURCE, result_keys=["ypf_home_fans", "ypf_away_fans", "ypf_home_ghost", "ypf_away_ghost", "rr_did"],
    ), out)


def analyse() -> ResultStore:
    df = load()
    rs = ResultStore(CASE_DIR)
    descriptives(df, rs)
    table = win_rates(df, rs)
    goal_diff(df, rs)
    cards(df, rs)
    congestion(df, rs)
    decision(rs)
    charts(df, table, rs)
    rs.save()
    return rs


if __name__ == "__main__":
    analyse()
