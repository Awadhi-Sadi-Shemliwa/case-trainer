# Grading (the examiner) — spec §5

Status: design only; implemented in Prompt 6, calibrated in Prompt 7.

## Rules that never change
- Deterministic and offline. No LLM decides pass/fail or touches numbers (LLMs may only rephrase feedback).
- **Pass = total ≥ 85 and no critical red flag.**
- 3 attempts:
  1. score + names of missing rubric areas (no answers) + the step's explanation template + `analysis_pointer`
  2. `hint` for each missing point + `feedback` for each red flag triggered + `redo_step`
  3. model answer with each rubric point highlighted and linked to `evidence`, plus `why`; schedule
     spaced re-test at 1, 3, 7, 21 days
- Every attempt, score and hint is stored in progress.sqlite.

## Scoring algorithm
1. Split the answer into sentences. Embed each sentence and each paraphrase (all-MiniLM-L6-v2, 384-dim).
2. Semantic score per point = max cosine over (sentence, paraphrase), mapped to 0–1 with a logistic
   curve **fitted on calibration data** (never raw cosine thresholds).
3. Keyword score per point = fraction of concept groups present (lower-cased, lemmatised, synonyms).
4. Coverage = 0.6 × semantic + 0.4 × keyword (weights tuned during calibration).
5. Numeric anchor: extract numbers from the answer; credit only if within tolerance of the pipeline value.
6. Red flags: matched above a calibrated threshold → subtract penalty. Negation check ("it is *not*
   causal") prevents false triggers.
7. Total = Σ(weight × coverage) − penalties, clipped to 0–100.

## Calibration (required before a case ships)
- 30–50 labelled answers per graded step (strong / partial / wrong / red-flag); owner reviews those
  marked `owner_review: true`.
- Fit curves, tune weights: acceptable answers ≥ 85, false-pass rate < 5%. Report Cohen's κ.
- The Python and Dart graders must agree within a small tolerance (test in Prompt 7).
