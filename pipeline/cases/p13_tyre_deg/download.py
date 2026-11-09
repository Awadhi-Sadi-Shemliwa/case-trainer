"""P13 · Download race lap tables with FastF1 and save them untouched (timedeltas -> seconds) to raw/.

Runs in the ISOLATED env (FastF1 needs pandas<3):
    cd pipeline && uv run --project f1_fetch python -m cases.p13_tyre_deg.download

Columns verified 2026-11-09 against docs.fastf1.dev/core.html (Laps) and the installed FastF1 3.9.2 source
(_api.py track_status_data): TrackStatus codes '1' clear, '2' yellow, '4' Safety Car, '5' red flag,
'6' VSC deployed, '7' VSC ending.

Terms: FastF1 is MIT-licensed, but the timing data comes from Formula 1's live-timing service and is unofficial.
For personal and educational use only, so the lap files are NOT committed (see .gitignore). Only aggregated
results and charts are committed.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

import fastf1
import pandas as pd

from common.provenance import Provenance, sha256_file

CASE_DIR = Path(__file__).resolve().parent
RAW = CASE_DIR / "raw"
CACHE = CASE_DIR / ".fastf1_cache"
SEASON = 2023
RACES = ["Bahrain", "Spain", "Austria", "Hungary", "Italy", "Abu Dhabi"]
COLS = ["Driver", "Team", "LapNumber", "LapTime", "Stint", "Compound", "TyreLife", "FreshTyre",
        "PitInTime", "PitOutTime", "TrackStatus", "IsAccurate", "Position", "FastF1Generated"]
TIMEDELTA = ["LapTime", "PitInTime", "PitOutTime"]
LICENCE = ("Formula 1 live-timing data via FastF1 3.9.2 (MIT). Unofficial data, personal/educational use only; "
           "not redistributed (raw lap files are git-ignored). Cite: FastF1, https://docs.fastf1.dev")


def key(race: str) -> str:
    return "f1_laps_" + race.lower().replace(" ", "_")


def download() -> Provenance:
    RAW.mkdir(exist_ok=True)
    CACHE.mkdir(exist_ok=True)
    fastf1.Cache.enable_cache(str(CACHE))
    prov = Provenance(CASE_DIR)
    for race in RACES:
        session = fastf1.get_session(SEASON, race, "R")
        session.load(laps=True, telemetry=False, weather=False, messages=False)
        laps = pd.DataFrame(session.laps)[COLS].copy()
        for c in TIMEDELTA:  # store seconds, not pandas Timedelta, so the main pipeline (pandas 3) reads plain numbers
            laps[c] = laps[c].dt.total_seconds()
        fname = f"laps_{SEASON}_{race.lower().replace(' ', '_')}.csv"
        laps.to_csv(RAW / fname, index=False)
        k = key(race)
        prov.data["datasets"][k] = {
            "key": k,
            "url": f"fastf1.get_session({SEASON}, '{race}', 'R').laps",
            "source_page": "https://docs.fastf1.dev/core.html",
            "file": f"raw/{fname}",
            "retrieved_utc": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "sha256": sha256_file(RAW / fname),
            "bytes": (RAW / fname).stat().st_size,
            "licence_note": LICENCE,
            "event": str(session.event["EventName"]),
            "event_date": str(session.event["EventDate"].date()),
            "units": "LapTime, PitInTime, PitOutTime in seconds; TyreLife and LapNumber in laps",
            "export_note": "FastF1 laps table, listed columns only; timedeltas converted to seconds. No rows removed.",
            "verified_on": "2026-11-09",
        }
        prov.describe(k, laps, print_schema=False)
        print(f"{k}: {session.event['EventName']} {session.event['EventDate'].date()} -> {len(laps)} laps, "
              f"compounds {sorted(laps['Compound'].dropna().unique())}")
    prov.save()
    (CASE_DIR / "fastf1_version.json").write_text(json.dumps({"fastf1": fastf1.__version__}) + "\n", encoding="utf-8")
    return prov


if __name__ == "__main__":
    download()
