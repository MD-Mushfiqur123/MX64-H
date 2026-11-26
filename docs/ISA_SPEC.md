# MXISA-64 ISA Specification

Version: 1.0-draft — not frozen for software compatibility.

## 1. Architectural state

- 64-bit program counter.
- 32 integer architectural registers `x0`–`x31`, each 64 bits.
- `x0` reads as zero; writes are discarded.
- Little-endian byte-addressed memory.
- 48-bit canonical virtual addresses.
- Integer arithmetic wraps modulo 2^64 unless an instruction explicitly defines overflow behavior.
- Instructions are encoded in a 32-bit base format with reserved extension space. Exact bit encodings are intentionally not assigned until opcode allocation and assembler/disassembler review are complete.

## 2. Instruction classes

| Class | Proposed mnemonics | Semantics family |
|---|---|---|
| Integer register-register | ADD, SUB, AND, OR, XOR | 64-bit integer operations |
| Integer immediate | ADDI, ANDI, ORI, XORI | 64-bit operations with defined immediate extension |
| Shift | SLL, SRL, SRA | Shift amount uses low 6 bits |
| Multiply | MUL, MULHU, MULH | Low/high product variants |
| Divide/remainder | DIV, DIVU, REM, REMU | Signed/unsigned division |
| Load/store | LB, LBU, LH, LHU, LW, LWU, LD, SB, SH, SW, SD | Byte/half/word/doubleword accesses |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU | Conditional control flow |
| Jump | JAL, JALR | Link and indirect control flow |
| System | ECALL, EBREAK, MRET, HALT | Environment/debug/return controls |
| Ordering | FENCE, FENCE.I | Memory and instruction-fetch ordering |
| Atomic (later gate) | LR, SC, AMO* | Atomic memory operations |

These names are a proposed vocabulary, not a final encoding or a claim of compatibility with another ISA.

## 3. Encoding policy

The following must be completed before RTL decode implementation:
1. Opcode map and reserved opcode policy.
2. Register/immediate field layouts for R/I/S/B/U/J formats or an alternative.
3. Immediate widths and sign/zero extension per instruction.
4. Alignment rules and misaligned access behavior.
5. Illegal-instruction behavior.
6. Instruction length and extension mechanism.
7. CSR and system instruction encodings.
8. Atomic instruction encoding and memory ordering semantics.

A canonical 32-bit base encoding is preferred for fetch simplicity. Longer instructions are not included in v1.0 unless a separate extension proposal is approved.

## 4. Arithmetic semantics

- ADD/SUB: modulo-2^64 result.
- Logical operations are bitwise over 64 bits.
- SLL/SRL/SRA use `rs2[5:0]`.
- Signed comparisons interpret operands as two's-complement 64-bit integers.
- Unsigned comparisons interpret operands as unsigned 64-bit integers.
- Division by zero and signed overflow corner cases must have explicitly defined result/trap semantics before implementation.
- High-product signedness is defined independently for MULH and MULHU.

## 5. Memory semantics

- Effective address is computed using 64-bit arithmetic and then checked for canonicality and translation.
- Loads/stores support byte, halfword, word and doubleword sizes.
- Load sign/zero extension is instruction-specific.
- Store byte enables derive from access size and address offset.
- Misaligned accesses: baseline policy is precise address-misaligned exception; hardware support may be added by a later extension.
- Endianness is little-endian.

## 6. Control-flow semantics

- Branch target and jump target formulas are defined by the final encoding.
- Branches resolve in the branch execution unit.
- Link instructions write the sequential PC to the destination register.
- Misprediction recovery must restore the correct speculative rename state and restart fetch at the resolved target.

## 7. Memory ordering

A formal memory model must be selected before multicore/atomic implementation. The initial single-core baseline preserves program-visible ordering for ordinary memory operations and must not expose speculative stores. FENCE/FENCE.I semantics must be specified before software-visible release.

## 8. Exceptions and traps

Precise exceptions are mandatory. Exception classes include:
- Illegal instruction.
- Instruction address misaligned.
- Instruction access fault.
- Breakpoint.
- Environment call.
- Load/store address misaligned.
- Load/store access fault.
- Instruction/load/store page fault, if virtual memory is enabled.

The current synchronous cause-code and `mtval` proposal is recorded in
`docs/isa/MXISA64_PRIVILEGED_PROFILE.md`. It is not frozen: interrupt priority,
full privilege-state transitions, nested traps and debug entry remain open.

## 9. Compatibility

MXISA-64 is a new ISA. It is not binary-compatible with MXISA v0.1 or RISC-V. Any compatibility layer must be an explicit future project.
