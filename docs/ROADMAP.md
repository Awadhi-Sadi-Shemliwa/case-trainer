# Roadmap

Prompts come from docs/spec.pdf §10. Status: TODO / IN PROGRESS / DONE / BLOCKED (with reason).

| # | Prompt | Status | Notes |
|---|--------|--------|-------|
| 1 | Read spec, plan, set up repo | DONE (pending S21 run by owner) | arm64 debug APK builds; pytest + flutter test pass |
| 2 | Pipeline framework (provenance, results, charts, content build) | DONE | 28 tests; build fails on missing keys, weights≠100, unverified sources, missing calibration, hand-typed numbers |
| 3 | Solve P50 yield curve end to end | DONE (awaiting owner review) | 25 steps, 94 results, 9 graded steps × 32 calibration answers (45 flagged for owner). NY Fed benchmark NOT obtained — see docs/knowledge/cases/p50_yield_curve.md |
| 4 | Flutter app shell and case player | TODO | |
| 5 | Interactive charts (Syncfusion + fl_chart fallback) | TODO | Owner registers Syncfusion Community Licence |
| 6 | Examiner: grading engine, 3 attempts, 85% | TODO | flutter_onnxruntime + MiniLM; verify 16 KB pages |
| 7 | Calibrate and test the grader | TODO | Owner labels calibration answers |
| 8 | Remaining Tier A cases in batches | TODO | Portfolio order: P34, P3, P13, P1, then spec §8 order |
| 9 | Learn tab, spaced review, progress, portfolio export | TODO | |
| 10 | Optional AI feedback + release build | TODO | flutter_gemma discontinued -> flutter_edge_ai |

## Portfolio goal (owner): 5 projects by end of 2026
P50 (Finance) · P34 (Football) · P3 (Aviation) · P13 (F1) · P1 (Aviation).

## Additions agreed with owner (beyond spec)
"Challenge mode" step types in every case: `data_expectation`, `cleaning_justification`,
`plan_challenge`, `decision_threshold`. See docs/knowledge/CONTENT_SCHEMA.md.
