"""Finance Foundations: the ranked glossary course (owner request 2026-11-15).

Layout (pipeline/learn/finance/):
    course.yaml                   tiers -> lessons (order = rank order), allowed_literals, read-next books
    terms/<lesson_id>.yaml        the ten words of one lesson, in rank order

Rules (same spirit as the cases, adapted to teaching content; see docs/knowledge/DECISIONS.md 2026-11-15):
  * Definitions are written fresh in plain English (the repo is public; nothing is copied from books).
  * Prose fields contain no hand-typed digits (allowed_literals such as "S&P 500" excepted).
  * Worked examples use made-up numbers that are COMPUTED here from `values` + `compute` with a whitelisted
    arithmetic evaluator, so an example can never contain an arithmetic slip; pytest re-checks every one.
  * Formulas are matplotlib mathtext, rendered to transparent PNGs the app tints to its theme.
  * Every source shown (pages definitions were checked against, books to read next) is VERIFIED in sources.json.
"""

from __future__ import annotations

import ast
import json
import math
import re
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
PLACEHOLDER_RE = re.compile(r"\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
TIERS_EXPECTED = 3
LESSONS_PER_TIER = 10
TERMS_PER_LESSON = 10
MAX_SHORT_WORDS = 30


# --------------------------------------------------------------------------- schema
class _Strict(BaseModel):
    # A YAML slip (e.g. a comma inside a {flow: mapping}) must fail, not silently drop text.
    model_config = ConfigDict(extra="forbid")


class Symbol(_Strict):
    symbol: str
    means: str


class Formula(_Strict):
    tex: str                        # matplotlib mathtext body (no surrounding $)
    plain: str                      # readable text version (screen readers, fallback)
    symbols: list[Symbol] = Field(min_length=1)


class Example(_Strict):
    """A worked example with made-up numbers. Every number shown is a value or a computed result."""

    values: dict[str, float]
    compute: dict[str, str]                     # evaluated in order; may use values and earlier results
    formats: dict[str, str] = Field(default_factory=dict)   # name -> format string such as "£{:,.0f}" or "{:.1%}"
    text: str                                   # uses {name} placeholders

    @field_validator("values", "compute")
    @classmethod
    def _names(cls, v: dict) -> dict:
        for k in v:
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
                raise ValueError(f"bad example name {k!r}")
        return v


class CaseRef(_Strict):
    case: str
    step: str


class Term(_Strict):
    id: str
    term: str
    aliases: list[str] = Field(default_factory=list)
    short: str                      # one sentence; the quick-check question is built from it
    plain: str                      # plain meaning with an everyday picture
    formula: Formula | None = None
    example: Example | None = None
    fools_you: str                  # how it fools people (spec's glossary card)
    related: list[str] = Field(default_factory=list)
    in_cases: list[CaseRef] = Field(default_factory=list)
    sources: list[str] = Field(default_factory=list)

    @field_validator("id")
    @classmethod
    def _id(cls, v: str) -> str:
        if not ID_RE.match(v):
            raise ValueError(f"term id {v!r} must be lower_snake_case")
        return v

    @model_validator(mode="after")
    def _short(self):
        if len(self.short.split()) > MAX_SHORT_WORDS:
            raise ValueError(f"{self.id}: short definition over {MAX_SHORT_WORDS} words")
        return self


class Lesson(_Strict):
    id: str
    title: str
    blurb: str
    sources: list[str] = Field(default_factory=list)   # pages the definitions were checked against


class Tier(_Strict):
    id: str
    title: str
    blurb: str
    read_next: list[str] = Field(default_factory=list)  # books (source keys)
    lessons: list[Lesson]


class Course(_Strict):
    id: str
    title: str
    allowed_literals: list[str] = Field(default_factory=list)
    tiers: list[Tier]


# --------------------------------------------------------------------------- safe arithmetic
_FUNCS = {"sqrt": math.sqrt, "log": math.log, "exp": math.exp, "abs": abs, "min": min, "max": max}
_BIN = {ast.Add: lambda a, b: a + b, ast.Sub: lambda a, b: a - b, ast.Mult: lambda a, b: a * b,
        ast.Div: lambda a, b: a / b, ast.Pow: lambda a, b: a ** b}


class ExampleError(ValueError):
    pass


def safe_eval(expr: str, env: dict[str, float]) -> float:
    """Evaluates + - * / ** ( ), unary minus, names from env and sqrt/log/exp/abs/min/max. Nothing else."""

    def ev(n: ast.AST) -> float:
        if isinstance(n, ast.Expression):
            return ev(n.body)
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)) and not isinstance(n.value, bool):
            return float(n.value)
        if isinstance(n, ast.Name):
            if n.id not in env:
                raise ExampleError(f"unknown name {n.id!r} in {expr!r}")
            return float(env[n.id])
        if isinstance(n, ast.BinOp) and type(n.op) in _BIN:
            return _BIN[type(n.op)](ev(n.left), ev(n.right))
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, (ast.USub, ast.UAdd)):
            v = ev(n.operand)
            return -v if isinstance(n.op, ast.USub) else v
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in _FUNCS
                and not n.keywords):
            return float(_FUNCS[n.func.id](*[ev(a) for a in n.args]))
        raise ExampleError(f"not allowed in example arithmetic: {ast.dump(n)[:80]} in {expr!r}")

    try:
        tree = ast.parse(expr, mode="eval")
    except SyntaxError as e:
        raise ExampleError(f"cannot parse {expr!r}: {e}") from e
    out = ev(tree)
    if not math.isfinite(out):
        raise ExampleError(f"{expr!r} is not finite")
    return out


