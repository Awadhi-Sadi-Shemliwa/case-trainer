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
| UI | `ui/screens/*`, `ui/steps/*`, `ui/widgets/*` | One widget family per step type (`step_view.dart` dispatches). Checked steps reveal the answer after 3 failed attempts. Chart steps use `InteractiveChart` (Charts layer below); the PNG is only the fallback |
| Drafts (2026-11-15) | `ui/steps/draft_saver.dart` | Every step keeps unsubmitted input in `progress.drafts` (saved 300 ms after an edit, on dispose and on app pause) |
| Code beside steps | `ui/widgets/code_context.dart` | `context_snippets` render under the prompt of any step, plus a "Show the code" sheet next to written answers |
| Learn (2026-11-15) | `learn/*` | `course.dart` (tiers, lessons, 300 words; `CourseProgress` unlock rules), `quiz.dart` (deterministic questions), `quiz_runner.dart`, `lesson_screen.dart` (+ review), `learn_screen.dart` (+ word search), `term_card.dart` (word card, sheet, page), `term_linker.dart` (finance words in case text) |
| Theme (2026-11-15) | `ui/theme/{tokens,typography,app_theme}.dart` | `CaseColors` ThemeExtension (paper, ink, highlighter, sector series), Archivo / JetBrains Mono, Material 3 component themes |
| Cover | `ui/screens/cover_screen.dart`, `ui/widgets/real_curves.dart` | Initial route `/cover` (Settings toggle); four signature curves from chart JSON; Continue resumes the last case |

Data flow for one step: `content_db.steps()` → `StepView` → `Prose` resolves placeholders → user answers →
`Checker` / `Grader` → `progress_db.recordAttempt()` → `progressTickProvider.bump()` → Home/Progress rebuild.

Guard test: `app/test/no_hardcoded_numbers_test.dart` renders every step of the REAL bundle and fails on any
digit outside value chips, code blocks and allowed literals (mutation-checked: an injected "13.5" fails it).

## Charts layer (`app/lib/charts/`, Prompt 5)
`chart_spec.dart` strictly parses the pipeline chart JSON (schema v1) and throws `ChartParseError` on anything
unexpected. `chart_view.dart`: `InteractiveChart(id)` loads `assets/content/charts/<id>.json`. On a load or parse
error it falls back to the PNG and logs `[CaseTrainer] chart <id> fallback to PNG: …`. `ChartPanel` holds the title, Reset view,
Full screen, the chart, a gesture hint and the source note. `cartesian_builder.dart` maps to Syncfusion: line, scatter + fitted
line, bar, stacked bar, histogram (columns at bin centres), box (Hilo whiskers + range column + median marker),
shaded regions → PlotBands, reference lines → zero-width PlotBands, annotations; the tooltip shows the unit.
`heatmap_view.dart` draws a custom grid. `FullScreenChart` locks to landscape and restores the default on close.
Test fixtures for every type live only in `app/test/chart_fixtures.dart`.

## Content bundle v2 and progress v2 (2026-11-15)
content.sqlite adds `course`, `tiers`, `lessons`, `terms` (JSON per word, rank 1..300) and `formulas/*.png`; cases
may carry `signature_chart`, steps may carry `context_snippets`. progress.sqlite (user_version 2) adds `drafts`,
`term_progress` (known, ladder rung, due date) and `lesson_progress` (best score, attempts, passed).

Design review without a phone: `SCREENSHOT_DIR=<folder> flutter test test_screens/screenshots_test.dart` renders the
main screens with the real fonts to PNG.

## Build-time guarantees (build_content.py fails if…)
- a `{expected.key}` placeholder is missing from expected_results.json
- a source key is missing from sources.json or not VERIFIED
- a chart file is missing
- rubric weights ≠ 100
- a graded step has no calibration set
- authored text contains a hand-typed number (digits outside placeholders; small whitelist)
- a context snippet would reveal the answer of a later code_fill / code_fix step
- the finance course is not 3 × 10 × 10, a short definition contains its own word, a related word or in_cases step
  does not exist, an example does not compute, a formula does not render, or a source is not VERIFIED
