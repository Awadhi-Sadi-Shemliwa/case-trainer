# Architecture

**Precompute on PC, examine on phone.** The phone never calculates a result, so it can never show
a made-up number, and it works offline on an older phone.

```
PC: pipeline/ (Python 3.13, uv)                          Phone: app/ (Flutter, Android arm64)
------------------------------------------               --------------------------------------
download.py  -> raw/ + provenance.json (SHA-256)          content.sqlite   read-only, copied from
clean.py     -> TransformLog (every drop + reason)                         assets on first run
analyse.py   -> expected_results.json (ResultStore)       charts/*.json    interactive charts
             -> charts/*.json + *.png  (charts.py, LTTB)  charts/*.png     fallback
content.yaml -> steps, rubrics, red flags, {expected.k}   progress.sqlite  attempts, scores,
test_case.py -> pytest asserts every result key                            hints, review schedule
calibration/ -> labelled answers for the grader           models/          MiniLM ONNX (Prompt 6)
build_content.py validates all of it ------------------>  app/assets/content/
```

## Case flow (spec §1) + Challenge mode (owner addition)
1 Brief → 2 Frame → **2b Predict the data (`data_expectation`)** → 3 Data (+ **`cleaning_justification`**)
→ 4 Explore → **`plan_challenge`** → 5 Model → 6 Decide (+ **`decision_threshold`**) → 7 Debrief.

## Examiner (spec §5)
Deterministic: sentence embeddings + keyword groups + numeric anchors − red-flag penalties.
Pass = score ≥ 85 and no critical red flag. 3 attempts with escalating feedback. LLMs may only
rephrase feedback, never grade. Details: GRADING.md.

## Build-time guarantees (build_content.py fails if…)
- a `{expected.key}` placeholder is missing from expected_results.json
- a source key is missing from sources.json or not VERIFIED
- a chart file is missing
- rubric weights ≠ 100
- a graded step has no calibration set
- authored text contains a hand-typed number (digits outside placeholders; small whitelist)
