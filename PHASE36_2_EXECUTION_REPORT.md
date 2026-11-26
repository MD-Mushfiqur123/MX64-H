# MX64-H Phase 36.2 — Store Error Lifecycle Fix

## Implemented
- Added `store_error_valid`, `store_error_ready`, and
  `store_error_lifecycle_slot` to `mx64_lsu_cache_subsystem`.
- A committed-store error is independently presented to a platform error sink.
- The cache response handshake waits for BOTH the ordinary response consumer
  and the platform error sink to acknowledge the error.
- Added assertions and static source-contract checks for identity stability
  and acknowledgement gating.
- Updated the cache error contract and directed verification obligations.

## Explicitly unresolved
- No platform-level fatal/machine-check controller is connected.
- `mx64_top` remains a non-functional shell.
- No HDL simulator/compiler is available; no RTL compile, elaboration,
  simulation, formal, or synthesis pass is claimed.
- The new dual-handshake requires an executable subsystem-level testbench.
