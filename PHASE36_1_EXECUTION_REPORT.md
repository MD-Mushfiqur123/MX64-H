# MX64-H Phase 36.1 — Directed Verification and Error Contracts

**Status:** Verification assets and interface contracts added; HDL execution remains unavailable.

## Added assets

- `verification/unit/tb_issue_queue_same_cycle_wakeup.sv`
- `verification/unit/tb_physical_register_reference_tracker.sv`
- `verification/unit/tb_cache_hierarchy_error_contract.sv`
- `verification/PHASE36_DIRECTED_TESTS.md` with source lists and simulator commands
- `docs/PHASE36_CACHE_ERROR_CONTRACT.md` defining dirty-victim writeback and committed-store lifecycle semantics

## Error policy decisions

1. A failed dirty-victim writeback fails the pending demand request, does not proceed to refill, and must preserve the dirty victim line.
2. `store_commit_ready` means cache acceptance only. The store lifecycle identity remains reserved until the matching cache response is consumed. A store error must be delivered to a platform fatal/asynchronous-store-error sink; ordinary speculative replay is not permitted.
3. Current interfaces lack an error-cause field, generation ID, and fatal-error sink. Those remain integration work; no RTL interface expansion is claimed here.

## Checks actually run in this workspace

- `scripts/check_repo.py`: PASS (55 required files)
- `scripts/check_rtl_sources.py`: PASS (29 modules / 222 source-contract checks)
- `scripts/check_phase36_stabilization.py`: PASS (5/5 static guards)
- ABI: PASS (8 checks)
- ISA audit: PASS (55 opcodes / canonical round-trips)
- Assembler, architecture, ELF64, multi-section, smoke, boot-image, platform, load-image: PASS (9 standalone scripts)

## Not run

No `iverilog`, `vvp`, `verilator`, or `yosys` executable was available. The three newly added testbenches have not been parsed, compiled, elaborated, or simulated. No HDL PASS is claimed. The tests are first-pass directed assets and may need simulator-specific syntax correction.

## Open blockers

- `mx64_top` remains non-functional.
- No system-level fatal/asynchronous store-error sink or transaction generation ID exists.
- No end-to-end LSU subsystem test proves lifecycle-slot retention through store response consumption.
- Dirty-victim writeback and pending-invalidation testbenches still require execution.
