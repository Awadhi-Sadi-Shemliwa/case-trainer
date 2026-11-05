"""Pydantic model of a case's content.yaml (spec §4 + §5, plus owner's Challenge-mode steps).

Numbers never appear in authored text: write {expected.<key>} and the app substitutes the
`display` string from expected_results.json at render time. build_content.py enforces this.
"""

from __future__ import annotations

import re
from typing import Literal

from pydantic import BaseModel, Field, model_validator

PLACEHOLDER_RE = re.compile(r"\{expected\.([a-z][a-z0-9_]*)\}")

Phase = Literal["brief", "frame", "predict", "data", "explore", "model", "decide", "debrief"]
PHASE_ORDER: list[str] = ["brief", "frame", "predict", "data", "explore", "model", "decide", "debrief"]

# Free-text steps graded by the examiner (rubric required, calibration set required).
GRADED_TYPES = {
    "free_text",
    "chart_explain",
    "result_explain",
    "memo",
    # Challenge mode (owner addition)
    "data_expectation",
    "cleaning_justification",
    "plan_challenge",
    "decision_threshold",
}
# Deterministically checked steps (exact answer, no rubric).
CHECKED_TYPES = {"mcq", "multi_select", "order_steps", "code_predict", "code_fill", "code_fix", "numeric", "kpi_builder"}
INFO_TYPES = {"code_read", "concept_card"}
StepType = Literal[
    "mcq", "multi_select", "order_steps", "code_read", "code_predict", "code_fill", "code_fix",
    "numeric", "kpi_builder", "concept_card", "free_text", "chart_explain", "result_explain", "memo",
    "data_expectation", "cleaning_justification", "plan_challenge", "decision_threshold",
]
# Explanation template shown as an optional guide (spec §5 'Explanation templates').
Scaffold = Literal["chart_6q", "cer", "memo", "predict_data", "justify_clean", "challenge_plan", "threshold", "none"]


class NumericAnchor(BaseModel):
    key: str
    tolerance: float
    tolerance_kind: Literal["abs", "rel"] = "abs"
    # Some results are fractions (0.25) that people write as percent (25%). Accept both.
    accept_percent: bool = False


class RubricPoint(BaseModel):
    id: str
    label: str                      # area name shown after attempt 1 (no answer content)
    weight: int = Field(gt=0)
    paraphrases: list[str] = Field(min_length=3, max_length=6)
    keywords: list[list[str]] = Field(min_length=1)   # concept groups; each group = synonyms
    numeric: NumericAnchor | None = None
    hint: str                       # attempt-2 targeted hint
    why: str                        # attempt-3 'why this point matters'
    evidence: str | None = None     # chart region / result key this point links to


class RedFlag(BaseModel):
    id: str
    critical: bool = False
    penalty: int = Field(ge=0, le=100)
    paraphrases: list[str] = Field(min_length=1)
    keywords: list[list[str]] = Field(default_factory=list)
    feedback: str


class Rubric(BaseModel):
    points: list[RubricPoint] = Field(min_length=4, max_length=7)
    red_flags: list[RedFlag] = Field(min_length=3, max_length=6)

    @model_validator(mode="after")
    def _ids_unique(self):
        ids = [p.id for p in self.points] + [r.id for r in self.red_flags]
        if len(ids) != len(set(ids)):
            raise ValueError("rubric point/red flag ids must be unique")
        return self


class Option(BaseModel):
    id: str
    text: str
    correct: bool = False
    explanation: str


class Blank(BaseModel):
    token: str          # exact text removed from the real snippet
    accept: list[str] = Field(default_factory=list)  # extra accepted spellings


class Snippet(BaseModel):
    file: str           # path relative to the case dir, e.g. clean.py
    name: str           # # >>> snippet: <name>


