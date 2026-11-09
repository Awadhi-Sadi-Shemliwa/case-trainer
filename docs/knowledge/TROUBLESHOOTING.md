# Troubleshooting

Format: **symptom** → cause → fix. Add every error you hit.

### `adb` not recognised
adb isn't on PATH. See ENVIRONMENT.md → "adb is not on PATH".

### FRED `fredgraph.csv` download times out from PowerShell (2026-11-05)
The series web page loads fine, but plain `Invoke-WebRequest` to `fredgraph.csv` timed out.
Pipeline download sends a browser-like User-Agent with retries; if it still fails, use the FRED API
(`https://api.stlouisfed.org/fred/series/observations`) with a free key in env var `FRED_API_KEY`.
Never substitute data.

### FRED missing values are blank cells, not '.' (2026-11-09)
The spec expected `'.'`; current `fredgraph.csv` exports leave the cell empty. pandas reads that as NaN by default.
download.py records the actual markers per file in provenance (`non_numeric_markers`).

### content.yaml: `off`/`on`/`yes`/`no` become booleans (2026-11-09)
PyYAML follows YAML 1.1, where a bare `off` in a keyword list became `False` and pydantic rejected it. Quote such words.

### content.yaml: a plain scalar starting with `{` or containing `" ` mid-line breaks YAML
Quote any string that begins with `{expected...}`, and don't start a plain scalar with a quoted phrase.

### Build fails "hand-typed number(s) ['R2']"
Words that contain digits but are names (R2, T10Y2Y, 2s10s) go in the case's `allowed_literals`.

### NY Fed yield-curve data download
There is no direct file link on ycfaq (JS app). Don't spoof a browser User-Agent to scrape it; download it by hand if needed.

### Riverpod: "Tried to modify a provider while the widget tree was building" (2026-11-09)
Bumping `progressTickProvider` from `initState` throws. Write to the DB immediately, bump in
`WidgetsBinding.instance.addPostFrameCallback`. See `case_player_screen.dart`.

### Widget test: "derived an Offset … would not hit test" (2026-11-09)
The button is below the fold or behind the bottom bar. Use `_tapVisible` in `player_test.dart`
(`Scrollable.ensureVisible(..., alignment: 0.5)` then tap).

### A guard test that strips display strings is vacuous
Removing every result display string ("1", "5", "19"…) erases most digits, so injected numbers slip through.
Strip by WIDGET (skip ValueChip and CodeView), and mutation-check the test once.

### `ReorderableListView.onReorder` deprecated (Flutter 3.44)
Use `onReorderItem`; it already adjusts `newIndex` for the removed item.

### `flutter drive` on the phone: "SocketException: Connection refused … localhost" in traceAction (2026-11-09)
The device tries to reach the host's DDS port. Add `--no-dds`.

### Syncfusion: "The name 'ChartSeries'/'ChartAxis' is defined in the libraries …"
Syncfusion exports those names. Our chart model uses `SpecSeries` / `SpecAxis`.

### Progress gone after a perf run
`flutter drive` reinstalls the app, which wipes app data. Expected. Don't run it on a phone with real progress you want to keep.

### Gradle: "Conflicting configuration … abiFilters … splits"
Don't set `ndk.abiFilters`; use `--split-per-abi --target-platform android-arm64`.
