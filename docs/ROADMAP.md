# Roadmap

> **NEXT TASK (owner, 2026-11-16):** "Building new real data for all the 4 groups such that once one problem is finished another pops up, as i said dont worry about the size of app make sure we achieve the target of me being the best data scientist"

Prompts come from docs/spec.pdf §10. Status: TODO / IN PROGRESS / DONE / BLOCKED (with reason).

| # | Prompt | Status | Notes |
|---|--------|--------|-------|
| 1 | Read spec, plan, set up repo | DONE | arm64 debug APK builds; pytest + flutter test pass |
| 2 | Pipeline framework (provenance, results, charts, content build) | DONE | 28 tests; build fails on missing keys, weights≠100, unverified sources, missing calibration, hand-typed numbers |
| 3 | Solve P50 yield curve end to end | DONE (awaiting owner review) | 25 steps, 120 results, 9 graded steps, 290 calibration answers (49 flagged for owner review; counts as of the 2026-11-10 cross-check, flagged count enforced by `tests/test_crosscheck.py`). NY Fed benchmark NOT obtained — see docs/knowledge/cases/p50_yield_curve.md |
| 4 | Flutter app shell and case player | DONE | Plays P50 on the S21+ to the first chart and beyond; resume verified after app kill; release cold start median 309 ms; 14 Flutter tests incl. no-hard-coded-numbers |
| 5 | Interactive charts (Syncfusion; PNG fallback) | DONE | Pinch/pan, unit tooltips, legend toggle, reset, landscape full screen verified on S21+. Pinch-zoom misses ~12% of 60 Hz build frames (median of 9 measured runs), raster 0 missed. No licence key needed in 35.x; fl_chart not added (DECISIONS) |
| 6 | Examiner: grading engine, 3 attempts, 85% | DONE (2026-11-16, owner change) | Claude examiner (claude-sonnet-5-5, cached, retried) judges rubric coverage; app computes score/pass. MiniLM plan dropped. Verified live on the owner's real answer |
| 7 | Calibrate and test the grader | TODO | Run the calibration answers through the Claude examiner once the account has credit; report agreement |
| 8 | Remaining Tier A cases in batches | IN PROGRESS | Batch 1: **P34 DONE** (quality-gated, fixed), **P3 DONE** (quality-gated, fixed); P50 also re-gated and fixed, **P13 DONE** (quality-gated, fixed) on the free OpenF1 API (CC BY-NC-SA 4.0) because FastF1 needs F1TV; 61 dry races 2023-2025. Next: P1, then spec §8 order |
| 9 | Learn tab, spaced review, progress, portfolio export | IN PROGRESS | Finished-case PDF report (Downloads/CaseTrainer + share) and methods lesson DONE 2026-11-16 |
| 10 | Optional AI feedback + release build | TODO | flutter_gemma discontinued -> flutter_edge_ai |

## Portfolio goal (owner): 5 projects by end of 2026
P50 (Finance) · P34 (Football) · P3 (Aviation) · P13 (F1) · P1 (Aviation).

## Additions agreed with owner (beyond spec)
"Challenge mode" step types in every case: `data_expectation`, `cleaning_justification`,
`plan_challenge`, `decision_threshold`. See docs/knowledge/CONTENT_SCHEMA.md.

Owner requests of 2026-11-15 (branch `owner-learn-ui`, DONE in code and tests; not yet installed on the phone):
- Code beside every step that talks about it (`context_snippets`, all four cases, leak-guarded).
- Finance Foundations: ranked words in three tiers with lessons, quick checks, review and search; finance words
  linked inside P50. 2026-11-16: Core also holds the 30 data-science measures every case uses (330 words in all), each
  with "reading the number" (a value on its scale, the right reading and the classic misreadings) and an In finance
  part; measures are linked in all four cases. This is the glossary part of Prompt 9, pulled forward; spaced review of case steps and the
  portfolio export remain Prompt 9.
- Drafts: unsubmitted input survives Back, leaving a case and restarts.
- Redesign ("analyst's notebook") with a real-data cover, new app icon and splash.

Owner requests of 2026-11-16 (branch `owner-examiner`): instant Claude examiner with pinpointed errors; "I don't know"
-> hint ladder -> answer after three tries; Finish locked until every question is answered; methods lesson (Holm,
difference-in-differences, fixed effects, ...); finished-case PDF saved to Downloads/CaseTrainer and shareable;
one active problem per sector from the 50-problem catalog (football after P34: **P33 being prepared, build next**).
