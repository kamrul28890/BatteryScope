# Changelog

## 0.2.0

- Separate raw, nominal, and macOS-reported health, with source selection.
- Compare reported and instantaneous current/power and sensor/virtual temperature.
- Add state-aware remaining-time fallbacks, device-reported fault/condition warnings, and Low Power Mode status.
- Add lifetime voltage/current extrema and raw firmware counters.
- Add configurable refresh intervals and percentage/time alerts; refresh on power and wake events.
- Preserve recent minute history and daily health snapshots with notes and CSV exports.
- Add AppleSmartBatteryPack normalization with synthetic coverage; macOS 27 hardware validation remains pending.
- Introduce a dependency-free Swift package, automated tests, app packaging, CI, and documentation.

## 0.1.0

- Initial local battery dashboard, menu bar monitor, recent history, and CSV export.
