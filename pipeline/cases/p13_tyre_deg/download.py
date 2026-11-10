"""P13 · Download race data from the OpenF1 API (2023-2025 races) and save it untouched to raw/.

Why OpenF1: FastF1 3.9 needs an active F1TV subscription (checked in its source, 2026-11-10). OpenF1 serves
historical sessions since 2023 with no login (https://openf1.org, read 2026-11-10).
Terms: "Licensed under CC BY-NC-SA 4.0"; intended for "educational purposes, personal learning projects,
research". Raw JSON is NOT committed (git-ignored, `committed: false` in provenance). Only derived tables are
committed, under CC BY-NC-SA 4.0 with credit to OpenF1. Free tier: 3 req/s and 30 req/min, so calls are throttled.

Fields verified 2026-11-10 by loading the 2023 Bahrain race (session_key 7953) and printing every endpoint:
laps (lap_duration s, is_pit_out_lap, lap_number), stints (compound, tyre_age_at_start, lap_start, lap_end),
race_control (category, flag, message, lap_number), intervals (interval s to the car ahead, ~4 s cadence),
weather (rainfall, track_temperature). The `pit` endpoint had no rows for that race, so in-laps come from stints.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import requests

from common.provenance import Provenance, ProvenanceError, _Downloader

CASE_DIR = Path(__file__).resolve().parent
API = "https://api.openf1.org/v1"
SEASONS = (2023, 2024, 2025)   # 2026 excluded: new car and tyre regulations (DECISIONS)
ENDPOINTS = ("laps", "stints", "race_control", "intervals", "weather")
LICENCE = ("OpenF1 (https://openf1.org), unofficial community API, CC BY-NC-SA 4.0. Educational, non-commercial use. "
           "Raw data not redistributed; derived tables shared under CC BY-NC-SA 4.0 with credit to OpenF1. "
           "Not associated with Formula 1 companies.")
HEADERS = {"User-Agent": "case-trainer-pipeline"}
MIN_GAP_S = 2.2                # <= ~27 requests per minute, under the free 30/min limit
EMPTY = b"[]"


class OpenF1Downloader(_Downloader):
    """Throttled; OpenF1 answers an empty query with 404 {"detail":"No results found."}, stored as []."""

    timeout = 120.0
    _last = 0.0

    def get(self, url: str, headers: dict[str, str]) -> bytes:
        for attempt in range(1, 5):
            wait = MIN_GAP_S - (time.monotonic() - self._last)
            if wait > 0:
                time.sleep(wait)
            self._last = time.monotonic()
            try:
                r = requests.get(url, headers=headers, timeout=self.timeout)
            except requests.RequestException:
                time.sleep(5 * attempt)
                continue
            if r.status_code == 404 and b"No results found" in r.content:
                return EMPTY
            if r.status_code == 429:
                time.sleep(20 * attempt)
                continue
            r.raise_for_status()
            return r.content
        raise ProvenanceError(f"OpenF1 download failed: {url}")


def races(prov: Provenance) -> list[dict]:
    out = []
    for year in SEASONS:
        k = f"openf1_sessions_{year}"
        path = prov.fetch(k, f"{API}/sessions?year={year}&session_name=Race", f"sessions_{year}.json",
                          licence_note=LICENCE, source_page="https://openf1.org/docs", headers=HEADERS)
        prov.annotate(k, committed=False, verified_on="2026-11-10")
        for s in json.loads(path.read_text(encoding="utf-8")):
            if not s.get("is_cancelled"):
                out.append(s)
    return out


def download() -> Provenance:
    prov = Provenance(CASE_DIR, downloader=OpenF1Downloader())
    sessions = races(prov)
    prov.save()
    for i, s in enumerate(sessions, 1):
        sk = s["session_key"]
        for ep in ENDPOINTS:
            k = f"openf1_{ep}_{sk}"
            path = prov.fetch(k, f"{API}/{ep}?session_key={sk}", f"{ep}_{sk}.json", licence_note=LICENCE,
                              source_page="https://openf1.org/docs", headers=HEADERS)
            prov.annotate(k, committed=False, session_key=sk, year=s["year"], circuit=s["circuit_short_name"],
                          country=s["country_name"], race_date=s["date_start"][:10], verified_on="2026-11-10",
                          rows=len(json.loads(path.read_text(encoding="utf-8"))))
        print(f"[{i}/{len(sessions)}] {s['year']} {s['country_name']} ({s['circuit_short_name']}) session {sk}")
        prov.save()
    return prov


if __name__ == "__main__":
    download()
