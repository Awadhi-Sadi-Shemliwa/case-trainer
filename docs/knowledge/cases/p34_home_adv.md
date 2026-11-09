# P34 — Did empty stadiums shrink home advantage? (case notes)

Status: built end to end on 2026-11-09 (Prompt 8, batch 1). Awaiting owner review: 22 calibration answers are
flagged `owner_review: true`. Result numbers live in `expected_results.json` and are not typed here (project rule).

## Data
- football-data.co.uk league CSVs, Premier League (E0), Bundesliga (D1), La Liga (SP1), Serie A (I1), seasons
  2017/18–2021/22: 20 files, committed in `raw/` ("My data is free"; cite football-data.co.uk).
- Column meanings were verified in https://www.football-data.co.uk/notes.txt (2026-11-09).

## What the data taught us
1. **No attendance column.** Ghost games are defined by date. Each league's restart is found *in the data* as the
   first match after the longest pause in 2019/20 (Bundesliga in May 2020, the other three in June 2020). This
   matches the review's "resumed in the form of ghost games in May and June 2020". No dates are hand-typed.
2. **Date formats differ by season**: some 2017/18 files use `dd/mm/yy`, the rest `dd/mm/yyyy`. Both are parsed
   explicitly, and any unparseable date stops the pipeline.
3. **Column sets drift**: about 62 columns before 2019/20, about 105 after (more odds). Only the needed columns are read.
4. **Yellow cards are counted differently.** England doesn't count the first yellow when a second is shown; Europe
   does (notes.txt). So card comparisons stay within a league (league fixed effects); levels are never compared across leagues.
5. **2020/21 had some partial crowds.** The main ghost window is restart → end of 2020/21, and a strict window
   (2019/20 after the restart only) is the robustness check (`hw_strict_ghost`, `hw_change_strict`).
6. 3 team-match rows have zero fouls. They are dropped from the card model only (log offset), and the drop is logged.

## Method
- Difference in proportions for the home win rate (per league + pooled), with a Holm correction across the 4 leagues.
- Welch t-test for home goal difference.
- Cards: Poisson GLM of yellow cards per team-match, with a `log(fouls)` offset, league fixed effects and a
  `home × ghost` interaction (difference-in-differences). Standard errors are clustered by match.
- Confounder: median rest days between matches (`rest_fans`, `rest_ghost`).
- Decision: the pricing-model home goal edge is reduced by `adj_goals` (range `adj_goals_lo`–`adj_goals_hi`) when
  crowds are absent.

## Headline result keys
`hw_fans`, `hw_ghost`, `hw_back`, `hw_change` (+ CI), `n_leagues_significant` vs `n_leagues_unadjusted_sig`,
`gd_fans`/`gd_ghost`/`gd_back`, `gd_share_lost`, `rr_did` (+ CI, p), `rest_fans`/`rest_ghost`, `adj_goals`.

## Teaching points
- Pooled evidence is strong, but after Holm **no single league** is significant. Don't rank leagues on noise.
- Cards must be counted per foul and compared with home teams (DiD); raw card totals mislead.
- The two verified papers disagree on the referee mechanism (review vs Leitner & Richlan 2021). Teach that.
- Congested fixtures in the ghost period are a confounder, so say "consistent with", not "proves".

## Limitations
No attendance data; partial crowds in 2020/21; congestion; four leagues only; cards depend on referee style trends.
