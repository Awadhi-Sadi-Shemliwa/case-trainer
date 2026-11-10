# Case Trainer

An Android app (Flutter) that trains data-science thinking on real, pre-solved business cases: predict the data
before loading it, justify every cleaning step, challenge your own plan, and end with a decision threshold and a
memo. A Python pipeline solves each case offline on real public data; the app only presents and examines.

## How it is built
- `pipeline/`: one folder per case (`download.py` → `clean.py` → `analyse.py` → `content.yaml`). Every number
  shown in the app is a key in the case's `expected_results.json` and is re-computed by `pytest`.
  Every raw file has a provenance entry (URL, retrieval time, SHA-256, licence, row/column counts, logged drops).
- `app/`: Flutter 3 app (Riverpod, go_router, SQLite content bundle, Syncfusion charts with PNG fallback).
- `docs/knowledge/`: architecture, decisions, environment, troubleshooting and per-case notes.
  Start at `docs/knowledge/00_START_HERE.md`. Progress: `docs/ROADMAP.md`.

```
cd pipeline && uv run pytest && uv run python build_content.py
cd app && flutter test && flutter build apk --release --split-per-abi --target-platform android-arm64
```

## Cases
| Case | Sector | Question |
|---|---|---|
| P50 | Finance | Does the yield curve warn of US recessions, and at what probability should a PM de-risk? |
| P34 | Football | Did matches without crowds shrink home advantage? |
| P3 | Aviation | How much flight delay is passed on to the next flight, and how long should turns be? |
| P13 | Formula 1 | Where is the tyre degradation cliff, and when does an extra pit stop pay? |

## Data and credits
Repository: https://github.com/Awadhi-Sadi-Shemliwa/case-trainer

Raw data is used under each provider's terms. Large or non-redistributable raw files are not committed; their
SHA-256 is in `provenance.json` and `download.py` fetches them again.
- **FRED**, Federal Reserve Bank of St. Louis: series T10Y2Y, T10Y3M, USREC ("Copyrighted: Citation Required";
  cited per series in provenance). https://fred.stlouisfed.org/
- **Football-Data.co.uk**: match results and statistics. https://www.football-data.co.uk/
- **US Bureau of Transportation Statistics**, Reporting Carrier On-Time Performance (public domain; raw zips not
  committed, aggregates committed). https://www.transtats.bts.gov/
- **OpenF1** (P13): unofficial, community-run F1 data API, licensed CC BY-NC-SA 4.0. Raw data not committed; any
  derived data published here is shared under CC BY-NC-SA 4.0 with credit to OpenF1. https://openf1.org/
  Not associated with Formula 1 companies; F1 and related marks are trademarks of Formula One Licensing B.V.

Research cited in the cases is listed, with short verified quotes, in `sources.json`.
