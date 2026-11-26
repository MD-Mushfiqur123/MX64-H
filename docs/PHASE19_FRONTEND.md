# MX64-H Phase 19 — Frontend Fetch/Decode Slice

## Delivered RTL

- `rtl/frontend/mx64_fetch_unit.sv`: one-outstanding-request instruction fetch
  with response holding under downstream backpressure, reset vector input,
  redirect handling, and a stale-response drain path.
- `rtl/frontend/mx64_instruction_decoder.sv`: fixed 32-bit base decoder using
  the current MXISA64 opcode table and baseline field layouts. It emits
  `decoded_uop_t`, including illegal-instruction and instruction-misaligned
  exceptions.
- `rtl/frontend/mx64_frontend.sv`: connects fetch, branch predictor and
  decoder, and maps instruction access faults into decode exception metadata.

## Important protocol assumptions

The fetch interface supports one outstanding request and has no transaction
ID or explicit bus-cancel signal. Therefore, when a redirect occurs while a
request is outstanding, the frontend drains and discards that response before
issuing from the redirect PC. This prevents an old response from being
mistaken for the new-path response.

The predictor is queried using the current fetch request address. The fetch PC
is held stable while a request is outstanding, so the prediction used on the
response is for the corresponding request.

## Deliberate scope limits

This phase creates a reusable frontend block; it does not connect the frontend
to `mx64_control_subsystem` or turn `mx64_top` into a working CPU. The current
decoder maps the base integer, load/store, branch, jump, system and fence
families into the existing uop shape. The backend still lacks complete
operation metadata and execution support for all multiply/divide, atomic,
CSR, floating-point and privileged instructions. Such operations must not be
assumed executable merely because their opcode appears in the ISA table.

Instruction access faults are carried to the decode uop. Instruction page
translation, cache/TLB refill, multi-request fetch queues, dual-wide decode,
and a full frontend redirect/flush integration remain future work.

## Verification

`make check`, the software test suites, and the RTL source-contract checks
provide repository/software/static-source validation only. No SystemVerilog
compiler, elaborator, simulator, formal tool, or synthesis tool was available
in this environment. HDL verification remains deferred as requested.
