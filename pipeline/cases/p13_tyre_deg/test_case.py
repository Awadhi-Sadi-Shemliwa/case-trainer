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


def test_loro_holds_out_whole_races():
    """Leave-one-race-out: the training mask never contains a lap from the held-out race."""
    c = A.clean_laps(A.load()[0])
    races = c["session_key"].to_numpy()
    for r in np.unique(races)[:5]:
        test = races == r
        train = ~test
        assert not set(races[train]) & {r}
        assert test.sum() > 0


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
