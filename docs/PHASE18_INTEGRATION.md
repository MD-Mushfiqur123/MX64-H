# MX64-H Phase 18 — Control Subsystem Integration

## Delivered

Added `rtl/core/mx64_control_subsystem.sv`, a structural integration wrapper
connecting the existing two-wide dispatch controller (rename, checkpoint
manager, integer backend, ROB and issue-queue recovery) to the precise trap
controller.

The wrapper establishes these control paths:

- decoded uops and operand-read results enter the dispatch controller;
- control-transfer uops leave through a dedicated branch-unit handshake;
- branch resolution returns a full ROB tag, misprediction indication, actual
  next PC, and destination result value;
- retirement events pass through the trap controller's ready/valid boundary;
- accepted synchronous traps redirect to the supplied trap vector and assert
  a speculative flush;
- the flush restores rename/free-list state from the committed RAT and
  committed free bitmap exported by the dispatch controller.

## Deliberate external boundaries

This is **not a complete standalone CPU**. The instruction fetch/decode
frontend, physical register-file read/write data path, branch execution unit,
CSR state update, LSU, MMU/TLB, cache hierarchy, and SoC memory interface are
not instantiated by this wrapper. Their interfaces remain explicit so that
future integration does not silently invent protocols.

The wrapper takes `current_privilege` and `trap_vector` from a future CSR
boundary. It exports trap metadata and redirect but does not itself update
`mepc`, `mcause`, `mtval`, `mstatus`, or `minstret`.

## Verification status

The Python ISA/toolchain regression and repository static checks are run by
`make check` and `make test`. RTL static checks can verify source contracts
and structural connectivity but are not a substitute for SystemVerilog
elaboration, simulation, formal verification, or synthesis. Those HDL steps
remain intentionally deferred per project instruction.
