"""P3 tests. Raw BTS zips (~350 MB) are not committed, so:
* the analysis is always re-run from the committed aggregates and must reproduce every result key;
* the full clean (raw -> aggregates) is re-run only when the raw zips are present, and must reproduce the aggregates.
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

import pandas as pd
import pytest

from cases.p3_delay_prop import analyse as A
from cases.p3_delay_prop import clean as C
from common.provenance import Provenance
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
EXPECTED = ResultStore.load(CASE_DIR)
RAW_PRESENT = all((CASE_DIR / "raw" / f"ontime_2025_{m:02d}.zip").exists() for m in range(1, 13))


@pytest.fixture(scope="module")
def rerun(tmp_path_factory):
    work = tmp_path_factory.mktemp("p3")
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
        assert math.isclose(got, exp, rel_tol=1e-9, abs_tol=1e-9), (key, got, exp)
    else:
        assert got == exp, (key, got, exp)


def test_no_unexpected_new_results(rerun):
    assert set(rerun[1]) == set(EXPECTED)


@pytest.mark.skipif(not RAW_PRESENT, reason="raw BTS zips not downloaded (git-ignored); run download.py")
def test_raw_hashes_and_full_clean_reproduce_aggregates(tmp_path):
    assert Provenance(CASE_DIR).verify_hashes() == []
    shutil.copy2(CASE_DIR / "provenance.json", tmp_path / "provenance.json")
    mp = pytest.MonkeyPatch()
    mp.setattr(C, "CASE_DIR", tmp_path)
    mp.setattr(C, "RAW", CASE_DIR / "raw")
    mp.setattr(C, "AGG", tmp_path / "aggregates")
    try:
        C.clean()
    finally:
        mp.undo()
    for f in ["flights_month.csv", "hub_hour.csv", "rotations.csv"]:
        a = pd.read_csv(CASE_DIR / "aggregates" / f)
        b = pd.read_csv(tmp_path / "aggregates" / f)
        pd.testing.assert_frame_equal(a, b, check_exact=False, rtol=1e-12)


def test_pass_through_falls_with_turn_length():
    p = [EXPECTED[f"pass_b{i}"]["value"] for i in range(1, EXPECTED["n_bands"]["value"] + 1)]
    assert all(a > b for a, b in zip(p, p[1:]))
    assert p[0] > 1.0                                    # tightest turns amplify


def test_cause_shares_sum_to_one_and_proration_holds():
    s = sum(EXPECTED[k]["value"] for k in EXPECTED if k.startswith("share_"))
    assert math.isclose(s, 1.0, abs_tol=1e-9)
    assert abs(EXPECTED["proration_gap"]["value"] - 1.0) < 0.01


def test_transforms_logged_once_with_reasons():
    t = json.loads((CASE_DIR / "provenance.json").read_text(encoding="utf-8"))["transforms"]
    ids = [x["id"] for x in t]
    assert len(ids) == len(set(ids))
    assert {"rotation_turn_window", "rotation_delay_range", "cancelled_diverted_excluded"} <= set(ids)
    assert all(x["reason"] for x in t)


def test_buffer_rule_uses_training_months_only():
    assert EXPECTED["buffer_min_turn"]["value"] in (20, 45, 60, 75, 90, 120)
    assert EXPECTED["max_slope_shift"]["value"] < 0.1   # stable from Jan-Sep to Oct-Dec
