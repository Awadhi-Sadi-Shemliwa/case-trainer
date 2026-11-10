# Roadmap

Prompts come from docs/spec.pdf §10. Status: TODO / IN PROGRESS / DONE / BLOCKED (with reason).

| # | Prompt | Status | Notes |
|---|--------|--------|-------|
| 1 | Read spec, plan, set up repo | DONE | arm64 debug APK builds; pytest + flutter test pass |
| 2 | Pipeline framework (provenance, results, charts, content build) | DONE | 28 tests; build fails on missing keys, weights≠100, unverified sources, missing calibration, hand-typed numbers |
| 3 | Solve P50 yield curve end to end | DONE (awaiting owner review) | 25 steps, 120 results, 9 graded steps, 290 calibration answers (49 flagged for owner review; counts as of the 2026-11-10 cross-check, flagged count enforced by `tests/test_crosscheck.py`). NY Fed benchmark NOT obtained — see docs/knowledge/cases/p50_yield_curve.md |
| 4 | Flutter app shell and case player | DONE | Plays P50 on the S21+ to the first chart and beyond; resume verified after app kill; release cold start median 309 ms; 14 Flutter tests incl. no-hard-coded-numbers |
| 5 | Interactive charts (Syncfusion; PNG fallback) | DONE | Pinch/pan, unit tooltips, legend toggle, reset, landscape full screen verified on S21+. Pinch-zoom misses ~12% of 60 Hz build frames (median of 9 measured runs), raster 0 missed. No licence key needed in 35.x; fl_chart not added (DECISIONS) |
| 6 | Examiner: grading engine, 3 attempts, 85% | TODO | flutter_onnxruntime + MiniLM; verify 16 KB pages |
| 7 | Calibrate and test the grader | TODO | Owner labels calibration answers |
| 8 | Remaining Tier A cases in batches | IN PROGRESS | Batch 1: **P34 DONE** (quality-gated, fixed), **P3 DONE** (quality-gated, fixed); P50 also re-gated and fixed, **P13 UNBLOCKED, not built yet**: FastF1 3.9 needs an active F1TV subscription (confirmed again 2026-11-10 in its source), but the free OpenF1 API (CC BY-NC-SA 4.0, no login) has lap times, stints, compounds, tyre age and race control, so P13 moves to OpenF1 with the original tyre question intact. Next: P1, then spec §8 order |
| 9 | Learn tab, spaced review, progress, portfolio export | TODO | |
| 10 | Optional AI feedback + release build | TODO | flutter_gemma discontinued -> flutter_edge_ai |

## Portfolio goal (owner): 5 projects by end of 2026
P50 (Finance) · P34 (Football) · P3 (Aviation) · P13 (F1) · P1 (Aviation).

## Additions agreed with owner (beyond spec)
"Challenge mode" step types in every case: `data_expectation`, `cleaning_justification`,
`plan_challenge`, `decision_threshold`. See docs/knowledge/CONTENT_SCHEMA.md.
