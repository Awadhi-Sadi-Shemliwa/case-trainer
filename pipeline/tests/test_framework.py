from __future__ import annotations

import copy
import json
import sqlite3

import numpy as np
import pandas as pd
import pytest

from build_content import build, hand_typed_numbers
from common.charts import MAX_POINTS, Axis, Chart, lttb, make_series, regions_from_indicator
from common.io import SnippetError, extract_snippets
from common.provenance import Provenance, ProvenanceError, sha256_file
from common.results import ResultError, ResultStore
from tests.conftest import FakeDownloader, rewrite_content


def run_build(fx, **kw):
    return build(cases_dir=fx["cases"], cal_root=fx["cal"], sources_file=fx["sources"], out_dir=fx["out"], **kw)


# --------------------------------------------------------------------------- provenance
def test_fetch_saves_bytes_untouched_and_hashes(tmp_path):
    payload = b"a,b\n1,.\n"
    prov = Provenance(tmp_path, downloader=FakeDownloader(payload))
    p = prov.fetch("k", "https://x.invalid/a.csv", "a.csv", licence_note="public domain")
    assert p.read_bytes() == payload
    e = prov.data["datasets"]["k"]
    assert e["sha256"] == sha256_file(p) and e["retrieved_utc"].endswith("Z") and e["bytes"] == len(payload)


def test_fetch_uses_cache_and_detects_tampering(tmp_path):
    dl = FakeDownloader(b"x\n1\n")
    prov = Provenance(tmp_path, downloader=dl)
    p = prov.fetch("k", "u", "a.csv", licence_note="l")
    prov.fetch("k", "u", "a.csv", licence_note="l")
    assert dl.calls == 1
    p.write_bytes(b"x\n2\n")
    with pytest.raises(ProvenanceError):
        prov.fetch("k", "u", "a.csv", licence_note="l")
    assert prov.verify_hashes()


def test_licence_and_reason_required(tmp_path):
    prov = Provenance(tmp_path, downloader=FakeDownloader(b"x"))
    with pytest.raises(ProvenanceError):
        prov.fetch("k", "u", "a.csv", licence_note=" ")
    prov.fetch("k", "u", "a.csv", licence_note="l")
    with pytest.raises(ProvenanceError):
        prov.log_transform("k", "t1", 10, 8, reason="")
    rec = prov.log_transform("k", "t1", 10, 8, reason="dupes")
    assert rec["rows_dropped"] == 2
    prov.log_transform("k", "t1", 10, 7, reason="rerun replaces")
    assert len(prov.data["transforms"]) == 1 and prov.transform("t1")["rows_dropped"] == 3


def test_describe_records_schema(tmp_path, capsys):
    prov = Provenance(tmp_path, downloader=FakeDownloader(b"x"))
    prov.fetch("k", "u", "a.csv", licence_note="l")
    df = pd.DataFrame({"a": [1.0, None], "b": ["x", "y"]})
    s = prov.describe("k", df)
    assert s["rows"] == 2 and s["missing"]["a"] == 1 and s["columns"] == ["a", "b"]
    assert "=== schema: k ===" in capsys.readouterr().out


# --------------------------------------------------------------------------- results
def test_result_store_roundtrip(tmp_path):
    rs = ResultStore(tmp_path)
    rs.put("auc_oos", np.float64(0.8123), "", "AUC", decimals=3)
    rs.put("share", 0.25, "", "share", pct=True)
    rs.put("n_rows", 12345, "rows", "rows")
    rs.save()
    r = ResultStore.load(tmp_path)
    assert r["auc_oos"]["display"] == "0.812"
    assert r["share"]["display"] == "25.0%"
    assert r["n_rows"]["display"] == "12,345"
    assert r["auc_oos"]["produced_by"].endswith(":test_result_store_roundtrip")


@pytest.mark.parametrize("key,val", [("Bad Key", 1), ("ok", float("nan")), ("ok2", [1])])
def test_result_store_rejects(tmp_path, key, val):
    with pytest.raises(ResultError):
        ResultStore(tmp_path).put(key, val, "", "d")


def test_result_store_duplicate(tmp_path):
    rs = ResultStore(tmp_path)
    rs.put("a", 1, "", "d")
    with pytest.raises(ResultError):
        rs.put("a", 2, "", "d")


# --------------------------------------------------------------------------- charts
def test_lttb_keeps_endpoints_and_peak():
    x = np.arange(10000, dtype=float)
    y = np.sin(x / 300)
    y[5000] = 50.0
    idx = lttb(x, y, 500)
    assert idx[0] == 0 and idx[-1] == 9999 and 5000 in idx and len(idx) <= 500


def test_make_series_downsamples_dates():
    d = pd.date_range("1990-01-01", periods=9000, freq="D")
    s = make_series("s", d, np.random.default_rng(0).normal(size=9000))
    assert len(s.x) < MAX_POINTS and s.original_points == 9000 and s.x[0] == "1990-01-01"


