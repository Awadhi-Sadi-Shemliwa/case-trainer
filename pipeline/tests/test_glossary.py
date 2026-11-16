"""Finance Foundations course (owner requests 2026-11-15/16): 340 ranked words (Core gained the methods lesson on 2026-11-16), validated like the cases."""

from __future__ import annotations

import sqlite3

import pytest
import yaml

from build_content import CASES_DIR, LEARN_DIR, SOURCES_FILE, discover_cases, load_sources
from common.glossary import (
    Example,
    ExampleError,
    Reading,
    check_formula,
    render_example,
    render_reading,
    safe_eval,
    term_json,
    validate_course,
    write_course,
)


@pytest.fixture(scope="module")
def course():
    sources, errs = load_sources(SOURCES_FILE)
    assert not errs
    case_steps = {}
    for cdir in discover_cases(CASES_DIR):
        d = yaml.safe_load((cdir / "content.yaml").read_text(encoding="utf-8"))
        case_steps[d["id"]] = {s["id"] for s in d["steps"]}
    c, ordered, errors = validate_course(LEARN_DIR, sources, case_steps, complete=True)
    return c, ordered, errors


# --------------------------------------------------------------------------- safe arithmetic
def test_safe_eval_does_arithmetic_only():
    assert safe_eval("2 * (3 + 4) ** 2 / 7", {}) == 14
    assert safe_eval("sqrt(x) + max(a, b) - abs(-1)", {"x": 9, "a": 1, "b": 2}) == 4
    assert safe_eval("-y", {"y": 3}) == -3
    for bad in ["__import__('os')", "x.real", "[1][0]", "(lambda: 1)()", "open('f')", "1 if 1 else 2",
                "unknown + 1", "1 / 0 if 0 else 1", "{1: 2}", "'a'"]:
        with pytest.raises((ExampleError, ZeroDivisionError)):
            safe_eval(bad, {"x": 1})


def test_render_example_wraps_every_number():
    ex = Example(values={"P": 1000, "r": 0.05}, compute={"I": "P * r"},
                 formats={"P": "£{:,.0f}", "r": "{:.0%}"}, text="{P} at {r} earns {I}.")
    text, env = render_example(ex)
    assert text == "[[£1,000]] at [[5%]] earns [[50]]."
    assert env["I"] == 50
    with pytest.raises(ExampleError):
        render_example(Example(values={"a": 1}, compute={}, text="{missing}"))
    with pytest.raises(ExampleError):
        render_example(Example(values={"a": 1}, compute={"a": "a + 1"}, text="{a}"))


def test_formula_checker_rejects_bad_tex():
    assert check_formula(r"\frac{a}{b}") is None
    assert check_formula(r"\frac{a}{") is not None


# --------------------------------------------------------------------------- the real course
def test_course_is_valid(course):
    _, _, errors = course
    assert errors == []


def test_course_shape(course):
    """Core = ten finance lessons + four lessons of measures and methods (owner requests 2026-11-16); the others ten each."""
    c, ordered, _ = course
    assert [t.id for t in c.tiers] == ["core", "intermediate", "quant"]
    assert [len(t.lessons) for t in c.tiers] == [14, 10, 10]
    assert len(ordered) == 340
    assert [sum(1 for tr, _, _ in ordered if tr.id == tier.id) for tier in c.tiers] == [140, 100, 100]
    assert len({t.id for _, _, t in ordered}) == 340
    core = c.tiers[0].lessons
    assert [ls.kind for ls in core] == ["finance"] * 10 + ["measures"] * 4
    assert all(ls.kind == "finance" for tier in c.tiers[1:] for ls in tier.lessons)


def test_owner_gaps_are_in_the_first_lessons(course):
    """The owner did not know equity or recession: both sit near the top of the ranking."""
    _, ordered, _ = course
    rank = {t.id: i + 1 for i, (_, _, t) in enumerate(ordered)}
    assert rank["equity"] <= 10
    assert rank["recession"] <= 30
    assert rank["yield_curve"] <= 60 and rank["inversion"] <= 60


def test_every_p50_concept_is_taught(course):
    _, ordered, _ = course
    names = {n.lower() for _, _, t in ordered for n in [t.term, *t.aliases]}
    for concept in ["AUC", "Brier score", "base rate", "probit", "HAC", "expanding window", "embargo",
                    "calibration", "decision threshold", "regime change", "time series", "look-ahead leakage"]:
        assert concept.lower() in names, concept


