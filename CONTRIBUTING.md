# Contributing

BatteryScope is an original SwiftUI macOS app. Use Swift 6+ and macOS 14+.

1. Fork and clone the repository.
2. Run `./test.sh` and `./build.sh`.
3. Keep sensor decoding and persistence in `Sources/BatteryCore`; UI lives in `Sources/BatteryScope`.
4. Add synthetic fixtures for new fields and failure cases. Record units, provenance, model coverage, and unknown values in `docs/DATA_SOURCES.md`.
5. Open a pull request describing behavior and the checks actually run.

A real battery is optional for tests. To validate hardware reads on a Mac notebook, run `BATTERYSCOPE_LIVE_TEST=1 ./test.sh`. Interactive checks should cover source selection, menu bar behavior, foreground/background notifications, CSV export, sleep/wake, and charge/discharge transitions.

Do not commit personal battery history, raw registry dumps, serial numbers, third-party executables/assets, decompiled code, or local REA/Ghidra/Java installations. Read-only monitoring is the current scope; hardware charge controls require a separate design discussion.
