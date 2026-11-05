"""Tiny, obviously-fake fixture case used ONLY by framework tests (spec Prompt 2: 'Use a tiny test
fixture created inside the tests only'). It never reaches the app bundle."""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest
import yaml

from common.charts import Axis, Chart, export_chart, make_series
from common.io import capture_output
from common.provenance import Provenance
from common.results import ResultStore


class FakeDownloader:
    def __init__(self, payload: bytes):
        self.payload = payload
        self.calls = 0

    def get(self, url, headers):
        self.calls += 1
        return self.payload


def _point(pid: str, weight: int) -> dict:
    return {
        "id": pid, "label": "Fixture area", "weight": weight,
        "paraphrases": ["fixture paraphrase a", "fixture paraphrase b", "fixture paraphrase c"],
        "keywords": [["alpha", "beta"]], "hint": "look again", "why": "it matters",
    }


def _flag(fid: str, critical: bool = False) -> dict:
    return {"id": fid, "critical": critical, "penalty": 20, "paraphrases": ["bad claim"], "feedback": "no"}


@pytest.fixture
def fixture_case(tmp_path: Path):
    """Builds a complete, valid case directory + sources.json + calibration root. Returns dict of paths."""
    cases = tmp_path / "cases"
    cdir = cases / "fx_case"
    cdir.mkdir(parents=True)
    cal = tmp_path / "calibration"
    (cal / "fx_case").mkdir(parents=True)

    # raw data + provenance (FakeDownloader: no network)
    prov = Provenance(cdir, downloader=FakeDownloader(b"date,value\n2020-01-01,1.5\n2020-01-02,.\n"))
    path = prov.fetch("fx_raw", "https://example.invalid/fx.csv", "fx.csv", licence_note="test fixture")
    df = pd.read_csv(path, na_values=".")
    prov.describe("fx_raw", df, print_schema=False)
    prov.log_transform("fx_raw", "drop_na", len(df), len(df.dropna()), reason="missing value marker")
    prov.save()

    # real code with a snippet + captured output
    (cdir / "analyse.py").write_text(
        "x = 1\n# >>> snippet: mean_calc\nm = df['value'].mean()\nprint(m)\n# <<< snippet\n", encoding="utf-8")
    with capture_output(cdir, "mean_calc"):
        print(df["value"].mean())

    rs = ResultStore(cdir)
    rs.put("fx_mean", float(df["value"].mean()), "units", "fixture mean", decimals=2)
    rs.save()

    chart = Chart(id="fx_chart", type="line", title="Fixture", x_axis=Axis(title="Date", kind="date"),
                  y_axis=Axis(title="Value", unit="u"),
                  series=[make_series("v", pd.to_datetime(df["date"]), df["value"])], source_note="fixture")
    export_chart(chart, cdir / "charts")

    content = {
        "id": "fx_case", "number": 99, "domain": "finance", "title": "Fixture case", "tier": "A",
        "decision_maker": "Tester", "decision": "Pass the tests?", "money_at_stake": "None",
        "concepts": ["testing"], "sources": ["fx_source"], "datasets": ["fx_raw"],
        "allowed_literals": ["2s10s"],
        "steps": [
            {"id": "s1_brief", "phase": "brief", "type": "mcq", "title": "Q", "prompt": "Who decides?",
             "options": [{"id": "a", "text": "Tester", "correct": True, "explanation": "yes"},
                         {"id": "b", "text": "Nobody", "explanation": "no"}]},
            {"id": "s2_code", "phase": "data", "type": "code_fill", "title": "Fill", "prompt": "Fill the blank",
             "snippet": {"file": "analyse.py", "name": "mean_calc"}, "blanks": [{"token": ".mean()"}]},
            {"id": "s3_chart", "phase": "explore", "type": "chart_explain", "title": "Explain",
             "prompt": "Explain the 2s10s chart; mean is {expected.fx_mean}", "chart": "fx_chart",
             "scaffold": "chart_6q", "analysis_pointer": "look at the line",
             "rubric": {"points": [_point("p1", 25), _point("p2", 25), _point("p3", 25), _point("p4", 25)],
                        "red_flags": [_flag("r1", True), _flag("r2"), _flag("r3")]},
             "model_answer": "The mean is {expected.fx_mean}."},
        ],
        "debrief": {"concepts_learned": ["testing"], "common_mistakes": ["none"],
                    "interview_summary": "Mean was {expected.fx_mean}."},
    }
    (cdir / "content.yaml").write_text(yaml.safe_dump(content, sort_keys=False), encoding="utf-8")

    answers = [{"id": f"a{i}", "text": "answer", "label": "acceptable" if i % 2 else "not_acceptable",
                "kind": "strong" if i % 2 else "wrong"} for i in range(30)]
    (cal / "fx_case" / "s3_chart.yaml").write_text(yaml.safe_dump({"answers": answers}), encoding="utf-8")

    sources = tmp_path / "sources.json"
    sources.write_text(json.dumps([{
        "key": "fx_source", "title": "T", "authors": ["A"], "year": 2000, "url": "https://example.invalid",
        "verified_on": "2026-11-05", "quote": "short quote", "status": "VERIFIED"}]), encoding="utf-8")

    return {"root": tmp_path, "cases": cases, "case": cdir, "cal": cal, "sources": sources,
            "out": tmp_path / "out", "content": content}


def rewrite_content(fx: dict, content: dict) -> None:
    (fx["case"] / "content.yaml").write_text(yaml.safe_dump(content, sort_keys=False), encoding="utf-8")
