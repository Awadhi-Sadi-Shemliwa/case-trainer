# START HERE — recovering or continuing the project

If the app crashes, a session is lost, or you come back after weeks, read in this order:

1. `CLAUDE.md` (repo root) — the rules. `docs/spec.pdf` — the full spec.
2. `docs/ROADMAP.md` — which prompt we are on and what is blocked.
3. `docs/knowledge/ARCHITECTURE.md` — how the pieces fit.
4. `docs/knowledge/DECISIONS.md` — why things are the way they are (dated).
5. `docs/knowledge/TROUBLESHOOTING.md` — errors already hit and their fixes.
6. `docs/knowledge/cases/<case>.md` — what each case's data taught us.

## Rebuild everything from a clean clone
```
# prerequisites: see ENVIRONMENT.md (Python 3.13 + uv, Flutter stable, Android SDK)
cd pipeline
uv sync                       # exact versions from uv.lock
uv run pytest                 # framework + every case's result asserts
uv run python build_content.py   # validates cases -> app/assets/content/
cd ../app
flutter pub get
flutter test
flutter build apk --debug --split-per-abi --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
```

## Where things live
| Thing | Path |
|---|---|
| Raw data + provenance | `pipeline/cases/<case>/raw/`, `pipeline/cases/<case>/provenance.json` |
| Every number | `pipeline/cases/<case>/expected_results.json` |
| Case text, rubrics | `pipeline/cases/<case>/content.yaml` |
| Grader calibration answers | `pipeline/calibration/<case>/` |
| Citations | `sources.json` (only VERIFIED ones may be shown) |
| Bundle the phone reads | `app/assets/content/` |
