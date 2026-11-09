"""P34 tests: raw files unchanged, every result reproducible from raw, period logic sane."""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

import pandas as pd
import pytest

from cases.p34_home_adv import analyse as A
from cases.p34_home_adv import clean as C
from common.provenance import Provenance
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
EXPECTED = ResultStore.load(CASE_DIR)


def test_raw_files_match_provenance_hashes():
    assert Provenance(CASE_DIR).verify_hashes() == []


@pytest.fixture(scope="module")
def rerun(tmp_path_factory):
    work = tmp_path_factory.mktemp("p34")
    shutil.copytree(CASE_DIR / "raw", work / "raw")
    shutil.copy2(CASE_DIR / "provenance.json", work / "provenance.json")
    mp = pytest.MonkeyPatch()
    for mod in (C, A):
        mp.setattr(mod, "CASE_DIR", work)
    mp.setattr(C, "RAW", work / "raw")
    try:
        C.clean()
        yield work, A.analyse().results
    finally:
        mp.undo()


@pytest.mark.parametrize("key", sorted(EXPECTED))
def test_every_result_reproduces(rerun, key):
    _, fresh = rerun
    exp, got = EXPECTED[key]["value"], fresh[key]["value"]
    if isinstance(exp, float):
        assert math.isclose(got, exp, rel_tol=1e-6, abs_tol=1e-9), (key, got, exp)
    else:
        assert got == exp, (key, got, exp)


def test_no_unexpected_new_results(rerun):
    assert set(rerun[1]) == set(EXPECTED)


def test_captured_outputs_reproduce(rerun):
    a = json.loads((CASE_DIR / "captured_outputs.json").read_text(encoding="utf-8"))
    b = json.loads((rerun[0] / "captured_outputs.json").read_text(encoding="utf-8"))
    assert a == b


def test_all_matches_kept_and_seasons_complete():
    df = pd.read_csv(CASE_DIR / "matches_clean.csv", parse_dates=["Date"])
    per = df.groupby(["league", "season"]).size()
    assert per.loc["Bundesliga"].eq(306).all()          # 18 teams
    for lg in ["Premier League", "La Liga", "Serie A"]:
        assert per.loc[lg].eq(380).all()                # 20 teams
    assert df[["FTHG", "FTAG", "HF", "AF", "HY", "AY"]].notna().all().all()


def test_periods_are_ordered_in_time():
    df = pd.read_csv(CASE_DIR / "matches_clean.csv", parse_dates=["Date"])
    for _, g in df.groupby("league"):
        assert g.loc[g.period == "fans", "Date"].max() < g.loc[g.period == "ghost", "Date"].min()
        assert g.loc[g.period == "ghost", "Date"].max() < g.loc[g.period == "fans_back", "Date"].min()
    # the restart is in spring/summer 2020 for every league, found from the data
    restarts = Provenance(CASE_DIR).transform("assign_period")["details"]["restart"]
    assert all(v.startswith("2020-05") or v.startswith("2020-06") for v in restarts.values())


def test_holm_is_never_more_lenient_than_raw():
    assert EXPECTED["n_leagues_significant"]["value"] <= EXPECTED["n_leagues_unadjusted_sig"]["value"]


def test_effect_signs():
    assert EXPECTED["hw_change"]["value"] < 0
    assert EXPECTED["gd_ghost"]["value"] > 0             # shrank, did not vanish
    assert EXPECTED["hw_change_lo"]["value"] < EXPECTED["hw_change"]["value"] < EXPECTED["hw_change_hi"]["value"]
