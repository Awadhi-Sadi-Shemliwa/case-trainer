# P3 — How much flight delay is passed on, and where? (case notes)

Status: built end to end on 2026-11-09 (Prompt 8, batch 1). Awaiting owner review (27 calibration answers flagged).
Result numbers live in `expected_results.json` (not typed here).

## Data
- BTS Reporting Carrier On-Time Performance, all 12 months of **2025**, from TranStats PREZIP:
  `https://transtats.bts.gov/PREZIP/On_Time_Reporting_Carrier_On_Time_Performance_1987_present_2025_<m>.zip`.
  US government data (public domain).
- **The raw zips (~350 MB) are git-ignored.** Their SHA-256 is in `provenance.json`. Re-download with
  `uv run python -m cases.p3_delay_prop.download`.
- `clean.py` reduces about 7 M flights to **committed aggregates** (`aggregates/*.csv`, ~160 KB). `analyse.py` reads
  only those, so tests run in a fresh clone. The full raw→aggregate rebuild test runs only when the raw files exist.
- Field definitions were verified from the `readme.html` inside each zip.

## What the data taught us
1. Cause minutes exist exactly for flights with `ArrDel15 == 1`. They are prorated by minutes (BTS: "each cause is
   prorated based on delayed minutes it is responsible for"), and the sum matches arrival delay minutes (`proration_gap`).
2. Times are **local hhmm**. Midnight can be written as 2400. Turn time = next scheduled departure minus scheduled arrival
   **at the same airport** (one time zone). Overnight inbound legs are dropped (ambiguous date without zones).
3. Rotations come from `Tail_Number` (missing tail numbers occur only on cancelled flights; every operated flight has one). Pairs = same tail, same date, consecutive by
   scheduled departure, arrival airport = next origin.
4. Filters are logged once with year totals: turn window 20–240 min; inbound delay 0–180 min; cancelled and diverted
   flights excluded from delay stats.
5. **Non-linear propagation**: short turns pass on about one-for-one *extra* delay; pass-through falls only once the
   turn leaves slack (see the quality-gate notes for why the raw >100% figure is not amplification).
6. **Small denominators**: the brightest heatmap cell (`worst_cell_*`) rests on `worst_cell_deps` departures against
   `hub_median_cell_deps` per cell.
7. Exact OLS from **sufficient statistics** (n, Σx, Σy, Σx², Σxy) per month × band × bin. The aggregates are
   tiny but the slopes are exact.

## Quality-gate review (fresh reviewer, 2026-11-10): what changed
- **"Amplification" was an artefact.** Raw pass-through Σy/Σx includes the baseline outbound delay (`base_out_*`).
  **Excess pass-through** (baseline bin 0–14 min removed, `pass_*`) is about one-for-one on short turns. Raw kept as
  `pass_raw_*` for the lesson.
- **Carrier mix confounds turn bands** (`top_carrier_short` = WN, `top_carrier_short_share`). The aggregates now carry
  carrier and a clean-day flag. A **carrier-weighted** curve of within-carrier excess pass-through (`pass_cw_*`) and a
  no-cancellation-day curve (`pass_clean_*`) both match the pooled one, so mix and swaps don't drive the result.
- **Buffer rule by interpolation** on band means (Jan–Sep): `buffer_turn_exact` → `buffer_min_turn` (rounded up to
  5). **Out-of-time check fails**: Oct–Dec crosses at `buffer_turn_octdec` and the rule passes on `buffer_pass_octdec`
  (`buffer_rule_holds_octdec` = no). The decision is a range to pilot. Saving per added minute: `saving_per_added_minute`.
- **Every rotation drop is logged** (with_tail, has_next_leg, same_airport, not_overnight, turn_window, delay_range).
- **Heatmap**: cells under `min_cell_deps` departures are masked; the morning-vs-evening ratio is partly mechanical
  (first-wave aircraft sat overnight); the worst evening airport is `evening_worst_airport`.
- Common shocks (ground stops, weather) and crew connections are named as confounders.

## Not taught (could not verify)
How BTS splits weather across categories (e.g. "non-extreme weather is coded NAS"). The bts.gov definitions page
returns 403 to automated requests, eCFR redirects to an anti-bot page, and the archives were empty. No workaround
was attempted. The case only says categories are carrier-reported labels.

## Decision
A minimum turn of `buffer_min_turn`–`buffer_turn_octdec` minutes, piloted against control banks on afternoon and
evening turns at the worst airports. Not network-wide: each added minute saves only `saving_per_added_minute` minutes
for a one-hour-late arrival.

## Limitations
Observational (turn length is chosen by schedulers); aircraft swaps break chains; cancellations drop out; carrier labels
aren't causes; one year; one-hour reference bin.
