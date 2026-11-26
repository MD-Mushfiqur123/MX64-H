# MX64-H H0/H1 Architecture Decisions

**Revision:** 0.1  
**Purpose:** Record default decisions and explicit freeze blockers.

## Accepted working decisions

| ID | Decision | Rationale | Status |
|---|---|---|---|
| ADR-H-001 | MXISA-64 is a new, non-compatible ISA. | Avoid accidental compatibility claims. | Accepted |
| ADR-H-002 | Base instruction length is fixed 32 bits. | Simpler fetch/decode and alignment. | Accepted proposal |
| ADR-H-003 | Base integer state is 32 × 64-bit GPRs; x0 is constant zero. | Simple compiler-visible model. | Accepted proposal |
| ADR-H-004 | Little-endian memory and ABI. | One unambiguous initial data layout. | Accepted proposal |
| ADR-H-005 | Single hardware thread for first implementation. | Reduces verification and coherence scope. | Accepted |
| ADR-H-006 | Out-of-order speculative execution with in-order retirement. | High-performance target with precise state. | Accepted |
| ADR-H-007 | No simulation/formal/synthesis execution until final integration/source-review gate. | Matches project sequencing requirement. | Accepted |
| ADR-H-008 | All performance/area/power numbers remain targets until measured. | Prevents unsupported performance claims. | Accepted |

## Decisions deliberately not frozen

1. Exact CSR instruction bit layout: current 16-bit immediate cannot simultaneously encode all CSR address, operation, source selector, and immediate forms without a subformat.
2. Atomic operations: require a defined reservation/coherence contract; keep outside base until platform memory system is specified.
3. Privilege model: M/U is a starting profile; OS-grade S-mode may be required. Decide based on intended software ecosystem.
4. Page tables: custom format vs compatibility format; choose only after privilege/OS requirements.
5. Interrupt architecture and external interrupt controller.
6. Floating-point formats, exception flags, rounding modes, and NaN behavior.
7. SIMD/vector model and context-switch state.
8. ELF machine ID, relocation numbers, dynamic linking, and syscall ABI.
9. Physical address width and memory map after platform integration.
10. Reset vector and boot ROM/firmware interface.

## Immediate engineering resolution

- Keep the new ISA document labelled proposal.
- Use opcode CSV as the candidate operation inventory, not yet the sole normative bit decoder.
- Do not update RTL decode to consume the proposed table until the selector-bit contradictions are resolved.
- First produce an encoding consistency audit, then revise ISA/encoder/model together.
