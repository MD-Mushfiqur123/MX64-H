# MX64-H Phase 36 Execution Report

**Result:** Partial stabilization delivered; CPU integration and HDL verification remain blocked.  
**Baseline:** Phase-35 LSU/cache subsystem snapshot.  
**Workspace:** isolated Phase-36 copy; original repository was not edited.

## Source changes carried in this Phase-36 workspace

- `rtl/scheduler/issue_queue.sv`: same-cycle wakeup bypass for accepted enqueue lanes; acquire refs only for still-unready operands; store the bypassed uop.
- `rtl/rename/physical_register_reference_tracker.sv`: preserve initial architectural identity-map reference counts during `clear_all`; suppress reclaim pulse during clear.
- `rtl/memory/cache_hierarchy.sv`: latch invalidation requests while busy; block new requests until deferred invalidation is serviced while idle.
- `scripts/check_rtl_sources.py`: update the invalidation contract check for pending-invalidation semantics.
- `scripts/check_phase36_stabilization.py`: add five static regression guards.
- `docs/PHASE36_STABILIZATION.md` and `verification/PHASE36_REAUDIT.md`: document scope, findings and remaining work.

## Checks executed

| Check | Result |
|---|---|
| `scripts/check_repo.py` | PASS — 55 required files |
| `scripts/check_rtl_sources.py` | PASS — 29 module declarations / 222 source-contract checks |
| `scripts/check_phase36_stabilization.py` | PASS — 5/5 static guards |
| ABI check | PASS — 8 checks |
| ISA audit | PASS — 55 opcode rows / encoder-decoder round trips |
| Assembler tests | PASS |
| Architecture tests | PASS |
| ELF64 tests | PASS |
| Multi-section tests | PASS |
| Boot-image tests | PASS |
| Platform tests | PASS |
| Load-image tests | PASS |
| Reference interpreter smoke test | PASS |
| FPGA and ASIC platform templates | PASS — structural templates only, not hardware-ready |
| Example ELF build | PASS — 8,608-byte ELF64 |
| Boot image pack/inspect | PASS — MXB, 8,608-byte payload, entry `0x10000` |
| Phase-36 SHA-256 manifest | PASS — 151 files (generated build/cache outputs excluded) |
| ZIP integrity | PASS — `unzip -t`, no compressed-data errors |

## Not run / not verified

No `iverilog`, `verilator`, or `yosys` executable was available in this environment. No HDL parsing, compilation, elaboration, simulation, formal verification, synthesis, place-and-route, timing analysis, or hardware test was performed. Existing `.sv` testbench files remain scaffolds and must not be described as executable verification coverage.

## Remaining blockers

1. `rtl/core/mx64_top.sv` remains an empty non-functional shell. No complete CPU is delivered.
2. The Phase-36 RTL changes are source-reviewed/static-checked only; directed HDL tests are still required.
3. Dirty victim writeback error attribution remains coupled to the active cache request response.
4. Store-order retirement occurs on cache request acceptance; later memory/cache errors still need a defined architectural policy and response lifecycle.
5. `mx64_rob_placeholder` remains as a legacy empty module pending source-list compatibility review.
6. Phase-35 manifest remains in the tree as historical evidence; Phase-36 has a separate clean manifest.

## Integrity

- `PHASE36_MANIFEST.sha256` covers source/documentation files and excludes `build/`, `.pytest_cache/`, `__pycache__/`, and `.pyc` artifacts.
- ZIP SHA-256 is recorded in the delivery message; ZIP integrity was checked with `unzip -t`.
- No claim of functional CPU completion or HDL verification is made.
