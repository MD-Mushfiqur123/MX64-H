# MX64-H Phase 37.4 — Research Review & Recovery Hardening

## Research basis

Reviewed MIPS R10000 User's Manual (1996), Alpha 21264 architecture paper (1998), Berkeley BOOM implementation documentation (rename/issue/execute/ROB), and Park/Ooi/Vijaykumar MICRO-36 2003 LSQ paper. The architecture decisions and direct links are recorded in `docs/PHASE37_4_RESEARCH_AND_RECOVERY_HARDENING.md`.

## Changes in this pass

1. Connected branch-mispredict recovery into the LSU physical-reference lifecycle in `rtl/core/mx64_frontend_dispatch.sv`.
2. Added the real store sequence number to the frontend/LSU lifecycle boundary; removed the constant-zero age placeholder.
3. Converted sequence-age comparisons to wrap-safe signed-difference helpers in:
   - `rtl/memory/memory_ordering_unit.sv`
   - `rtl/memory/lsu_reference_lifecycle.sv`
   - `rtl/memory/mx64_lsu_rob_adapter.sv`
4. Added research/design rationale and explicit verification boundaries.
5. Updated static source-contract checks to validate the new comparison helpers.

## Validation actually run

- `scripts/check_phase37_4.py`: PASS 10/10.
- `scripts/check_phase37_3.py`: PASS 10/10.
- `scripts/check_repo.py`: PASS (55 required files).
- `scripts/check_rtl_sources.py`: PASS (31 module declarations, 223 static contracts).
- `tools/mx64/abi_check.py`: PASS (8 checks).
- `tools/mx64/audit_isa.py`: PASS (55 opcode rows and canonical encoder/decoder round-trips).
- `tools/mx64/assembler_tests.py`: PASS.
- `tools/mx64/architecture_tests.py`: PASS.
- `tools/mx64/elf64_tests.py`: PASS.
- `tools/mx64/multisection_tests.py`: PASS.

These are software/static checks. No HDL compiler, elaborator, simulator, formal engine, synthesis tool, or physical-design flow was run. No SystemVerilog compile or functional simulation pass is claimed.

## Remaining blockers (not complete)

- `rtl/core/mx64_top.sv` remains an empty shell. Frontend/dispatch and LSU/ROB adapter are not yet connected in a functional top.
- Branch execution is still an external boundary; no complete branch execution unit is integrated into the top.
- Physical address translation/TLB/page walker and permission/page-fault path are absent.
- The cache path is single-outstanding and lacks cancellation; killed load response identity must remain retained.
- Draft memory opcode size/signedness mapping needs ISA freeze.
- The complete core still requires HDL compile, elaboration, directed and randomized simulation, formal checks, synthesis and timing analysis.

## Sequence-number invariant

The signed-difference ordering helpers are correct only while fewer than half the sequence-number space of live operations can separate compared entries. Sequence numbers must not wrap ambiguously while entries remain live. This is an explicit design invariant, not a proof that wrap can never occur.