class Step(BaseModel):
    id: str
    phase: Phase
    type: StepType
    title: str
    prompt: str
    body: str | None = None             # context text / concept card text
    concepts: list[str] = Field(default_factory=list)

    # choice-style
    options: list[Option] | None = None
    items: list[str] | None = None      # order_steps: correct order
    # code
    snippet: Snippet | None = None
    output_name: str | None = None      # captured_outputs.json key for code_predict
    blanks: list[Blank] | None = None   # code_fill
    buggy_code: str | None = None       # code_fix: the snippet with ONE injected bug
    bug_explanation: str | None = None
    # numeric
    answer_key: str | None = None
    tolerance: float | None = None
    unit: str | None = None
    # graded free text
    chart: str | None = None            # chart id (charts/<id>.json)
    dataset: str | None = None          # data_expectation: provenance dataset key to reveal
    transform: str | None = None        # cleaning_justification: provenance transform id
    flawed_plan: str | None = None      # plan_challenge: the plan to attack
    scaffold: Scaffold = "none"
    rubric: Rubric | None = None
    model_answer: str | None = None
    analysis_pointer: str | None = None  # attempt-1 'one sentence on what analysis to look at'
    redo_step: str | None = None         # attempt-2 'the analysis step to redo'

    @model_validator(mode="after")
    def _by_type(self):
        t = self.type
        need = lambda *fields: [f for f in fields if getattr(self, f) in (None, [], "")]  # noqa: E731
        missing: list[str] = []
        if t in ("mcq", "multi_select", "kpi_builder"):
            missing = need("options")
            if self.options:
                n_correct = sum(o.correct for o in self.options)
                if t == "mcq" and n_correct != 1:
                    raise ValueError(f"{self.id}: mcq needs exactly one correct option")
                if t in ("multi_select", "kpi_builder") and n_correct < 1:
                    raise ValueError(f"{self.id}: needs at least one correct option")
        elif t == "order_steps":
            missing = need("items")
        elif t == "code_read":
            missing = need("snippet")
        elif t == "code_predict":
            missing = need("snippet", "output_name", "options")
        elif t == "code_fill":
            missing = need("snippet", "blanks")
        elif t == "code_fix":
            missing = need("snippet", "buggy_code", "bug_explanation")
        elif t == "numeric":
            missing = need("answer_key", "tolerance", "unit")
        elif t in GRADED_TYPES:
            missing = need("rubric", "model_answer", "analysis_pointer")
            if t == "chart_explain":
                missing += need("chart")
            if t == "data_expectation":
                missing += need("dataset")
            if t == "cleaning_justification":
                missing += need("transform")
            if t == "plan_challenge":
                missing += need("flawed_plan")
        if missing:
            raise ValueError(f"step {self.id} ({t}): missing {missing}")
        if self.rubric is not None:
            total = sum(p.weight for p in self.rubric.points)
            if total != 100:
                raise ValueError(f"step {self.id}: rubric weights sum to {total}, must be 100")
        return self


class Debrief(BaseModel):
    concepts_learned: list[str]
    common_mistakes: list[str]
    interview_summary: str          # 30-second summary (placeholders allowed)


class Case(BaseModel):
    id: str
    number: int
    domain: Literal["aviation", "f1", "football", "finance"]
    title: str
    tier: Literal["A", "A*"]
    decision_maker: str
    decision: str
    money_at_stake: str
    concepts: list[str]
    sources: list[str]
    datasets: list[str]
    allowed_literals: list[str] = Field(default_factory=list)   # e.g. "10-year", "2s10s"
    steps: list[Step]
    debrief: Debrief

    @model_validator(mode="after")
    def _steps(self):
        ids = [s.id for s in self.steps]
        if len(ids) != len(set(ids)):
            raise ValueError("step ids must be unique")
        # phases must appear in canonical order
        seen = [PHASE_ORDER.index(s.phase) for s in self.steps]
        if seen != sorted(seen):
            raise ValueError("steps must be ordered by phase (brief → … → debrief)")
        return self
