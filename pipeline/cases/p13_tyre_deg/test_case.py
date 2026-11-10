"""P13 tests. Raw OpenF1 JSON is not committed (CC BY-NC-SA source, ~350 files), so:
* the analysis is always re-run from the committed aggregates and must reproduce every result key;
* the full clean (raw -> aggregates) is re-run only when the raw files are present, and must reproduce the aggregates.
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from cases.p13_tyre_deg import analyse as A
from cases.p13_tyre_deg import clean as C
from common.provenance import Provenance
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
EXPECTED = ResultStore.load(CASE_DIR)
PROV = json.loads((CASE_DIR / "provenance.json").read_text(encoding="utf-8"))
RAW_PRESENT = all((CASE_DIR / e["file"]).exists() for e in PROV["datasets"].values())
LAPS = pd.read_csv(CASE_DIR / "aggregates" / "laps.csv.gz")


@pytest.fixture(scope="module")
def rerun(tmp_path_factory):
    work = tmp_path_factory.mktemp("p13")
    shutil.copytree(CASE_DIR / "aggregates", work / "aggregates")
    mp = pytest.MonkeyPatch()
    mp.setattr(A, "CASE_DIR", work)
    mp.setattr(A, "AGG", work / "aggregates")
    try:
        yield work, A.analyse().results
    finally:
        mp.undo()


@pytest.mark.parametrize("key", sorted(EXPECTED))
def test_every_result_reproduces_from_aggregates(rerun, key):
    exp, got = EXPECTED[key]["value"], rerun[1][key]["value"]
    if isinstance(exp, float):
        assert math.isclose(got, exp, rel_tol=1e-7, abs_tol=1e-9), (key, got, exp)
    else:
        assert got == exp, (key, got, exp)


def test_no_unexpected_new_results(rerun):
    assert set(rerun[1]) == set(EXPECTED)


@pytest.mark.skipif(not RAW_PRESENT, reason="raw OpenF1 JSON not downloaded (git-ignored); run download.py")
def test_raw_hashes_and_full_clean_reproduce_aggregates(tmp_path):
    assert Provenance(CASE_DIR).verify_hashes() == []
    shutil.copy2(CASE_DIR / "provenance.json", tmp_path / "provenance.json")
    mp = pytest.MonkeyPatch()
    mp.setattr(C, "CASE_DIR", tmp_path)
    mp.setattr(C, "AGG", tmp_path / "aggregates")
    try:
        C.clean()
    finally:
        mp.undo()
    for f in ["laps.csv.gz", "stints.csv", "pit_stops.csv", "races.csv"]:
        pd.testing.assert_frame_equal(pd.read_csv(CASE_DIR / "aggregates" / f), pd.read_csv(tmp_path / "aggregates" / f),
                                      check_exact=False, rtol=1e-12)


def test_stint_fe_plus_lap_number_is_not_identified():
    """The spec's literal model: within a stint, tyre age and lap number move together exactly."""
    assert EXPECTED["within_stint_corr_age_lap"]["value"] > 0.999
    assert EXPECTED["stint_fe_rank"]["value"] < EXPECTED["stint_fe_columns"]["value"]
    # and the fix works because pit stops reset age while lap number keeps rising
    assert EXPECTED["share_multi_stint"]["value"] > 0.5


def test_no_excluded_lap_type_survives_cleaning():
    c = LAPS[LAPS.drop_reason.isna()]
    assert not c["neutralised"].astype(bool).any()
    assert (c["lap_number"] > 1).all()
    assert c["lap_duration"].notna().all() and c["compound"].isin(["SOFT", "MEDIUM", "HARD"]).all()
    assert not (c["median_gap_ahead"] < C.TRAFFIC_GAP_S).any()
    assert not (c["delta_to_stint_median"] > C.INCIDENT_S).any()
    # out-laps: first lap of a later stint; in-laps: last lap of a stint that was followed by another
    st = pd.read_csv(CASE_DIR / "aggregates" / "stints.csv")
    firsts = st[st.stint_number > 1][["session_key", "driver_number", "lap_start"]].rename(columns={"lap_start": "lap_number"})
    lasts = st[st.ended_in_pit][["session_key", "driver_number", "lap_end"]].rename(columns={"lap_end": "lap_number"})
    keys = ["session_key", "driver_number", "lap_number"]
    assert c.merge(firsts, on=keys).empty and c.merge(lasts, on=keys).empty


def test_every_drop_is_logged_once_with_a_reason():
    t = {x["id"]: x for x in PROV["transforms"]}
    for r in C.ORDER:
        assert f"drop_{r}" in t and t[f"drop_{r}"]["reason"]
        assert t[f"drop_{r}"]["rows_dropped"] == int((LAPS.drop_reason == r).sum())
    assert "wet_races_excluded" in t