def _fmt(value: float, spec: str | None) -> str:
    if spec is None:
        spec = "{:,.0f}" if float(value).is_integer() else "{:,.2f}"
    return spec.format(value)


def render_example(ex: Example) -> tuple[str, dict[str, float]]:
    """Returns the text with every number wrapped as [[number]] (the app highlights these) and all values."""
    env: dict[str, float] = dict(ex.values)
    for name, expr in ex.compute.items():
        if name in env:
            raise ExampleError(f"{name!r} computed twice")
        env[name] = safe_eval(expr, env)
    for name in ex.formats:
        if name not in env:
            raise ExampleError(f"format given for unknown name {name!r}")

    def sub(m: re.Match) -> str:
        name = m.group(1)
        if name not in env:
            raise ExampleError(f"placeholder {{{name}}} has no value")
        return f"[[{_fmt(env[name], ex.formats.get(name))}]]"

    return PLACEHOLDER_RE.sub(sub, ex.text), env


# --------------------------------------------------------------------------- formulas
def render_formula(tex: str, out_png: Path) -> None:
    """Black glyphs on a transparent background at 3x (the app tints them and shows them at scale 3)."""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib.figure import Figure

    with matplotlib.rc_context({"mathtext.fontset": "stixsans", "font.family": "sans-serif"}):
        fig = Figure(figsize=(0.01, 0.01))
        fig.text(0, 0, f"${tex}$", fontsize=21, color="black")
        out_png.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out_png, dpi=300, transparent=True, bbox_inches="tight", pad_inches=0.05,
                    metadata={"Software": None})


def check_formula(tex: str) -> str | None:
    """None if matplotlib can lay the formula out, else the parse error."""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib.mathtext import MathTextParser

    try:
        with matplotlib.rc_context({"mathtext.fontset": "stixsans"}):
            MathTextParser("path").parse(f"${tex}$", dpi=72)
    except (ValueError, RuntimeError) as e:
        return str(e).splitlines()[0]
    return None


# --------------------------------------------------------------------------- loading + validation
def _digits(text: str, allowed: list[str]) -> list[str]:
    t = text
    for lit in sorted(allowed, key=len, reverse=True):
        t = re.sub(re.escape(lit), " ", t, flags=re.IGNORECASE)
    return re.findall(r"\S*\d\S*", t)


def _word_re(phrase: str) -> re.Pattern:
    return re.compile(r"(?<![A-Za-z0-9])" + re.escape(phrase) + r"(?![A-Za-z0-9])", re.IGNORECASE)


