# Environment (recorded 2026-11-05)

| Tool | Version | Notes |
|---|---|---|
| OS (PC) | Windows 11 Home | Repo path has no spaces on purpose (Android native builds dislike spaces) |
| Python | 3.13.3 | Managed by uv 0.10.2; versions locked in `pipeline/uv.lock` |
| Flutter | 3.44.8 stable, Dart 3.12.2 | `C:\Users\awadh\dev\flutter` |
| Java | OpenJDK 21.0.11 | |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` | platforms 35, 36, 36.1, 37.0; build-tools 35/36 |
| compileSdk / targetSdk | 36 / 36 | Flutter 3.44.8 defaults (FlutterExtension.kt) |
| minSdk | 26 | spec §3 |

## adb is not on PATH
adb is at `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`. Add to PATH (PowerShell, once):
```
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:LOCALAPPDATA\Android\Sdk\platform-tools", "User")
```
Then open a new terminal and run `adb version`.

## Galaxy S21: enable USB debugging and install
1. Settings → About phone → Software information → tap **Build number** 7 times (enter PIN).
2. Settings → Developer options → turn on **USB debugging**.
3. Plug in with a data USB cable; on the phone accept "Allow USB debugging?" (tick *Always allow*).
4. PC: `adb devices` → should list the phone as `device` (not `unauthorized`).
5. `cd app && flutter run` (debug, hot reload) **or**
   `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
6. Record the phone's Android / One UI version here (Settings → About phone → Software information):
   - Android: _owner to fill_ · One UI: _owner to fill_ · Model (S21 / S21+), chip: _owner to fill_

## Verified package versions (pub.dev / PyPI APIs, 2026-11-05)
Flutter: flutter_riverpod 3.4.3 · go_router 18.1.3 · drift 2.35.3 · sqlite3 3.9.0 ·
syncfusion_flutter_charts 35.1.43 · fl_chart 1.3.0 · flutter_onnxruntime 1.9.0 · flutter_edge_ai 2.5.6 ·
path_provider 2.1.6 · share_plus 13.3.1 · yaml 3.1.4.
Flagged: **flutter_gemma discontinued → flutter_edge_ai**; **sqlite3_flutter_libs EOL**;
`onnxruntime` (Dart) stale since 2024-03; flutter_highlight unmaintained since 2021.
Python: see `pipeline/pyproject.toml` (all pinned with `==`).
