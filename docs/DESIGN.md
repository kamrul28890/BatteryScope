# Design decisions

A local REA/Ghidra audit of a reference battery utility helped identify several gaps in the original prototype. This repository contains an original implementation using macOS readings; it contains no decompiled source or reference binaries.

1. **Keep provenance visible.** Raw capacity, nominal capacity, and macOS maximum-capacity percentage are independent. The user chooses the dashboard source, and comparison remains visible. Missing selected data is never silently replaced.
2. **Normalize once.** Registry/pack formats are normalized at the reader boundary. Decoding and UI use the same typed reading and units.
3. **Prefer public read-only access.** Standard power-source APIs, registry reads, and `pmset` are enough for the supported scope. Private powerlog databases, elevated privileges, and undocumented SMC commands are not needed.
4. **Be precise about uncertainty.** Time values are state-dependent estimates. Battery, input, and adapter powers have different meanings. Wh is voltage-dependent. Unverified firmware counters stay raw.
5. **Separate time scales.** Recent minute telemetry answers charge/session questions; daily health/cycle snapshots and notes answer longer-term questions. Both are local and independently exportable.
6. **Preserve existing data.** Legacy nominal readings keep their meaning. Daily history seeds from old minute records. Corrupt history is not overwritten.
7. **Test boundaries.** Synthetic fixtures verify signed sensor values, source separation, format variants, unavailable data, history migration, and alerts. Hardware and UI verification remain separate from parser tests.

Native analysis does not establish full product parity, runtime behavior, or physical sensor accuracy. The local investigation assets and third-party tools are excluded from publication.
