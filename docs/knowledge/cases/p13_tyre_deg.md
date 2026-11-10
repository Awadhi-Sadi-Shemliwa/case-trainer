# P13 — Where is the tyre degradation cliff? (case notes)

Status: built 2026-11-10 (Prompt 8, batch 1) on OpenF1 data. Result numbers live in `expected_results.json`
(not typed here). Calibration answers flagged for owner review are counted by `tests/test_crosscheck.py`.

## Data
- **OpenF1** (https://openf1.org), free historical API, no login. Licence CC BY-NC-SA 4.0; intended for
  educational, personal and research use. Not associated with Formula 1 companies.
- Why not FastF1 (the spec's source): FastF1 3.9 needs an active F1TV subscription (DECISIONS 2026-11-09/10).
- Races: every completed Grand Prix of 2023, 2024 and 2025 (`n_races`). 2026 excluded: new car and tyre rules.
- Endpoints per race: `laps`, `stints`, `race_control`, `intervals`, `weather`. `pit` had no rows for the probe race
  (Bahrain 2023), so in-laps come from stints. Fields verified by loading and printing every endpoint.
- **Raw JSON is git-ignored** (`committed: false` in provenance, SHA-256 recorded). `download.py` re-fetches it,
  throttled under the free tier's 30 requests per minute; OpenF1 answers empty queries with 404 "No results
  found", stored as `[]`.
- `clean.py` writes committed aggregates (`aggregates/laps.csv.gz`, `stints.csv`, `pit_stops.csv`, `races.csv`),
  derived data shared under CC BY-NC-SA 4.0. `analyse.py` reads only these, so the tests run in a fresh clone.

## Cleaning (each lap gets the FIRST reason that applies; totals logged once)
Wet races = intermediate or wet tyres used (whole race out). Then per lap: no time, lap 1, not in a stint, out-lap,
in-lap, neutralised (SC/VSC/red-flag windows from race-control **timestamps**, not leader lap numbers, plus one
restart lap), rain (latest weather sample shows rainfall), traffic (median gap to the car ahead during the lap below
`traffic_gap_s`), incident (more than `incident_s` slower than the stint median).
- First rule draft treated any recorded rain as a wet race. That threw out dry races where rain fell before the
  start (Austria, Spa, Brazil 2023 ran on slicks only), so rain became a per-lap rule.
- Tyre age = `tyre_age_at_start` + (lap − stint first lap). Used sets are common (`share_stints_used_tyres`).
- Red-flag stops include the suspension time (Melbourne 2023 pit "loss" ~1,000 s), so pit loss uses green-flag
  stops only.

## What the data taught us
1. **The spec's model is not identified.** With a stint fixed effect, tyre age and lap number are the same variable
   (`within_stint_corr_age_lap`, rank `stint_fe_rank` of `stint_fe_columns`). Without a fuel control the hard tyre
   looks like it improves (`naive_slope_hard`): the spec's red flag, reproduced.
2. **Fix:** a driver-race fixed effect. Pit stops reset tyre age but not lap number (`share_multi_stint` of
   driver-races have 2+ stints). Wear `deg_soft` > `deg_medium` > `deg_hard`; lap effect `fuel_slope` (fuel burn and
   track evolution together; they can't be split). SEs clustered by race.
3. **Cliff:** hinge `max(0, age − k)` per compound, k on a grid with `MIN_LAPS_SIDE` laps each side, chosen on the
   training races inside each leave-one-race-out fold. A cliff counts only if it beats the line out of sample AND the
   extra slope is positive and significant (`cliff_supported_*`, `n_cliffs_supported`). Censoring (teams pit
   first, `p13_stint_survival`) means the old-tyre laps come from survivors.
4. **Decision:** split a stint when the wear saved by an extra stop beats the pit loss. Linear wear s: L* =
   2·sqrt(P/s) (`split_len_*`, range `split_len_*_short`–`split_len_*_long`), compared with observed stint lengths.
5. **Checks:** traffic gap and incident thresholds varied (`deg_*_gap05/gap20/inc3/inc8`); a separate lap slope per
   race (`deg_*_racelap`); out-of-time 2023–24 vs 2025 (`deg_*_train/test`, `oot_gain`).

## Limitations
Observational; lap number mixes fuel with track evolution; temperature, set-up and tyre pressures not modelled;
traffic threshold is a convention; OpenF1 is unofficial timing data; the cliff (if any) beyond the ages teams run is
untested, not ruled out; the decision ignores track position, undercuts and the two-compound rule.
