# MX64-H Phase 37.2 — LSU-to-ROB Transaction Adapter

## Implemented in this increment
- Added `rtl/memory/mx64_lsu_rob_adapter.sv` (standalone transaction adapter).
- Added draft MXISA-64 load/store opcode size and signedness decode.
- Added cache-independent alignment precheck and precise load/store misalignment completion.
- Retained full ROB tags for accepted loads and stores, including generation bits.
- Added load response -> ROB completion and successful load -> PRF writeback mapping.
- Added load access-fault completion with PRF write suppression.
- Added stale load-response suppression after precise flush while retaining cache
  transaction identity until the response is drained.
- Added speculative store capture and commit authorization matched by full ROB tag.
- Added post-retirement committed-store error reporting.
- Preserved already committed store transaction identity across precise flush.
- Added `retire_gate_ready` to `mx64_control_subsystem` and
  `mx64_frontend_dispatch`, allowing a future wrapper to gate ROB retirement on
  store commit acceptance.
- Added design/contract documentation and static contract checker.

## Validation actually executed
- `scripts/check_phase37_2.py`: PASS, 9/9 static contract checks.
- `scripts/check_repo.py`: PASS.
- `scripts/check_rtl_sources.py`: PASS.
- `scripts/check_phase37_1.py`: PASS.
- ABI checker: PASS.
- ISA audit: PASS.
- Assembler, architecture, ELF64 and multisection software tests: PASS.
- A broader rerun was interrupted during the smoke-test invocation; no result is
  claimed for that invocation. Phase 37.1's prior recorded smoke-test pass is
  preserved in its own validation report.
- HDL compiler/simulator/formal/synthesis tools were not available. No RTL parse,
  elaboration, simulation, formal or synthesis pass is claimed.

## Not complete / blockers
- Adapter is a standalone module; not instantiated into a functional `mx64_top`.
- Top-level wiring must connect memory issue, memory completion, PRF writeback,
  retirement candidates, retirement gate, translation and external memory bus.
- Branch-mispredict recovery is not propagated into LSU/cache structures. This
  remains a correctness blocker for speculative memory operations younger than
  a mispredicted branch.
- Translation, permissions, TLB/page walks and page-fault generation remain
  external.
- ISA size/signedness decode is based on a draft opcode table and remains
  provisional until ISA freeze.
- The cache subsystem remains single-outstanding. Adapter conservatively blocks
  new memory issue while a committed store is in flight.
- The current top-level CPU is not functional and no full-core simulation has run.
