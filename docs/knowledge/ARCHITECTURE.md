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

## App layers (`app/lib/`, Prompt 4)
| Layer | Files | Notes |
|---|---|---|
| Entry | `main.dart`, `app.dart` | Opens both DBs before `runApp`; injects them with Riverpod overrides; go_router shell with 4 tabs + `/case/:id` |
| State | `providers.dart` | `contentDbProvider`, `progressDbProvider`, `graderProvider`; `progressTickProvider` bumped after every progress write; `themeModeProvider` (stored in progress settings) |
| Data | `data/content_db.dart` | Copies `assets/content/content.sqlite` to app support dir when missing or different (byte compare), opens **read-only** |
| | `data/progress_db.dart` | `attempts`, `case_state` (resume: `step_idx`, `max_idx`, `completed`), `reviews` (Prompts 6/9), `settings`; schema via `PRAGMA user_version` |
| Engine | `engine/placeholders.dart` | `{expected.k}` → `results.display` (ValueChip, tap shows description); `{captured.n}` → code block; unknown key **throws** |
| | `engine/checker.dart` | Exact checks for mcq / multi / kpi / order / numeric (tolerance, % aware) / code_fill / code_fix (whitespace-insensitive) |
| Grading | `grading/grader.dart` | `Grader` interface; `StubGrader` until Prompt 6. While the stub is active, free-text steps offer the model answer after submit |
| UI | `ui/screens/*`, `ui/steps/*`, `ui/widgets/*` | One widget family per step type (`step_view.dart` dispatches). Checked steps reveal the answer after 3 failed attempts. Charts are pipeline PNGs (pinch-zoom, full screen) until Prompt 5 |

Data flow for one step: `content_db.steps()` → `StepView` → `Prose` resolves placeholders → user answers →
`Checker` / `Grader` → `progress_db.recordAttempt()` → `progressTickProvider.bump()` → Home/Progress rebuild.

Guard test: `app/test/no_hardcoded_numbers_test.dart` renders every step of the REAL bundle and fails on any
digit outside value chips, code blocks and allowed literals (mutation-checked: an injected "13.5" fails it).

## Build-time guarantees (build_content.py fails if…)
- a `{expected.key}` placeholder is missing from expected_results.json
- a source key is missing from sources.json or not VERIFIED
- a chart file is missing
- rubric weights ≠ 100
- a graded step has no calibration set
- authored text contains a hand-typed number (digits outside placeholders; small whitelist)
