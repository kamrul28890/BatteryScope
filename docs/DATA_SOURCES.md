# Data sources and units

BatteryScope uses read-only macOS sources as the current user. The IOKit service and field names below are implementation details, not stable Apple guarantees across every model.

| Measurement | Source | Interpretation |
| --- | --- | --- |
| System charge | `CurrentCapacity / MaxCapacity` | Percentage; never reuse `MaxCapacity` as mAh |
| Raw charge | `AppleRawCurrentCapacity / AppleRawMaxCapacity` | Independent raw percentage |
| Raw health | `AppleRawMaxCapacity / DesignCapacity` | Calculated percent, without clamping away values above 100 |
| Nominal health | `NominalChargeCapacity / DesignCapacity` | Independent calculated percent; legacy v0.1 `fullMAh` retains nominal meaning |
| macOS health | `pmset -g ps -xml`, explicit maximum-capacity percent key | Queried asynchronously with a three-second deadline and cached for 30 minutes; unavailable if not returned |
| Capacity | Explicit raw/nominal/design keys | mAh only; no guessing from percentage-valued fields |
| Wh | mAh × current pack voltage / 1000 | Approximation; unavailable when voltage is missing |
| Battery temperature | `Temperature / 100` | °C, observed scale |
| Virtual temperature | `VirtualTemperature / 100` | Separate reading, not silently substituted |
| Reported current | `Amperage / 1000` | Signed A; source averaging period is unspecified |
| Instantaneous current | `InstantAmperage / 1000` | Signed A; unsigned two's-complement values decoded explicitly |
| Battery power | Selected current × `Voltage / 1000` | Signed W; positive into battery, negative out |
| Adapter rating | `AdapterDetails.Watts` or first raw adapter record | Rated W, not instantaneous consumption |
| System load/input | `PowerTelemetryData.SystemLoad/SystemPowerIn` | Reported mW converted to W; separate from battery power |
| Charge estimate | `AvgTimeToFull`, then `TimeRemaining` | Valid minutes only while charging |
| Depletion estimate | IOPS seconds, then `AvgTimeToEmpty`, then `TimeRemaining` | Valid minutes only while on battery |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` | Does not imply optimized battery charging |
| Condition | IOPS `BatteryHealth` | Preserved text; non-Good/Normal values shown on Overview |
| Fault status | `PermanentFailureStatus` | Raw word plus observed bits 0–13; unknown bits retained as warnings |
| Not-charging reason | `ChargerData.NotChargingReason` | Raw code; no unsupported diagnosis |

Time values of 0, negative, nonfinite, or 65535 are unavailable. Connected-but-not-charging states do not display a charge/depletion estimate. `FullyCharged` is kept distinct.

## Registry paths

The normal service is `AppleSmartBattery`. An `AppleSmartBatteryPack` class or named direct child is read when available. Pack `EntryChildren.BatteryData`, pack `BatteryData`, and direct fields are normalized over the parent before decoding. Explicit pack fields win over parent fields. Missing raw/nominal fields remain missing.

This path is synthetically tested from the observed structure. It has not been validated on macOS 27 hardware. New structures fail to supply readings rather than causing fabricated values.

## Fault flags

The observed map is: 0 external input; 1 safety overvoltage; 2 charge over-temperature; 3 discharge over-temperature; 4 cell imbalance; 5 charge FET; 6 discharge FET; 7 data flush; 8 permanent AFE communication; 9 periodic AFE communication; 10 charge safety overcurrent; 11 discharge safety overcurrent; 12 open thermistor; 13 fuse blown. These are battery-reported flags and may vary by firmware. They are not an independent hardware diagnosis.

## Firmware lifetime information

`BatteryData.LifetimeData` (or a direct `LifetimeData`) provides supported fields:

- Min/max/average temperature: observed tenths of °C.
- Min/max pack voltage: observed mV → V.
- Maximum charge/discharge current: signed mA → absolute A.
- Operating-time and temperature-sample counters: retained in **raw units** where model-specific duration conversion is unverified.

Zero/invalid temperature placeholders are not treated as measurements. Missing extrema are unavailable. No operating days or temperature-recording days are inferred from unknown counter scales.

There is no direct SMC connection and no wall-power estimate. Unsupported energy counters are not relabeled as watts. No private powerlog database fallback is used.
