# Validation and scope

## Automated coverage

The Swift Testing suite covers source separation, sensor units, signed two's-complement current, charge/depletion estimate precedence and sentinel values, fault labels/unknown bits, battery-pack normalization, explicit macOS health parsing, configurable alerts, CSV quoting, legacy reading migration, daily notes, restart persistence, and preservation of corrupt files.

CI runs synthetic tests, builds the app, and verifies its local signature. The live battery probe is opt-in and does not require a battery on CI runners.

## Hardware scope

Live read-only checks have run on an Apple silicon Mac notebook on macOS 26.7. Both capacity/current/temperature fields were available. The macOS health query returned a separate percentage. These readings validate data access on that machine, not calibration accuracy or every supported Mac.

Version 0.2.0 passed all 12 tests with the live probe enabled on the development Mac. The release app bundle built and passed local signature verification.

The app builds for the host architecture. Intel hardware behavior remains unverified. macOS 27 battery-pack normalization is covered by synthetic fixtures; validation on real macOS 27 hardware is pending.

## Interactive checks

Before treating a build as a polished release, verify:

- Dashboard, navigation, source choices, unavailable fields, and menu bar.
- Charging/discharging/not-charging transitions and sleep/wake refresh.
- System notification permission, foreground/background delivery, and threshold rearming.
- CSV save dialogs and file contents, history charts, and note editing.
- Long-running battery and resource behavior.

Computer-use permission was unavailable in the development session. The build and data path were checked programmatically; interactive behavior is not claimed as verified.

## Distribution

Version 0.2.0 is a locally signed development build. Public binaries are architecture-specific and not Apple notarized. The source build is reproducible using the scripts; binary byte-for-byte reproducibility is not claimed.

There is no iPhone/iPad connection, SSD diagnosis, custom printing, direct SMC access, or charging-control helper in this version.