def load_course(course_dir: Path, complete: bool = True) -> tuple[Course | None, dict[str, list[Term]], list[str]]:
    """Parses course.yaml and every lesson file. Returns (course, terms by lesson id, schema errors).
    complete=False tolerates lesson files that do not exist yet (work in progress)."""
    errs: list[str] = []
    try:
        course = Course.model_validate(yaml.safe_load((course_dir / "course.yaml").read_text(encoding="utf-8")))
    except (ValidationError, yaml.YAMLError, FileNotFoundError) as e:
        return None, {}, [f"course.yaml invalid: {e}"]
    terms: dict[str, list[Term]] = {}
    for tier in course.tiers:
        for lesson in tier.lessons:
            f = course_dir / "terms" / f"{lesson.id}.yaml"
            if not f.exists():
                if complete:
                    errs.append(f"lesson {lesson.id}: file terms/{lesson.id}.yaml missing")
                continue
            try:
                raw = yaml.safe_load(f.read_text(encoding="utf-8")) or []
                terms[lesson.id] = [Term.model_validate(t) for t in raw]
            except (ValidationError, yaml.YAMLError) as e:
                errs.append(f"terms/{lesson.id}.yaml invalid: {e}")
    return course, terms, errs


def validate_course(course_dir: Path, sources: dict[str, dict], case_steps: dict[str, set[str]],
                    complete: bool = True) -> tuple[Course | None, list[tuple[Tier, Lesson, Term]], list[str]]:
    """Every check the bundle relies on. `complete=False` skips the 3 x 10 x 10 shape (for work in progress).

    Returns (course, ordered [(tier, lesson, term)], errors). Order = rank 1..N.
    """
    course, by_lesson, errs = load_course(course_dir, complete)
    if course is None:
        return None, [], errs
    ordered: list[tuple[Tier, Lesson, Term]] = []
    for tier in course.tiers:
        for lesson in tier.lessons:
            for t in by_lesson.get(lesson.id, []):
                ordered.append((tier, lesson, t))

    def need_source(key: str, where: str) -> None:
        if key not in sources:
            errs.append(f"{where}: source {key!r} not in sources.json")
        elif sources[key]["status"] != "VERIFIED":
            errs.append(f"{where}: source {key!r} is not VERIFIED")

    # shape
    ids = [x.id for x in course.tiers] + [ls.id for tr in course.tiers for ls in tr.lessons]
    if len(ids) != len(set(ids)):
        errs.append("tier/lesson ids must be unique")
    if complete:
        if len(course.tiers) != TIERS_EXPECTED:
            errs.append(f"{len(course.tiers)} tiers, expected {TIERS_EXPECTED}")
        for tier in course.tiers:
            if len(tier.lessons) != LESSONS_PER_TIER:
                errs.append(f"tier {tier.id}: {len(tier.lessons)} lessons, expected {LESSONS_PER_TIER}")
            for lesson in tier.lessons:
                n = len(by_lesson.get(lesson.id, []))
                if n != TERMS_PER_LESSON:
                    errs.append(f"lesson {lesson.id}: {n} words, expected {TERMS_PER_LESSON}")
    for tier in course.tiers:
        for k in tier.read_next:
            need_source(k, f"tier {tier.id} read_next")
        for lesson in tier.lessons:
            for k in lesson.sources:
                need_source(k, f"lesson {lesson.id}")

    # ids, names, aliases
    all_terms = [t for _, _, t in ordered]
    term_ids = [t.id for t in all_terms]
    dup = {i for i in term_ids if term_ids.count(i) > 1}
    if dup:
        errs.append(f"duplicate term ids {sorted(dup)}")
    known = set(term_ids)
    names: dict[str, str] = {}
    for t in all_terms:
        for n in [t.term, *t.aliases]:
            k = n.strip().lower()
            if k in names and names[k] != t.id:
                errs.append(f"{t.id}: name/alias {n!r} already used by {names[k]}")
            names[k] = t.id

    lit = course.allowed_literals
    for tier, lesson, t in ordered:
        where = f"{lesson.id}/{t.id}"
        for field in ("term", "short", "plain", "fools_you"):
            bad = _digits(getattr(t, field), lit)
            if bad:
                errs.append(f"{where}.{field}: hand-typed number(s) {bad} (use an example or allowed_literals)")
        for alias in t.aliases:
            if _digits(alias, lit):
                errs.append(f"{where}: alias {alias!r} contains digits not in allowed_literals")
        # The quick check asks "which word means <short>?": the short text must not give the word away.
        for n in [t.term, *t.aliases]:
            if _word_re(n).search(t.short):
                errs.append(f"{where}: short definition contains its own word {n!r}")
        for r in t.related:
            if r not in known:
                errs.append(f"{where}: related {r!r} is not a term")
            if r == t.id:
                errs.append(f"{where}: related to itself")
        for ref in t.in_cases:
            if ref.case not in case_steps:
                errs.append(f"{where}: in_cases case {ref.case!r} unknown")
            elif ref.step not in case_steps[ref.case]:
                errs.append(f"{where}: in_cases step {ref.case}/{ref.step} unknown")
        for k in t.sources:
            need_source(k, where)
        if t.formula is not None:
            msg = check_formula(t.formula.tex)
            if msg:
                errs.append(f"{where}: formula does not render: {msg}")
        if t.example is not None:
            try:
                text, _ = render_example(t.example)
                bad = _digits(re.sub(r"\[\[.*?\]\]", " ", text), lit)
                if bad:
                    errs.append(f"{where}: example text has hand-typed number(s) {bad}; put them in values")
            except ExampleError as e:
                errs.append(f"{where}: example: {e}")
    return course, ordered, errs


