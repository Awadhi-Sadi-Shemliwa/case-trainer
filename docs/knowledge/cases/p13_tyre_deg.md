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
3. **Cliff:** hinge `max(0, age - k)` per compound, k on a grid with `MIN_LAPS_SIDE` laps each side, chosen on the
   training races inside each leave-one-race-out fold. A cliff needs lower held-out error AND more race wins than
   chance (sign test `loro_sign_p_*`) AND a positive extra slope (`cliff_supported_*`, `n_compounds_with_cliff`). No
   in-sample p-value: the break age was picked on the same data. Result: the break helps by under 1% and bends the
   wrong way (flattens). **Fixed-set check** (`fixedset_*`): on stints that run well past the break, the flattening
   remains, so survivor selection is NOT the whole explanation (tyre management, warm-up/graining, fuel-saving,
   non-linear track evolution are open). One break age is shared by all circuits, so a circuit-specific cliff is
   untested.
4. **Decision:** split a stint when the wear saved by an extra stop beats the pit loss. Linear wear s: L* =
   2*sqrt(P/s) (`split_len_*`). The real range comes from circuits (`split_len_hard_circ_*`, each circuit's own wear
   and pit loss), not from the pooled CI (`split_len_*_short/long`, too narrow). Over a median race (`race_laps_median`)
   wear alone justifies `stops_wear_*` stop(s). Stint lengths use Kaplan-Meier (`stint_len_median_*`): stints that run
   to the flag are censored, not stops (`share_stints_to_flag_*`).
5. **Checks:** traffic gap and incident thresholds varied (`deg_*_gap05/gap20/inc3/inc8`; soft moves about 11% with
   the looser gap); per-race lap slope (`deg_*_racelap`); compound offset per race (`deg_*_raceoffset`); track
   temperature (`deg_*_temp`, `temp_slope`); out-of-time 2023-24 vs 2025 (`deg_*_train/test`, `oot_gain`; soft wear
   shifted, taught in the memo).

## Quality-gate review (fresh reviewer, 2026-11-10): what changed
- **SC/VSC windows never closed** when a VSC became a SC or a SC ended in a red flag: whole races were neutralised
  (Interlagos 2023 had 0 clean laps). Windows now close at the SC deployment / red flag; red flag runs to the next
  SESSION STARTED plus two restart laps. Test: every kept race has clean laps and under 40% neutralised.
- **Lusail 2024 was labelled wet** because of an UNKNOWN compound. Wet now = INTERMEDIATE/WET used; unknown-compound
  laps drop as `no_stint`. **Miami 2025 feed is incomplete** (58% lap coverage): excluded and logged.
- **Content said the break "never beat" the line**; it was slightly better (under 1%) but not reliably and bent the
  wrong way. Wording fixed everywhere; key renamed `n_compounds_with_cliff`; claims locked in `test_crosscheck.py`.
- **Censoring was taught as the proven cause** of the flattening; the fixed-set check showed it isn't the whole story.
- **Split-length range was far too narrow**; now per circuit. **Decision reframed**: wear justifies one stop, not two.
- Numeric tolerances tightened so wrong answers (e.g. the line's RMSE, the medium slope) can't pass. The vacuous LORO
  test was replaced by one that records every training mask the cliff search uses.

## Limitations
Observational; lap number mixes fuel with track evolution; temperature, set-up and tyre pressures not modelled;
traffic threshold is a convention; OpenF1 is unofficial timing data; the cliff (if any) beyond the ages teams run is
untested, not ruled out; the decision ignores track position, undercuts and the two-compound rule.
