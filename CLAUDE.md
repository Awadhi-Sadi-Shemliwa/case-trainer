# Case Trainer — project rules

Full spec: docs/spec.pdf (single source of truth; Section 2 overrides everything).
Start-here / recovery docs: docs/knowledge/00_START_HERE.md. Progress: docs/ROADMAP.md.

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
- Let any LLM decide pass/fail or change numbers; the deterministic grader decides.
- Redistribute data beyond its terms (StatsBomb credit+logo; LOBSTER research use; check Yahoo/Kaggle).
- Build features from a later prompt than the current one.
- Claim causation unless the design supports it; always state limitations.

## Commands
- Pipeline: `cd pipeline && uv run pytest` · `uv run python build_content.py`
- App: `cd app && flutter test` · `flutter build apk --debug --split-per-abi --target-platform android-arm64`