# --------------------------------------------------------------------------- bundle
COURSE_DDL = """
CREATE TABLE course(id TEXT PRIMARY KEY, title TEXT, json TEXT NOT NULL);
CREATE TABLE tiers(id TEXT PRIMARY KEY, course TEXT, ord INTEGER, title TEXT, json TEXT NOT NULL);
CREATE TABLE lessons(id TEXT PRIMARY KEY, tier TEXT, ord INTEGER, title TEXT, json TEXT NOT NULL);
CREATE TABLE terms(id TEXT PRIMARY KEY, tier TEXT, lesson TEXT, rank INTEGER, term TEXT, json TEXT NOT NULL);
"""


def term_json(t: Term, formula_asset: str | None) -> dict[str, Any]:
    d = t.model_dump(exclude={"formula", "example"})
    d["formula"] = None if t.formula is None else {
        "plain": t.formula.plain,
        "symbols": [s.model_dump() for s in t.formula.symbols],
        "image": formula_asset,
    }
    d["example"] = None if t.example is None else {"text": render_example(t.example)[0]}
    return d


def write_course(con, course: Course, ordered: list[tuple[Tier, Lesson, Term]], out_dir: Path) -> None:
    con.executescript(COURSE_DDL)
    con.execute("INSERT INTO course VALUES(?,?,?)", (course.id, course.title, json.dumps(
        {"id": course.id, "title": course.title, "allowed_literals": course.allowed_literals})))
    for i, tier in enumerate(course.tiers):
        con.execute("INSERT INTO tiers VALUES(?,?,?,?,?)", (tier.id, course.id, i, tier.title, json.dumps(
            {"id": tier.id, "title": tier.title, "blurb": tier.blurb, "read_next": tier.read_next})))
        for j, lesson in enumerate(tier.lessons):
            con.execute("INSERT INTO lessons VALUES(?,?,?,?,?)", (lesson.id, tier.id, j, lesson.title,
                                                                  json.dumps(lesson.model_dump())))
    for rank, (tier, lesson, t) in enumerate(ordered, start=1):
        asset = None
        if t.formula is not None:
            asset = f"formulas/{t.id}.png"
            render_formula(t.formula.tex, out_dir / asset)
        con.execute("INSERT INTO terms VALUES(?,?,?,?,?,?)",
                    (t.id, tier.id, lesson.id, rank, t.term, json.dumps(term_json(t, asset))))
