# BatteryScope

[![Build and test](https://github.com/kamrul28890/BatteryScope/actions/workflows/ci.yml/badge.svg)](https://github.com/kamrul28890/BatteryScope/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](Package.swift)

A native, local-only Mac battery dashboard that makes its data sources visible. Compare **raw, nominal, and macOS-reported health**, track charge and daily health history, and understand the readings behind the numbers.

Built with SwiftUI, Charts, and IOKit. No accounts, external packages, administrator access, or network telemetry.

## Features

| Area | Included |
| --- | --- |
| Live status | System and raw charge percentage, charge/discharge state, cycles, Low Power Mode, device-reported condition and fault warnings |
| Health sources | Raw full capacity / design capacity, nominal full capacity / design capacity, and the separate macOS-reported maximum-capacity percentage |
| Power sources | Reported and instantaneous current and battery wattage; pack voltage; system load/input telemetry; adapter rated output |
| Temperature | Battery sensor and virtual temperature, selectable on the dashboard |
| Time estimates | macOS estimates with state-aware `TimeRemaining` fallbacks and explicit source labels |
| Lifetime | Firmware temperature/voltage extrema, maximum charge/discharge current, and raw operating-time/sample counters |
| History | Fourteen days of minute samples; up to five years of daily health/cycle snapshots with notes; charge and health charts |
| Notifications | Configurable low charge, charge target, and remaining-time alerts; thresholds rearm after recovery |
| Preferences | Source choices, mAh/estimated Wh, 5/10/30/60-second refresh, and menu bar status |
| Export | Recent readings and daily health/notes as separate CSV files, including independent source fields |

Missing fields stay **unavailable**. Selecting a missing source never silently switches to a different measurement.

## Get started

Requirements: a Mac notebook running **macOS 14 or later**, with **Swift 6+** available through Xcode or Apple Command Line Tools. Local hardware validation currently covers Apple silicon on macOS 26.7.

```sh
git clone https://github.com/kamrul28890/BatteryScope.git
cd BatteryScope
./build.sh
open build/BatteryScope.app
```

The build script uses Swift Package Manager, creates a normal `.app` bundle, and applies a local ad-hoc signature. No dependencies are downloaded. This is a development build, not an Apple-notarized distribution.

Alternatively, open `Package.swift` in Xcode. `swift build` builds the executable; use `./build.sh` for the app bundle and notification identity.

Create an architecture-specific archive:

```sh
./scripts/package.sh
```

Archives and SHA-256 checksums appear in `dist/`. They contain only BatteryScope, not development/reference tools.

## Use

- **Overview:** current charge, estimate, selected health/temperature/power sources, recent charge chart, and warnings.
- **Sources & power:** compare all available measurements and choose the dashboard sources.
- **Battery details:** capacities, cycle count, condition, raw fault/reason codes, and Low Power Mode.
- **Lifetime:** firmware statistics and explicitly labeled raw counters.
- **History:** charge charts, daily health trends, notes, and CSV exports.
- **Preferences:** sample interval, units, and custom notification thresholds. Notifications are off initially.

The menu bar item shows current status and opens the dashboard. Sampling stops when you quit. Power-source changes and wake events trigger a refresh; minute samples are saved at most once a minute.

For a one-shot registry read without saving history:

```sh
build/BatteryScope.app/Contents/MacOS/BatteryScope --diagnostics
```

This explicit diagnostic command prints supported battery fields to stdout. Keep personal diagnostic output out of public issues.

## Data and privacy

History stays in `~/Library/Application Support/BatteryScope/`:

- `history.json`: recent minute samples, retained for 14 days.
- `daily-health.json`: daily snapshots and notes, up to 1,827 days.

Preferences use macOS UserDefaults. Legacy v0.1 readings are loaded and used to seed daily history; their original nominal-health interpretation is preserved. Corrupt history files are left untouched and saving pauses with an error instead of overwriting them.

The app does not collect device/battery serial numbers, contact a server, read the private powerlog database, or control charging. macOS notification permission is optional. CSV export writes only where you choose.

## Understanding differences

Raw, nominal, and macOS-reported health are **different measurements**, and may disagree. Capacity varies with conditions and battery calibration. Wh is an approximation based on the **current pack voltage**, not a rated design-energy value. Current × voltage measures net battery flow, not wall power. Adapter wattage is its reported rating.

Remaining times come from macOS and change with workload. A connected battery that is not charging can have several causes; BatteryScope reports that state without claiming every pause is optimized charging.

See [data sources and units](docs/DATA_SOURCES.md) and [scope and validation](docs/VALIDATION.md). Firmware lifetime-counter units and some new-platform behavior remain unverified; raw counters are not presented as invented hours/days.

## Development and testing

```sh
./test.sh
./build.sh
# Optional, read-only hardware test on a Mac notebook:
BATTERYSCOPE_LIVE_TEST=1 ./test.sh
```

Tests use Swift Testing (bundled with Swift 6). They cover independent source selection, signed current, estimate precedence/sentinels, lifetime units, fault flags, pack normalization, macOS-health parsing, alerts, legacy migration, notes, CSV quoting, and corrupt-history preservation. The live test is skipped by default on CI.

```text
Sources/BatteryCore/      Measurements, read-only providers, alerts, persistence, CSV
Sources/BatteryScope/     SwiftUI dashboard, Charts, menu bar, notifications
Tests/BatteryCoreTests/   Synthetic fixtures and optional live probe
Resources/               App bundle metadata
scripts/                 Packaging
```

## Origins and scope

BatteryScope is an independent implementation. [coconutBattery](https://www.coconut-flavour.com/coconutbattery/) provided a feature reference; [REA](https://github.com/morluto/rea) with Ghidra supported a local, read-only native audit. No third-party code, assets, binaries, or decompiled output are distributed in this repository. [Design decisions](docs/DESIGN.md) summarize the resulting measurement choices.

Current scope is this Mac. iPhone/iPad connectivity, SSD diagnostics, custom printing, direct SMC commands, and hardware charging controls are not included. AppleSmartBatteryPack normalization has synthetic tests; macOS 27 hardware validation remains pending. No claim of full parity or perfect sensor accuracy is made.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md) · [MIT license](LICENSE)
