# Case Trainer — project rules

Full spec: docs/spec.pdf (single source of truth; Section 2 overrides everything).
Start-here / recovery docs: docs/knowledge/00_START_HERE.md. Progress: docs/ROADMAP.md.

## NEXT TASK (owner, 2026-11-16)
"Building new real data for all the 4 groups such that once one problem is finished another pops up, as i said dont worry about the size of app make sure we achieve the target of me being the best data scientist"
Order per sector follows pipeline/catalog.yaml build_rank (football: P33 first). Same rules as every case: real data only.

## What this is
Python pipeline (pipeline/) solves 50-problem cases offline on REAL public data and writes a
content bundle; Flutter Android app (app/) only presents and examines. The app never computes results.

## DO
- Plan mode for every multi-file change; wait for approval.
- Load every raw file and print schema (columns, dtypes, head, rows) before writing code that uses it.
- One provenance.json entry per raw file (URL, UTC time, SHA-256, licence, rows, columns, transforms with counts + reasons).
- Every number shown in the app is a key in expected_results.json, asserted by pytest.
- Mark external claims VERIFIED (URL opened, quote stored) or UNVERIFIED.
- Time-based splits for time-ordered data. Fixed seeds. Pinned versions (uv.lock, pubspec.lock).
- Check package versions/APIs on pub.dev / PyPI before use; flag discontinued packages.
- Measure performance on the real Galaxy S21; never estimate.
- Small commits; run all tests (`uv run pytest`, `flutter test`) before saying done.
- Update docs/knowledge/ (DECISIONS, TROUBLESHOOTING, cases/*.md) whenever something is learned.

## DON'T
- Type numbers by hand into Dart, content YAML, Markdown or rubrics — use {expected.key} placeholders.
- Invent columns, series IDs, file names, endpoints, APIs or citations.
- Cite Gemini's references (docs/source/) or any source not VERIFIED in sources.json.
- Use synthetic/simulated data in a case. No real data => STOP and report.
- Silently drop rows/outliers — log what and why.
- Let any LLM change or invent numbers. Grading (owner decision 2026-11-16): the Claude examiner judges coverage of
  each rubric point; the app computes the score from the weights, checks numbers against expected_results, and
  applies pass = score >= 85 with no critical red flag (docs/knowledge/GRADING.md).
- Call the Claude API outside app/lib/grading/claude_client.dart, or break the budget rules in docs/knowledge/API_USAGE.md.
- Commit an API key. The Claude key lives in git-ignored app/secrets.json (`--dart-define-from-file=secrets.json`).
- Redistribute data beyond its terms (StatsBomb credit+logo; LOBSTER research use; check Yahoo/Kaggle).
- Build features from a later prompt than the current one.
- Claim causation unless the design supports it; always state limitations.

## Commands
- Pipeline: `cd pipeline && uv run pytest` · `uv run python build_content.py`
- App: `cd app && flutter test` · `flutter build apk --debug --split-per-abi --target-platform android-arm64`