def test_every_example_recomputes_and_uses_only_its_numbers(course):
    _, ordered, _ = course
    for _, _, t in ordered:
        if t.example is None:
            continue
        text, env = render_example(t.example)
        assert "[[" in text, t.id
        assert all(isinstance(v, float) for v in env.values()), t.id


def test_bundle_has_terms_and_formula_images(course, tmp_path):
    c, ordered, _ = course
    con = sqlite3.connect(tmp_path / "c.sqlite")
    write_course(con, c, ordered, tmp_path)
    assert con.execute("select count(*) from terms").fetchone()[0] == 340
    assert con.execute("select count(*) from lessons").fetchone()[0] == 34
    assert con.execute("select min(rank), max(rank) from terms").fetchone() == (1, 340)
    with_formula = [t for _, _, t in ordered if t.formula]
    assert len(list((tmp_path / "formulas").glob("*.png"))) == len(with_formula)
    png = (tmp_path / "formulas" / "equity.png").read_bytes()
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    kind = dict(con.execute("select id, json_extract(json, '$.kind') from lessons").fetchall())
    assert kind["core_11_forecast_scores"] == "measures" and kind["core_01_money"] == "finance"


# --------------------------------------------------------------------------- measures (owner request 2026-11-16)
def _reading(**over) -> Reading:
    base = dict(values={"auc": 0.78}, compute={"pct": "auc"}, formats={"auc": "{:.2f}", "pct": "{:.0%}"},
                question="What does an AUC of {auc} mean?", means="Right in {pct} of pairs.",
                misreadings=["Accurate in {pct} of months.", "Catches {pct} of events.", "Alarms right {pct}."],
                scale={"lo": 0.5, "hi": 1, "format": "{:.1f}"}, point="auc",
                marks=[{"at": 0.5, "label": "coin toss"}],
                bands=[{"upto": 0.7, "label": "weak"}, {"upto": 1, "label": "good"}], bands_source="src")
    base.update(over)
    return Reading.model_validate(base)


def test_render_reading_formats_every_number_and_position():
    out, env = render_reading(_reading())
    assert out["question"] == "What does an AUC of 0.78 mean?"
    assert out["means"] == "Right in [[78%]] of pairs."
    assert out["misreadings"][0] == "Accurate in 78% of months."
    assert out["scale"] == {"lo": 0.5, "hi": 1.0, "lo_text": "0.5", "hi_text": "1.0", "better": "neither"}
    assert out["point"] == {"at": 0.78, "text": "0.78"}
    assert out["marks"] == [{"at": 0.5, "text": "0.5", "label": "coin toss"}]
    assert [(b["lo_text"], b["hi_text"], b["label"]) for b in out["bands"]] == [("0.5", "0.7", "weak"),
                                                                              ("0.7", "1.0", "good")]
    assert env["pct"] == 0.78


@pytest.mark.parametrize("over, message", [
    ({"values": {"auc": 0.4}}, "outside the scale"),
    ({"bands": [{"upto": 0.8, "label": "weak"}, {"upto": 0.7, "label": "good"}]}, "must end above"),
    ({"bands": [{"upto": 0.7, "label": "weak"}, {"upto": 0.9, "label": "good"}]}, "last band must end"),
    ({"bands_source": None}, "rule of thumb needs its source"),
    ({"misreadings": ["Right in {pct} of pairs.", "b", "c"]}, "must differ"),
    ({"scale": None}, "need a scale"),
    ({"point": "missing"}, "has no value"),
])
def test_render_reading_rejects_bad_scales(over, message):
    with pytest.raises(ExampleError, match=message):
        render_reading(_reading(**over))


