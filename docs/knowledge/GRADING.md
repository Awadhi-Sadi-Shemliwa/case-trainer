# Grading (the examiner)

Status (2026-11-16): **live**, Claude examiner. Owner decision: "i want the examiner to be there like instantly and
grade me effectively with accuracy and pin point areas i got wrong in explaining". This replaces the planned offline
MiniLM grader (spec §5, Prompt 6/7); the rule "no LLM decides pass/fail" is overridden by the owner, see DECISIONS.

## Who decides what
| Part | Who | Where |
|---|---|---|
| Coverage of each rubric point (full / partial / none), quotes of wrong sentences, red flags asserted, "no attempt" | Claude (`claude-opus-5-5`, effort medium, structured JSON output) | `app/lib/grading/claude_grader.dart` |
| Score = sum of weight x coverage minus red-flag penalties, clipped 0-100 | app | `grading/score.dart` |
| Numeric anchor: a point with `numeric` keeps full credit only if the answer has the pipeline number within tolerance (else capped at partial) | app | `score.dart` |
| Pass = score >= 85 and no critical red flag | app | `score.dart` |
| "I don't know" / near-empty answers | app, no API call | `grading/no_attempt.dart` |

Claude sees the step, the model answer, the rubric (labels, weights, paraphrases, why), the red flags, every
pipeline number the step uses (placeholders resolved), a text description of the chart, and the answer. Unknown point
or flag ids it returns are ignored.

## Attempt ladder (3 tries)
1. score, every rubric point with what is missing, every wrong sentence quoted with the problem and a better
   version, strengths, `analysis_pointer`
2. plus a `hint` per missing point, red-flag feedback, `redo_step`
3. (or a pass) plus the model answer and each point's `why`; the step joins the 1/3/7/21-day review ladder

"I don't know" counts as a try on the same ladder: pointer + first hint, then every hint, then the model answer.
If the examiner cannot be reached (offline, no key, no credit, rate limit) the answer is kept as a draft and the try
is NOT used up; "Grade now" retries. Answers saved before 2026-11-16 were never graded and do not count as tries.

## Storage
progress.sqlite v3 `examiner_feedback` (one row per counted try: status, score, passed, the full verdict JSON, model,
tokens). The finish rule (`engine/step_status.dart`) counts a written step as answered once passed or after three tries.

## Cost
About 3-6k input and 1-2k output tokens per grade on Opus 5.5 ($4 / $20 per million): roughly 2-6 US cents each.
