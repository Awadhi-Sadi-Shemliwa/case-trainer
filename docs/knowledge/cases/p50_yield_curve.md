# P50 — Does yield-curve inversion predict US recessions? (case notes)

Status: built end to end in the pipeline (Prompt 3), 2026-11-09. **Awaiting owner review** of the results,
model answers and the calibration answers flagged `owner_review: true`.

Result numbers are NOT typed here (project rule). Each one is named by its key in
`pipeline/cases/p50_yield_curve/expected_results.json`. Print them with:
`uv run python -c "import json;[print(k,v['display']) for k,v in json.load(open('cases/p50_yield_curve/expected_results.json')).items()]"`

## Files
| File | What it does |
|---|---|
| `download.py` | Fetches FRED T10Y2Y, T10Y3M, USREC untouched → `raw/`, records provenance + schema |
| `clean.py` | Drops holiday blanks → monthly means → joins USREC → builds target → flags model sample |
| `analyse.py` | Lead times, false alarms, probit + HAC, expanding-window OOS, threshold, today's reading, 4 charts |
| `test_case.py` | Hash check, re-runs clean+analyse in a temp dir and asserts **every** result key, embargo test |
| `content.yaml` | 25 steps, brief → debrief |
| `../../calibration/p50_yield_curve/*.yaml` | 9 graded steps × 32 labelled answers |
| `clean_panel.csv`, `captured_outputs.json`, `charts/` | Generated: re-run `clean` then `analyse` to refresh |

Run order: `uv run python -m cases.p50_yield_curve.clean` then `uv run python -m cases.p50_yield_curve.analyse`.
Then `uv run pytest` and `uv run python build_content.py`.

## What the data taught us (surprises vs the spec)
1. **The missing-value marker is a blank cell, not `'.'`.** The spec expected `'.'`. The current FRED
   `fredgraph.csv` exports use empty cells (counts in provenance transforms `drop_blank_*`), almost all on US bond-market
   holidays (Nov-11, Jul-04, Dec-25, Jan-01). They were dropped, not filled, and logged as `drop_blank_*`.
2. **USREC uses the trough method.** The peak month is excluded and the trough month included. The latest
   zeros are provisional, because NBER dates recessions 6–18 months after the fact.
3. **T10Y3M starts in 1982-01**, T10Y2Y in 1976-06. Model comparisons use the common sample.
4. **The first modelling plan failed, and why.** Keeping months already in recession gave a very low pseudo-R²
   (`pseudo_r2_all_months_*`) and negative out-of-sample skill. Inside recessions the target is 1 but the curve has re-steepened
   (the Fed is cutting), which teaches the model the reverse relationship. Restricting fitting and scoring to
   expansion months (`exclude_current_recession`, `n_recession_months_excluded`) raised it (`pseudo_r2_10y3m`). The
   rule comes from the decision (the PM acts during expansions), not from the score. The numbers for the
   rejected plan are kept as `*_all_months_*` results, and step s11 teaches this.
5. **HAC matters.** Overlapping 12-month targets make naive standard errors too small by the factor `se_ratio_*`.
6. **Discrimination ≠ calibration.** Out-of-sample AUC is good (`auc_oos_10y3m` > `auc_oos_2s10s`), but the
   Brier skill vs climatology (`bss_oos_10y3m`) is **negative**. The post-hoc split from `split_from` shows why:
   skill was positive before it (`bss_oos_pre_split_10y3m`), then the latest long inversion averaged
   `mean_prob_post_split_10y3m` and no recession followed. That is consistent with
   Johansson & Meldrum (2018): a lower term premium can make the raw slope overstate risk.
7. **2s10s missed the pandemic recession** (it never inverted on a monthly-mean basis). 10y–3m inverted in 2019.
8. **NY Fed published probabilities: NOT obtained.** The data sits behind `ycfaq#/interactive` with no direct
   file link. An automated fetch with a browser User-Agent was blocked by the session's safety policy (correctly),
   and no URL was guessed. To add the benchmark, the owner can download the file by hand from the interactive
   page into `raw/`. Then add a `Provenance.fetch` entry (or record it as hand-downloaded with its SHA-256) and a
   comparison in `analyse.py`.

## Design decisions in this case
| Decision | Choice | Why |
|---|---|---|
| Target | `rec_next12` = recession in any of t+1..t+12 | Matches "next year" decision; NY Fed uses exactly t+12, ours is a window |
| Inverted | monthly-mean spread < 0 | Single-day dips are noise |
| Episode merge gap | ≤ 3 normal months | Monthly means flicker around zero |
| Lead window | 24 months | Literature says 4–6 quarters; 24 allows the long 1980s leads |
| Model | univariate probit | Estrella–Mishkin / NY Fed convention; logit reported for comparison |
| SEs | HAC Newey-West, 12 lags | Overlap = horizon |
| OOS | expanding window from 1991-04, embargo: train on rows ≤ t−12 | Row s needs USREC up to s+12 |
| First OOS month | after the 2nd complete recession in the 10y–3m sample | The model has seen >1 event |
| Primary spread for the decision | 10y–3m, chosen a priori | Literature benchmark (spec §6 correction) |
| Threshold | max Youden J on training data only → `threshold` | No peeking at the test |
| Trigger in spread units | full-sample probit inverse → `trigger_spread_10y3m` | Makes the rule something the PM can watch |
| Split diagnostic | 2022-01 | Explains the lost skill; NOT used for any model choice |

## Headline result keys (what to show a recruiter)
- Lead: `median_lead_months` (range `min_lead_months`–`max_lead_months`), `recessions_signalled_2s10s` of
  `recessions_evaluable_2s10s`, `false_alarm_episodes_2s10s`.
- OOS: `auc_oos_10y3m`, `auc_oos_2s10s`, `bss_oos_10y3m`, `bss_oos_pre_split_10y3m`.
- Trigger: `threshold` ≈ 10y–3m at `trigger_spread_10y3m`; `oos_hit_rate`, `oos_false_alarm_rate`,
  `oos_signal_precision`, `oos_recessions_caught` of `n_oos_recessions`, lead `oos_signal_median_lead`.
- Today (`latest_month`): `latest_spread_10y3m` → `latest_prob_10y3m` → signal `latest_signal_10y3m`.

## What would change the conclusion
- A recession starting before about 2026 (USREC revision) would turn the 2022–25 "false alarm" into a long-lead hit.
- Adding a term-premium-adjusted spread (the next step in the memo) could fix the calibration.
- The NY Fed benchmark comparison is still missing.

## Limitations to keep teaching
Few recessions (3 out-of-sample); association, not causation; USREC is not real time; the split is post-hoc;
the spread is a single predictor.
