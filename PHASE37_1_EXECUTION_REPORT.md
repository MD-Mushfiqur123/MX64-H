# MX64-H Phase 37.1 — Research-Guided Memory Dispatch Separation

## Research basis
Reviewed out-of-order pipeline/ROB, issue-queue wakeup/select, LSQ organization,
and store-commit references. The implementation applies split memory issue,
program-order admission into the existing LSQ/LSU, explicit operand wakeup and
reference lifetime, and separate memory completion into the ROB. It does not
copy BOOM's ISA or adopt speculative/multi-outstanding loads.

See `docs/PHASE37_1_RESEARCH_AND_ARCHITECTURE.md` for source-by-source notes,
decisions, non-adoptions and the known-gap register.

## Implemented
- Added `mx64_memory_issue_queue.sv` with oldest-first in-order memory issue,
  wakeup capture, source-reference accounting, recovery/flush cleanup and stable
  ready/valid output under backpressure.
- Routed load/store UOPs to that memory queue instead of the integer ALU queue.
- Propagated memory dispatch through `mx64_control_subsystem`.
- Integrated memory queue with `mx64_frontend_dispatch`.
- Added external memory result writeback to PRF and memory-queue wakeup.
- Added a dedicated memory-to-ROB completion lane beyond integer and branch
  completion lanes. Store completion may complete ROB without a PRF write;
  successful load completion can also write PRF; fault completion carries
  exception metadata and must not write PRF.
- Merged memory queue reference acquire/release events into the physical
  register reference tracker.
- Added directed testbench source for ordering, wakeup/refcount, stall stability,
  flush/recovery, duplicate-wakeup collision priority and ROB completion lane.
- Added research and interface-map documents.

## Validation actually executed
See `PHASE37_1_VALIDATION.txt`.
- Repository checks: PASS (55 required-file checks).
- RTL source contracts: PASS (223 text-based checks; 30 unique declarations).
- Phase 36 static guards: PASS (6/6).
- Phase 37.1 static guards: PASS (18/18).
- ABI: PASS (8 checks); ISA audit: PASS (55 opcode rows / software round-trip).
- Eight standalone software regression suites: PASS.
- FPGA/ASIC platform-template structure checks: PASS (not hardware readiness).

## Not claimed / blocking gaps
- No HDL compilation, elaboration, simulation, formal proof or synthesis pass.
- Directed SystemVerilog testbenches are authored but unexecuted.
- The LSU response-to-ROB adapter is not implemented. The future adapter must
  retain `rob_tag`, `dst_tag`, `writes_dst`, and sequence identity from issued
  memory UOP until matching lifecycle response, map errors to precise ROB
  exceptions, and suppress killed/stale responses after recovery.
- The memory UOP's size/signedness must be decoded from a frozen MXISA-64 opcode
  contract. Current ISA specification remains a proposal; do not guess this.
- Branch execution remains an external interface.
- `rtl/core/mx64_top.sv` remains an explicitly non-functional shell.

## Input snapshot and provenance
This package was built from the durable Phase 36.2 archive
`MX64H_PHASE36_2_STORE_ERROR_FIX.zip`, SHA-256
`131542f06f152953fe08338cb28133030530691349d2779afa0c7a0a4b34eb9b`.
Later Phase 36.3/36.4/37.0 bundle files were not present as readable archive
inputs in the active workspace. Their unarchived changes are not claimed as
merged into this Phase 37.1 package.