def test_chart_validation():
    with pytest.raises(ValueError):
        Chart(id="c", type="line", title="t", x_axis=Axis(title="x"), y_axis=Axis(title="y"), source_note="s")
    with pytest.raises(ValueError):
        Chart(id="c", type="line", title="t", x_axis=Axis(title="x"), y_axis=Axis(title="y"), source_note="s",
              series=[make_series("a", range(3000), range(3000), downsample=False)])


def test_regions_from_indicator():
    d = pd.date_range("2000-01-01", periods=6, freq="MS")
    r = regions_from_indicator(d, [0, 1, 1, 0, 1, 1], "rec")
    assert [(x.start, x.end) for x in r] == [("2000-02-01", "2000-03-01"), ("2000-05-01", "2000-06-01")]


def test_all_chart_types_render(tmp_path):
    from common.charts import BoxStat, Heatmap, Histogram, export_chart
    base = dict(title="t", x_axis=Axis(title="x"), y_axis=Axis(title="y", unit="u"), source_note="s")
    charts = [
        Chart(id="sc", type="scatter", series=[make_series("a", [1, 2], [3, 4]),
              make_series("fit", [1, 2], [3, 4], role="fitted")], **base),
        Chart(id="br", type="bar", series=[make_series("a", ["x", "y"], [1, 2])], **base),
        Chart(id="sb", type="stacked_bar", series=[make_series("a", ["x", "y"], [1, 2]),
              make_series("b", ["x", "y"], [2, 1])], **base),
        Chart(id="hi", type="histogram", histogram=Histogram(bin_edges=[0, 1, 2], counts={"a": [3, 4]}), **base),
        Chart(id="bx", type="box", box=[BoxStat(category="a", whisker_low=0, q1=1, median=2, q3=3, whisker_high=4)], **base),
        Chart(id="hm", type="heatmap", heatmap=Heatmap(x_categories=["a", "b"], y_categories=["r"], values=[[1, 2]]), **base),
    ]
    for c in charts:
        jp, pp = export_chart(c, tmp_path)
        assert json.loads(jp.read_text())["type"] == c.type and pp.stat().st_size > 0


# --------------------------------------------------------------------------- snippets
def test_extract_snippets(tmp_path):
    f = tmp_path / "a.py"
    f.write_text("a=1\n    # >>> snippet: s1\n    b = 2\n    # <<< snippet\n")
    assert extract_snippets(f) == {"s1": "b = 2"}
    f.write_text("# >>> snippet: s1\nb=2\n")
    with pytest.raises(SnippetError):
        extract_snippets(f)


# --------------------------------------------------------------------------- build
def test_hand_typed_numbers():
    assert hand_typed_numbers("AUC was 0.81", []) == ["0.81"]
    assert hand_typed_numbers("AUC was {expected.auc}", []) == []
    assert hand_typed_numbers("The 10-year minus 2-year", ["10-year", "2-year"]) == []


def test_build_ok_writes_bundle(fixture_case):
    fx = fixture_case
    assert run_build(fx) == 0
    con = sqlite3.connect(fx["out"] / "content.sqlite")
    assert con.execute("select count(*) from steps").fetchone()[0] == 3
    assert con.execute("select display from results where key='fx_mean'").fetchone()[0] == "1.50"
    assert con.execute("select code from snippets").fetchone()[0].startswith("m = df")
    assert (fx["out"] / "charts" / "fx_chart.json").exists()
    step = json.loads(con.execute("select json from steps where id='s3_chart'").fetchone()[0])
    assert "{expected.fx_mean}" in step["prompt"]  # app substitutes at render time


def _mutate(fx, fn):
    c = copy.deepcopy(fx["content"])
    fn(c)
    rewrite_content(fx, c)


@pytest.mark.parametrize("mutation", [
    lambda c: c["steps"][2].__setitem__("model_answer", "Mean is {expected.missing_key}"),   # missing key
    lambda c: c["steps"][2]["rubric"]["points"][0].__setitem__("weight", 15),                 # weights 90
    lambda c: c["steps"][2].__setitem__("chart", "no_such_chart"),                            # chart missing
    lambda c: c.__setitem__("sources", ["unknown_source"]),                                   # source missing
    lambda c: c["steps"][2].__setitem__("model_answer", "The mean is 1.5"),                   # hand-typed number
    lambda c: c["steps"][1]["blanks"][0].__setitem__("token", ".median()"),                   # blank not in code
    lambda c: c.__setitem__("datasets", ["not_downloaded"]),                                  # dataset missing
])
def test_build_fails(fixture_case, mutation):
    _mutate(fixture_case, mutation)
    assert run_build(fixture_case, check_only=True) == 1


def test_build_fails_without_calibration(fixture_case):
    (fixture_case["cal"] / "fx_case" / "s3_chart.yaml").unlink()
    assert run_build(fixture_case, check_only=True) == 1


def test_build_fails_on_unverified_source(fixture_case):
    s = json.loads(fixture_case["sources"].read_text())
    s[0]["status"] = "UNVERIFIED"
    fixture_case["sources"].write_text(json.dumps(s))
    assert run_build(fixture_case, check_only=True) == 1


def test_build_fails_on_tampered_raw(fixture_case):
    (fixture_case["case"] / "raw" / "fx.csv").write_bytes(b"tampered")
    assert run_build(fixture_case, check_only=True) == 1
