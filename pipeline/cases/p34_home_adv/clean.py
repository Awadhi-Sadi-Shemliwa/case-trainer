"""P34 · Clean: 20 league-season CSVs -> one match table with a crowd period per match.

Periods (no hand-typed dates; the restart is found in the data):
* fans      - 2017/18 .. the COVID suspension of 2019/20 (crowds present)
* ghost     - league restart in 2019/20 .. end of 2020/21 (no or very limited crowds; Leitner et al. 2022:
              leagues "resumed in the form of ghost games in May and June 2020")
* fans_back - 2021/22 (crowds returned)
The restart = first match after the longest gap between consecutive matches in the league's 2019/20 file.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from common.io import capture_output
from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
RAW = CASE_DIR / "raw"
LEAGUES = {"E0": "Premier League", "D1": "Bundesliga", "SP1": "La Liga", "I1": "Serie A"}
SEASONS = ["1718", "1819", "1920", "2021", "2122"]
COLS = ["Date", "HomeTeam", "AwayTeam", "FTHG", "FTAG", "FTR", "HF", "AF", "HY", "AY", "HR", "AR"]
NUM = ["FTHG", "FTAG", "HF", "AF", "HY", "AY", "HR", "AR"]


def parse_dates(prov: Provenance, div: str, season: str) -> pd.DataFrame:
    key = f"fd_{div}_{season}"
    text = pd.read_csv(RAW / f"{div}_{season}.csv", encoding="latin-1", usecols=COLS, dtype=str)
    # >>> snippet: parse_dates
    short = text["Date"].str.len() == 8                        # dd/mm/yy
    dates = pd.to_datetime(text["Date"].where(~short), format="%d/%m/%Y", errors="coerce")
    dates = dates.fillna(pd.to_datetime(text["Date"].where(short), format="%d/%m/%y", errors="coerce"))
    # <<< snippet
    bad = int(dates.isna().sum())
    if bad:
        raise ValueError(f"{key}: {bad} unparseable dates")
    df = text.assign(Date=dates)
    for c in NUM:
        df[c] = pd.to_numeric(df[c], errors="raise").astype(int)
    df.insert(0, "league", LEAGUES[div])
    df.insert(1, "season", f"20{season[:2]}/{season[2:]}")
    prov.log_transform(
        key, f"parse_{div}_{season}", len(text), len(df),
        reason=("Dates parsed day-first. Older files write dd/mm/yy, newer dd/mm/yyyy; each format is parsed "
                "explicitly (no guessing) and any unparseable date stops the pipeline. No rows dropped."),
        details={"two_digit_year_rows": int(short.sum()), "kept_columns": COLS},
    )
    return df


def find_restart(df_1920: pd.DataFrame) -> pd.Timestamp:
    # >>> snippet: find_restart
    days = df_1920["Date"].sort_values().drop_duplicates().reset_index(drop=True)
    gap = days.diff()
    restart = days[gap.idxmax()]                               # first match day after the longest pause
    # <<< snippet
    return restart, int(gap.max().days)


def build(prov: Provenance) -> pd.DataFrame:
    frames = []
    restarts = {}
    for div in LEAGUES:
        league = [parse_dates(prov, div, s) for s in SEASONS]
        restart, gap_days = find_restart(league[SEASONS.index("1920")])
        restarts[LEAGUES[div]] = (restart, gap_days)
        frames += league
    df = pd.concat(frames, ignore_index=True)

    # Duplicate fixtures would double-count a match.
    dup = df.duplicated(["league", "Date", "HomeTeam", "AwayTeam"])
    prov.log_transform("fd_all", "drop_duplicate_fixtures", len(df), int((~dup).sum()),
                       reason="Same league, date, home and away team appearing twice would double-count a match.",
                       details={"duplicates": int(dup.sum())})
    df = df[~dup]

    # >>> snippet: assign_period
    restart = df["league"].map({k: v[0] for k, v in restarts.items()})
    df["period"] = "fans"
    df.loc[(df["season"] == "2019/20") & (df["Date"] >= restart), "period"] = "ghost"
    df.loc[df["season"] == "2020/21", "period"] = "ghost"
    df.loc[df["season"] == "2021/22", "period"] = "fans_back"
    df["strict_ghost"] = (df["season"] == "2019/20") & (df["Date"] >= restart)
    # <<< snippet
    prov.log_transform(
        "fd_all", "assign_period", len(df), len(df),
        reason=("Each match labelled fans / ghost / fans_back. Restart per league = first match after the longest "
                "pause in 2019/20 (found in the data, not typed). 2020/21 counted as ghost (no or very limited "
                "crowds); strict_ghost marks only the 2019/20 post-restart matches for a robustness check."),
        details={"restart": {k: v[0].strftime("%Y-%m-%d") for k, v in restarts.items()},
                 "pause_days": {k: v[1] for k, v in restarts.items()},
                 "matches_per_period": df["period"].value_counts().to_dict()},
    )
    return df, restarts


def clean() -> pd.DataFrame:
    prov = Provenance(CASE_DIR)
    with capture_output(CASE_DIR, "restart_dates"):
        df, restarts = build(prov)
        for k, (d, g) in restarts.items():
            print(f"{k:<15} pause {g:>3} days, restart {d:%Y-%m-%d}")
    with capture_output(CASE_DIR, "period_counts"):
        print(df.groupby(["league", "period"]).size().unstack()[["fans", "ghost", "fans_back"]].to_string())
    prov.save()
    df.to_csv(CASE_DIR / "matches_clean.csv", index=False)
    return df


if __name__ == "__main__":
    clean()
