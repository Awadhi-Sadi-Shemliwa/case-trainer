"""P50 tests: raw data unchanged, every result reproducible from raw, no look-ahead, sane metrics.

Spec §2: every number shown in the app is a key in expected_results.json, asserted by pytest.
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

import pandas as pd
import pytest

from cases.p50_yield_curve import analyse as A
from cases.p50_yield_curve import clean as C
from common.provenance import Provenance
from common.results import ResultStore

CASE_DIR = Path(__file__).resolve().parent
EXPECTED = ResultStore.load(CASE_DIR)


def test_raw_files_match_provenance_hashes():
    assert Provenance(CASE_DIR).verify_hashes() == []


@pytest.fixture(scope="module")
def rerun(tmp_path_factory):
    """Re-run clean + analyse from the raw files in a scratch copy of the case directory."""
    work = tmp_path_factory.mktemp("p50")
    shutil.copytree(CASE_DIR / "raw", work / "raw")
    shutil.copy2(CASE_DIR / "provenance.json", work / "provenance.json")
    mp = pytest.MonkeyPatch()
    mp.setattr(C, "CASE_DIR", work)
    mp.setattr(C, "RAW", work / "raw")
    mp.setattr(A, "CASE_DIR", work)
    try:
        C.clean()
        rs = A.analyse()
        yield work, rs.results
    finally:
        mp.undo()


def test_expected_results_present():
    assert len(EXPECTED) > 50


@pytest.mark.parametrize("key", sorted(EXPECTED))
def test_every_result_reproduces(rerun, key):
    _, fresh = rerun
    assert key in fresh, f"{key} no longer produced"
    exp, got = EXPECTED[key]["value"], fresh[key]["value"]
    if isinstance(exp, float):
        assert math.isclose(got, exp, rel_tol=1e-6, abs_tol=1e-9), (key, got, exp)
    else:
        assert got == exp, (key, got, exp)
    assert fresh[key]["display"] == EXPECTED[key]["display"]


def test_no_unexpected_new_results(rerun):
    _, fresh = rerun
    assert set(fresh) == set(EXPECTED)


def test_captured_outputs_reproduce(rerun):
    work, _ = rerun
    a = json.loads((CASE_DIR / "captured_outputs.json").read_text(encoding="utf-8"))
    b = json.loads((work / "captured_outputs.json").read_text(encoding="utf-8"))
    assert a == b


def test_embargo_no_lookahead():
    """At forecast month t the model may only train on rows s <= t - 13 (their target needs USREC to s+12 <= t-1)."""
    p = A.load_panel()
    ts = p["T10Y3M"].first_valid_index()
    start = A.first_oos_month(p, ts)
    f = A.expanding_oos(p, "T10Y3M", start, ts)
    data = p.loc[ts:]
    for t in list(f.index[:3]) + list(f.index[-3:]):
        allowed = data.loc[: t - pd.DateOffset(months=A.EMBARGO)]
        allowed = allowed[allowed["model_sample"]].dropna(subset=["T10Y3M"])
        assert f.at[t, "n_train"] == len(allowed)
        # every training row's target window ends BEFORE the forecast month (USREC(t) unknown during month t)
        assert (allowed.index + pd.DateOffset(months=A.HORIZON)).max() <= t - pd.DateOffset(months=1)


def test_model_sample_has_no_recession_months_or_unknown_targets():
    p = A.load_panel()
    m = p[p["model_sample"]]
    assert (m["USREC"] == 0).all()
    assert m["rec_next12"].notna().all()
    assert m[["T10Y2Y"]].notna().all().all()


def test_metric_ranges():
    for k, v in EXPECTED.items():
        if k.startswith("auc_"):
            assert 0.5 <= v["value"] <= 1.0, k
        if k.startswith("brier_"):
            assert 0.0 <= v["value"] <= 0.25, k
    assert 0 < EXPECTED["threshold"]["value"] < 1
    assert EXPECTED["probit_slope_10y3m"]["value"] < 0  # flatter/inverted curve -> higher probability
    assert EXPECTED["se_ratio_10y3m"]["value"] > 1      # overlap makes naive SEs too small


def test_target_definition():
    p = A.load_panel()
    # month before the 2008 recession start must have target 1; a calm mid-expansion month must be 0
    assert p.at[pd.Timestamp("2007-12-01"), "rec_next12"] == 1
    assert p.at[pd.Timestamp("1995-06-01"), "rec_next12"] == 0
    assert p["rec_next12"].tail(C.HORIZON).isna().all()


def test_transforms_logged_with_reasons():
    prov = Provenance(CASE_DIR)
    ids = {t["id"] for t in prov.data["transforms"]}
    assert {"drop_blank_t10y2y", "drop_blank_t10y3m", "align_months", "target_unknown_last_months",
            "exclude_current_recession"} <= ids
    assert all(t["reason"] for t in prov.data["transforms"])


def test_charts_exported():
    for cid in ("p50_spread_recessions", "p50_spread_vs_forward", "p50_oos_probability", "p50_roc"):
        for ext in ("json", "png"):
            assert (CASE_DIR / "charts" / f"{cid}.{ext}").exists()
        chart = json.loads((CASE_DIR / "charts" / f"{cid}.json").read_text(encoding="utf-8"))
        for k in chart["result_keys"]:
            assert k in EXPECTED, (cid, k)
