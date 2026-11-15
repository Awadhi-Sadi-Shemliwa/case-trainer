"""Finance Foundations course (owner request 2026-11-15): 300 ranked words, validated like the cases."""

from __future__ import annotations

import sqlite3

import pytest
import yaml

from build_content import CASES_DIR, LEARN_DIR, SOURCES_FILE, discover_cases, load_sources
from common.glossary import (
    Example,
    ExampleError,
    check_formula,
    render_example,
    safe_eval,
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


def test_course_shape_three_tiers_of_one_hundred(course):
    c, ordered, _ = course
    assert [t.id for t in c.tiers] == ["core", "intermediate", "quant"]
    assert len(ordered) == 300
    for tier in c.tiers:
        assert sum(1 for tr, _, _ in ordered if tr.id == tier.id) == 100
    assert len({t.id for _, _, t in ordered}) == 300


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
    assert con.execute("select count(*) from terms").fetchone()[0] == 300
    assert con.execute("select count(*) from lessons").fetchone()[0] == 30
    assert con.execute("select min(rank), max(rank) from terms").fetchone() == (1, 300)
    with_formula = [t for _, _, t in ordered if t.formula]
    assert len(list((tmp_path / "formulas").glob("*.png"))) == len(with_formula)
    png = (tmp_path / "formulas" / "equity.png").read_bytes()
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
