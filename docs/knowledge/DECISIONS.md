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

### 2026-11-09 · App storage: `sqlite3` directly, not drift (supersedes the 2026-11-05 entry below)
Both DBs are tiny and fixed (read-only bundle, four progress tables). drift adds build_runner code generation
for little gain. sqlite3 3.x bundles SQLite itself (verified: runs on the S21+ and in Windows host tests).

### 2026-11-09 · Charts are the pipeline PNGs until Prompt 5
Spec Prompt 4 only needs play-through to the first chart. Interactive Syncfusion/fl_chart rendering is Prompt 5.

### 2026-11-09 · Model answer visible after submitting, only while the grader is a stub
Until the examiner exists you can still self-check. `Grader.isStub` gates it; Prompt 6 switches to the
spec's attempt-3 reveal.

### 2026-11-09 · Checked steps reveal after 3 failed attempts
Mirrors the examiner's 3-attempt rule for mcq/order/numeric/code steps.

### 2026-11-05 · drift + sqlite3 (not sqlite3_flutter_libs)
sqlite3_flutter_libs is marked end-of-life (0.6.0+eol). To confirm in Prompt 4 that sqlite3 3.x
bundles the native library on Android.

### 2026-11-09 · Syncfusion: no licence key in the app
Syncfusion 35.x no longer needs a runtime key (CHANGELOG quoted in ENVIRONMENT.md). The owner's Community Licence
registration covers use. Nothing secret is in the repo, which matters because it will be public.

### 2026-11-09 · fl_chart not added (spec lists it as a fallback)
With a valid Syncfusion licence, fl_chart would only duplicate rendering. The spec's real fallback, the
pipeline PNG on parse failure, is implemented and tested. Revisit if Syncfusion's terms change.

### 2026-11-09 · LineSeries, not FastLineSeries
Measured on the S21+: 9 runs, no difference in missed frames (ENVIRONMENT.md). Keep the simpler code path.

### 2026-11-09 · Raw data is binary in git
`.gitattributes` `* text=auto eol=lf` rewrote CRLF in football-data CSVs, so committed blobs failed their SHA-256.
`pipeline/cases/*/raw/** binary` now keeps raw files byte-for-byte; verified with a fresh clone.

### 2026-11-09 · P13 blocked: F1 timing data needs F1TV
FastF1 3.9.2 signs in to a Formula 1 account and needs "An active F1TV subscription" (installed source,
`internals/f1account`). No substitute data (rule). Kept: `cases/p13_tyre_deg/download.py` and an isolated env
`pipeline/f1_fetch/` (FastF1 needs pandas<3; main pipeline is pandas 3). Owner options: F1TV login, or a Tier-B
reframe on Jolpica lap times + pit stops (no tyre compounds).

### 2026-11-10 · P13 unblocked: use OpenF1 instead of FastF1
Re-tested FastF1 3.9.2 on 2026-11-10: without credentials every timing feed fails ("Failed to load timing data!"),
and its sign-in code says "An active F1TV subscription is required." A free F1 account is not enough.
OpenF1 (https://openf1.org, API https://api.openf1.org/v1/) works with no login. Probed for the 2023 Bahrain race
(session_key 7953): `laps` (lap_duration, is_pit_out_lap, sectors), `stints` (compound, tyre_age_at_start,
lap_start/lap_end) and `race_control` (Safety Car / VSC messages with lap numbers) all return data.
Terms (openf1.org, read 2026-11-10): "Licensed under CC BY-NC-SA 4.0"; intended for "educational purposes, personal
learning projects, research". Free tier: historical sessions since 2023, 3 req/s and 30 req/min.
Handling: raw JSON stays git-ignored (same as before); committed aggregates and charts carry a CC BY-NC-SA 4.0 notice
and credit OpenF1 (ShareAlike applies to derived data we publish). FastF1 env `pipeline/f1_fetch/` was removed
once the OpenF1 download was written (2026-11-10).

### 2026-11-09 · Large raw data: commit aggregates, not raw (P3)
BTS 2025 is ~350 MB. Raw zips are git-ignored with SHA-256 in provenance; `clean.py` writes small aggregates
(sufficient statistics for exact OLS) that are committed. Tests reproduce results from aggregates always, and
aggregates from raw when raw is present.
**2026-11-10 fix (found by a fresh-clone cross-check):** `build_content.py` failed in a fresh clone because it
required the git-ignored zips. Such datasets now carry `"committed": false` in provenance; `verify_hashes` skips
them only when the file is absent and still checks the hash when it is present. A framework test asserts that
every git-ignored raw file is marked `committed: false` and every tracked one is not.

### 2026-11-09 · Unverifiable claims are not taught
P3: BTS category definitions (e.g. non-extreme weather → NAS) could not be opened (403 / anti-bot redirect). No
workaround attempted; the case teaches only verified statements (proration, 15-minute rule).

### 2026-11-09 · Quality gate per case (spec Prompt 8)
A fresh reviewer audits each new case. P34's review found over-claims (seasonality, inconclusive reversal,
underpowered robustness check, pre-trend, negatable red-flag keywords); all fixed before marking done.

### 2026-11-10 · P13 design decisions
- Seasons 2023-2025 only (OpenF1 starts in 2023; 2026 has new car and tyre rules).
- Wet race = intermediate or wet tyres used. Rain on slicks is a per-lap rule. Races whose median driver has under 80%
  of laps in the feed are excluded (Miami 2025).
- Model: driver-race fixed effect (the spec's stint FE + lap number is not identified). SEs clustered by race.
- Cliff rule: lower leave-one-race-out error AND race-level sign test AND a steepening break; no in-sample p-value.
- Decision: split length 2*sqrt(P/s) with the spread taken across circuits, not from the pooled CI.
- Stint lengths with Kaplan-Meier (stints to the flag are censored).
- Repo published 2026-11-10 at https://github.com/Awadhi-Sadi-Shemliwa/case-trainer (public). The Gemini PDF was
  removed from all history before the first push (owner's choice) and is kept locally, git-ignored.