def _mini_course(tmp_path, term: dict, kind: str = "measures") -> list[str]:
    (tmp_path / "terms").mkdir()
    course = {"id": "t", "title": "T", "tiers": [{"id": "core", "title": "Core", "blurb": "b", "lessons": [
        {"id": "l1", "title": "L", "blurb": "b", "kind": kind}]}]}
    (tmp_path / "course.yaml").write_text(yaml.safe_dump(course), encoding="utf-8")
    base = {"id": "auc", "term": "AUC", "short": "Area under a curve.", "plain": "Ranks.", "fools_you": "Not calibration.",
            "used_for": "Comparing models.", "in_finance": "Credit teams call it Gini."}
    base.update(term)
    (tmp_path / "terms" / "l1.yaml").write_text(yaml.safe_dump([base]), encoding="utf-8")
    sources = {"src": {"status": "VERIFIED"}, "weak": {"status": "UNVERIFIED"}}
    return validate_course(tmp_path, sources, {}, complete=False)[2]


def test_measures_cards_need_used_for_and_in_finance(tmp_path):
    errs = _mini_course(tmp_path, {"used_for": None, "in_finance": None})
    assert any("need used_for" in e for e in errs) and any("need in_finance" in e for e in errs)


def test_finance_cards_do_not_need_them(tmp_path):
    assert _mini_course(tmp_path, {"used_for": None, "in_finance": None}, kind="finance") == []


def test_reading_texts_and_sources_are_checked(tmp_path):
    reading = _reading(bands_source="weak").model_dump()
    reading["misreadings"][2] = "Wrong 3 times in {pct}."
    errs = _mini_course(tmp_path, {"reading": reading, "in_finance": "Gini is {gini}."})
    assert any("hand-typed number" in e and "reading text" in e for e in errs)
    assert any("'weak' is not VERIFIED" in e for e in errs)
    assert any("in_finance" in e and "has no value" in e for e in errs)


def test_owner_named_measures_are_in_core(course):
    """ROC AUC, PCA, KS, EDA and R² by name, plus the P50 evaluation words, all in Core (ranks 101-130)."""
    _, ordered, _ = course
    where = {n.lower(): (tr.id, ls.kind) for tr, ls, t in ordered for n in [t.term, *t.aliases]}
    for name in ["ROC AUC", "PCA", "KS", "EDA", "R²", "base rate", "Brier score", "calibration",
                 "decision threshold", "hit rate", "p-value", "confidence interval", "RMSE", "PSI", "Gini"]:
        assert where[name.lower()] == ("core", "measures"), name
    rank = {t.id: i + 1 for i, (_, _, t) in enumerate(ordered)}
    assert rank["base_rate"] == 101 and rank["population_stability_index"] == 130


def test_measures_cards_explain_reading_and_finance(course):
    _, ordered, _ = course
    measures = [t for _, ls, t in ordered if ls.kind == "measures"]
    assert len(measures) == 40
    assert all(t.used_for and t.in_finance for t in measures)
    assert sum(1 for t in measures if t.reading) >= 20
    auc = next(t for t in measures if t.id == "roc_auc")
    j = term_json(auc, None)
    assert j["reading"]["point"] == {"at": 0.78, "text": "0.78"}
    assert "[[0.56]]" in j["in_finance"], "Gini = 2 x AUC - 1, computed, not typed"
    assert j["reading"]["bands_source"] == "casrai_auc_bands"


def test_aliases_moved_with_their_meaning(course):
    _, ordered, _ = course
    owner = {n.lower(): t.id for _, _, t in ordered for n in [t.term, *t.aliases]}
    assert owner["pca"] == "pca" and owner["level slope curvature"] == "yield_curve_pca"
    assert owner["multiple testing"] == "multiple_testing" and owner["p-hacking"] == "data_snooping"


def test_methods_lesson_explains_the_case_methods(course):
    """Owner 2026-11-16: 'i never heard of the holm method'. Each method a case relies on has its own card."""
    _, ordered, _ = course
    by_id = {t.id: (ls, t) for _, ls, t in ordered}
    for tid in ["holm_correction", "difference_in_differences", "natural_experiment", "confounder", "poisson_model",
                "rate_ratio", "interaction_term", "clustered_standard_errors", "fixed_effects", "censoring"]:
        ls, t = by_id[tid]
        assert ls.id == "core_14_methods" and ls.kind == "measures", tid
        assert t.used_for and t.in_finance and t.sources, tid
    names = {n.lower(): t.id for _, _, t in ordered for n in [t.term, *t.aliases]}
    assert names["holm"] == "holm_correction" and names["holm-adjusted"] == "holm_correction"
    assert names["bonferroni"] == "multiple_testing"
