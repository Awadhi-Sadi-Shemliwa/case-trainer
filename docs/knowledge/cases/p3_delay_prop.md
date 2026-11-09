# P3 — How much flight delay is passed on, and where? (case notes)

Status: built end to end on 2026-11-09 (Prompt 8, batch 1). Awaiting owner review (22 calibration answers flagged).
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
3. Rotations come from `Tail_Number` (about 2.5 k flights a month have none). Pairs = same tail, same date, consecutive by
   scheduled departure, arrival airport = next origin.
4. Filters are logged once with year totals: turn window 20–240 min; inbound delay 0–180 min; cancelled and diverted
   flights excluded from delay stats.
5. **Non-linear propagation**: tight turns pass on *more* than the inbound delay (`pass_b1` > 100%). Pass-through
   falls only once the turn leaves slack. Linear slopes stay near 1 for short turns, which is why the decision uses the
   model-free **pass-through of a 60–74-minute-late arrival** (`REF_BIN`).
6. **Small denominators**: the brightest heatmap cell (`worst_cell_*`) rests on `worst_cell_deps` departures against
   `hub_median_cell_deps` per cell.
7. Exact OLS from **sufficient statistics** (n, Σx, Σy, Σx², Σxy) per month × band × bin. The aggregates are
   tiny but the slopes are exact.

## Not taught (could not verify)
How BTS splits weather across categories (e.g. "non-extreme weather is coded NAS"). The bts.gov definitions page
returns 403 to automated requests, eCFR redirects to an anti-bot page, and the archives were empty. No workaround
was attempted. The case only says categories are carrier-reported labels.

## Decision
Buffer rule chosen on **Jan–Sep only**: the shortest turn band whose pass-through is below `pass_target` →
`buffer_min_turn` minutes, applied to afternoon and evening turns at the airports where delay accumulates. It is piloted
against control banks, because the curve is observational. Expected saving: `buffer_saving_ref` minutes per one-hour-late arrival.

## Limitations
Observational (turn length is chosen by schedulers); aircraft swaps break chains; cancellations drop out; carrier labels
aren't causes; one year; one-hour reference bin.
