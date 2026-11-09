"""P34 · Download football-data.co.uk league CSVs untouched and record provenance.

Leagues: Premier League (E0), Bundesliga (D1), La Liga (SP1), Serie A (I1); seasons 2017/18 .. 2021/22.
Column meanings verified 2026-11-09 from https://www.football-data.co.uk/notes.txt (quoted in CASE notes):
FTHG/FTAG full-time goals, FTR result (H/D/A), HF/AF fouls committed, HY/AY yellow cards, HR/AR red cards.
Notes.txt: "English and Scottish yellow cards do not include the initial yellow card when a second is shown to a
player" while for European games the initial card "is included as a yellow (plus red)" -> compare within league.
Site: "My data is free." Cite football-data.co.uk.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
URL = "https://www.football-data.co.uk/mmz4281/{season}/{div}.csv"
LEAGUES = {"E0": "Premier League", "D1": "Bundesliga", "SP1": "La Liga", "I1": "Serie A"}
SEASONS = ["1718", "1819", "1920", "2021", "2122"]
LICENCE = ("football-data.co.uk: 'My data is free.' No separate terms page (checked 2026-11-09). "
           "Cite: Football-Data.co.uk, https://www.football-data.co.uk/")


def key(div: str, season: str) -> str:
    return f"fd_{div}_{season}"


def download(refresh: bool = False) -> Provenance:
    prov = Provenance(CASE_DIR)
    for div, name in LEAGUES.items():
        for season in SEASONS:
            k = key(div, season)
            path = prov.fetch(k, URL.format(season=season, div=div), f"{div}_{season}.csv", licence_note=LICENCE,
                              source_page="https://www.football-data.co.uk/data.php", refresh=refresh)
            prov.annotate(k, league=name, division=div, season=f"20{season[:2]}/{season[2:]}",
                          units="goals, fouls, cards: counts per match",
                          verified_on="2026-11-09", verified_how="Column definitions read in football-data notes.txt")
            # Spec §2: print the schema before using it. Keep everything as text so markers stay visible.
            raw = pd.read_csv(path, dtype=str, encoding="latin-1", on_bad_lines="error")
            prov.describe(k, raw[[c for c in ["Div", "Date", "HomeTeam", "AwayTeam", "FTHG", "FTAG", "FTR",
                                               "HF", "AF", "HY", "AY", "HR", "AR"] if c in raw.columns]],
                          print_schema=False)
            prov.annotate(k, all_columns_count=len(raw.columns),
                          has_fouls=bool({"HF", "AF"} <= set(raw.columns)),
                          blank_rows=int(raw.isna().all(axis=1).sum()))
            print(f"{k}: {len(raw)} rows, {len(raw.columns)} cols, fouls={'HF' in raw.columns}")
    prov.save()
    return prov


if __name__ == "__main__":
    download()
