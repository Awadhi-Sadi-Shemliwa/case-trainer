# Troubleshooting

Format: **symptom** → cause → fix. Add every error you hit.

### `adb` not recognised
adb isn't on PATH. See ENVIRONMENT.md → "adb is not on PATH".

### FRED `fredgraph.csv` download times out from PowerShell (2026-11-05)
The series web page loads fine, but plain `Invoke-WebRequest` to `fredgraph.csv` timed out.
Pipeline download sends a browser-like User-Agent with retries; if it still fails, use the FRED API
(`https://api.stlouisfed.org/fred/series/observations`) with a free key in env var `FRED_API_KEY`.
Never substitute data.

### Gradle: "Conflicting configuration … abiFilters … splits"
Don't set `ndk.abiFilters`; use `--split-per-abi --target-platform android-arm64`.