def test_cliff_search_never_trains_on_the_held_out_race(tmp_path):
    """Run the real cliff() on a few races and record every training mask it fits on. Apart from the one full-data
    fit, each mask must leave out exactly one whole race and keep every other race (no leakage, nothing else lost)."""
    c = A.clean_laps(A.load()[0])
    keep = c["session_key"].drop_duplicates().iloc[:6]
    c = c[c["session_key"].isin(keep)].reset_index(drop=True)
    races = c["session_key"].to_numpy()
    seen = []
    real = A.lstsq_resid

    def spy(y, X, train):
        seen.append(train.copy())
        return real(y, X, train)

    mp = pytest.MonkeyPatch()
    mp.setattr(A, "lstsq_resid", spy)
    mp.setattr(A, "MIN_LAPS_SIDE", 50)
    try:
        rs = ResultStore(tmp_path)
        A.identification(c, rs)
        A.main_model(c, rs)
        seen.clear()
        A.cliff(c, rs)
    finally:
        mp.undo()
    loro = [m for m in seen if not m.all()]
    assert loro, "cliff() made no leave-one-race-out fits"
    for m in loro:
        out = set(races[~m])
        assert len(out) == 1, "a training mask dropped more than one race"
        assert not (set(races[m]) & out), "held-out race leaked into training"
        assert set(races[m]) == set(races) - out


def test_every_kept_race_is_sane():
    races = pd.read_csv(CASE_DIR / "aggregates" / "races.csv")
    kept = races[~races.wet & ~races.incomplete]
    g = LAPS.groupby("session_key").agg(clean=("drop_reason", lambda s: s.isna().sum()), neut=("neutralised", "mean"))
    assert set(g.index) == set(kept.session_key)
    assert (g["clean"] > 0).all(), "a kept race has no clean laps"
    assert (g["neut"] < 0.4).all(), g[g.neut >= 0.4]
    assert (kept["lap_coverage"] >= C.MIN_LAP_COVERAGE).all()


def test_wet_means_inters_or_wets_were_used():
    races = pd.read_csv(CASE_DIR / "aggregates" / "races.csv").fillna({"other_compounds": ""})
    used_wet = races["other_compounds"].str.contains("INTERMEDIATE|WET")
    assert (races["wet"] == used_wet).all()


def test_race_control_windows_close():
    """VSC upgraded to SC, SC ended by a red flag, red flag until the session restarts."""
    t = lambda s: f"2025-01-01T00:{s}+00:00"
    rc = pd.DataFrame([
        {"date": t("00:00"), "category": "SafetyCar", "flag": None, "message": "VIRTUAL SAFETY CAR DEPLOYED"},
        {"date": t("01:00"), "category": "SafetyCar", "flag": None, "message": "SAFETY CAR DEPLOYED"},
        {"date": t("02:00"), "category": "Flag", "flag": "RED", "message": "RED FLAG"},
        {"date": t("05:00"), "category": "SessionStatus", "flag": None, "message": "SESSION STARTED"},
        {"date": t("30:00"), "category": "Flag", "flag": "CHEQUERED", "message": "CHEQUERED FLAG"},
    ])
    w = C.windows(rc)
    ends = sorted(b for _, b, _ in w)
    assert max(ends) == pd.Timestamp(t("05:00")), "a window stayed open to the end of the race"
    assert len(w) == 3


def test_wear_ordering_and_fuel_sign():
    assert EXPECTED["fuel_slope"]["value"] < 0                       # laps get faster as fuel burns off
    assert EXPECTED["deg_soft"]["value"] > EXPECTED["deg_hard"]["value"] > 0


def test_decision_split_length_formula():
    P = EXPECTED["pit_loss"]["value"]
    for comp in ("soft", "medium", "hard"):
        s = EXPECTED[f"deg_{comp}"]["value"]
        assert math.isclose(EXPECTED[f"split_len_{comp}"]["value"], 2 * math.sqrt(P / s), rel_tol=1e-12)
        assert EXPECTED[f"split_len_{comp}_short"]["value"] <= EXPECTED[f"split_len_{comp}"]["value"] \
            <= EXPECTED[f"split_len_{comp}_long"]["value"]


def test_charts_exported():
    for cid in ("p13_example_stint", "p13_wear_curves", "p13_stint_survival", "p13_loro"):
        for ext in ("json", "png"):
            assert (CASE_DIR / "charts" / f"{cid}.{ext}").exists()
        chart = json.loads((CASE_DIR / "charts" / f"{cid}.json").read_text(encoding="utf-8"))
        assert all(k in EXPECTED for k in chart["result_keys"]), cid
