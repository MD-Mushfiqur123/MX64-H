# MX64-H Phase 37.3 Execution Report

## Delivered

Implemented sequence-based LSU selective recovery across:
- `rtl/memory/mx64_lsu_rob_adapter.sv`
- `rtl/memory/mx64_lsu_cache_subsystem.sv`
- `rtl/memory/mx64_lsu_pipeline.sv`
- `rtl/memory/memory_ordering_unit.sv`
- `rtl/memory/lsu_reference_lifecycle.sv`
- Compatibility tie-off in `rtl/core/mx64_frontend_dispatch.sv`

Added `docs/PHASE37_3_LSU_SELECTIVE_RECOVERY.md` and `scripts/check_phase37_3.py`.

## Validation actually run

- Phase37.3 static contract: PASS 10/10.
- Repository structure: PASS (55 required files).
- RTL source contracts: PASS (31 module declarations, 223 checks).
- Phase37.1 static contracts: PASS 18/18.
- Phase37.2 static contracts: PASS 9/9.
- No HDL compile, elaboration, simulation, formal proof, or synthesis was run. The environment has no HDL tools installed; installation was not attempted.

## Correctness contract

Recovery removes only store entries with sequence strictly greater than the resolving branch sequence. It releases both store source references. In-flight loads are retained until their non-cancelable cache response arrives; younger loads are marked killed and their ROB/PRF result is suppressed. The response is consumed even if it coincides with recovery. Committed stores are retained. `flush_all` remains a distinct destructive flush.

## Remaining blockers

1. The functional `mx64_top` is still not integrated; real branch recovery must drive the adapter pins.
2. No HDL compile/simulation/formal verification has been performed.
3. Cache remains single-outstanding and has no cancellation protocol.
4. Translation, page permissions, TLB/page walker, and page faults are not implemented.
5. MXISA-64 memory opcode size/signedness mapping remains provisional.
6. No claim of end-to-end CPU functionality is made.
