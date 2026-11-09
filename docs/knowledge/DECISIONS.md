# Decision log

Newest at the bottom. Each entry: date · decision · why · alternatives rejected.

### 2026-11-05 · Repo at D:\coding\case-trainer
Original folder name contained a space; Android NDK/CMake builds can break on spaces. Owner approved.

### 2026-11-05 · Scope: Prompts 1–3, then owner review
Owner wants real understanding over speed; P50 results and model answers are reviewed before the UI is built on them.

### 2026-11-05 · Challenge mode added on top of the spec
Owner's core weakness is reasoning *before and during* analysis. Four extra step types:
`data_expectation`, `cleaning_justification`, `plan_challenge`, `decision_threshold`.
They use the same rubric/grader machinery as other free-text steps.

### 2026-11-05 · Portfolio order P50 → P34 → P3 → P13 → P1
First five of spec §8; covers all four sectors for cold outreach.

### 2026-11-05 · Python 3.13 + uv (lockfile)
Installed already; all pinned libs support ≥3.13 (numpy/scipy need ≥3.12). FastF1 needs ≥3.10 — fine.

### 2026-11-05 · No `abiFilters` in Gradle; build with `--target-platform android-arm64`
Gradle refuses `ndk.abiFilters` together with `--split-per-abi`. Passing the target platform on the
command line gives an arm64-only APK without the conflict.

### 2026-11-05 · Raw data committed when the licence allows
pytest asserts results computed from raw files; FRED revises history, so a re-download could change
numbers. Committing the raw (with SHA-256 in provenance) keeps tests reproducible. Restricted datasets
(StatsBomb, LOBSTER, Kaggle) get a per-case .gitignore and a documented re-download step.

### 2026-11-05 · Embeddings plugin: flutter_onnxruntime (not `onnxruntime`)
`onnxruntime` last published 2024-03; flutter_onnxruntime 1.9.0 published 2026-10. 16 KB page
support still to verify in Prompt 6; fallback is MediaPipe Text Embedder via platform channel.

### 2026-11-09 · P50: model on expansion months only
The first plan (all months) fitted badly (pseudo-R² ≈ 0.05, negative OOS skill), because inside a recession the
target is 1 while the curve has re-steepened. Expansion-only matches the decision (the PM acts before a recession). The rejected
plan's numbers are kept as `*_all_months_*` results and taught in step s11. Details: docs/knowledge/cases/p50_yield_curve.md.

### 2026-11-09 · P50: embargo in the expanding window, threshold from training only
At forecast month t, train on rows ≤ t−12 (target needs USREC to s+12). Threshold = max Youden J on data
known at the first forecast month. 10y–3m was chosen a priori as the decision spread (literature benchmark).

### 2026-11-09 · P50: NY Fed benchmark not obtained
The probability series is behind an interactive page with no direct file link. No URL was guessed. It can be added later
if the owner downloads the file by hand.

### 2026-11-09 · Calibration answers may use {expected.key} placeholders
Correct numbers in example answers come from the pipeline, like content text. Deliberately WRONG numbers in
wrong/red-flag answers are typed, because they are not results. build_content.py fails if a calibration placeholder
key is missing.

### 2026-11-05 · drift + sqlite3 (not sqlite3_flutter_libs)
sqlite3_flutter_libs is marked end-of-life (0.6.0+eol). To confirm in Prompt 4 that sqlite3 3.x
bundles the native library on Android.
