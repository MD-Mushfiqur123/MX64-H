# MXISA-64 Base ISA — H-series Baseline Proposal

**Document ID:** MXISA64-BASE-001  
**Revision:** 0.2 proposal  
**Status:** H1 candidate; not frozen for external software compatibility  
**Endianness:** Little-endian  
**Instruction length:** Fixed 32 bits in the base profile  
**Architectural width:** 64 bits

## 1. Architectural state

- `PC`: 64-bit byte address; base instructions advance by four bytes.
- `x0`–`x31`: 32 × 64-bit integer registers. `x0` is constant zero.
- `f0`–`f31`: reserved for the separately specified floating-point profile; no FP opcode is assigned in this base document.
- Arithmetic is modulo \(2^{64}\), unless an instruction explicitly traps.
- Memory is byte-addressed and little-endian.
- Base profile requires naturally aligned accesses. Misaligned loads/stores trap.
- Virtual addresses are 48-bit canonical in the initial target; translation details are in `MXISA64_PRIVILEGED_PROFILE.md`.

## 2. Encoding formats

All instruction words are little-endian in memory. Bit numbering below uses bit 31 as the most significant bit.

| Format | Fields |
|---|---|
| R | `[31:26] major`, `[25:21] rd`, `[20:16] rs1`, `[15:11] rs2`, `[10:6] shamt/reserved`, `[5:0] minor` |
| I | `[31:26] major`, `[25:21] rd`, `[20:16] rs1`, `[15:12] minor`, `[11:0] imm12` |
| S | `[31:26] major`, `[25:21] rs2`, `[20:16] rs1`, `[15:12] minor`, `[11:0] imm12` |
| B | `[31:26] major`, `[25:21] rs2`, `[20:16] rs1`, `[15:12] minor`, `[11:0] signed displacement units` |
| U | `[31:26] major`, `[25:21] rd`, `[20:17] minor`, `[16:0] upper immediate` |
| J | `[31:26] major`, `[25:0] signed displacement units` |

For I/S/B formats, the four-bit `minor` selector chooses an operation within the major opcode group; the remaining 12-bit field is the immediate. I/S immediates are signed 12-bit byte offsets unless an instruction says otherwise. For B and J, displacement units are four bytes and the effective target is `PC + sign_extend(displacement) * 4`; the low two target bits are zero. U-format `minor` selects LUI or AUIPC; its 17-bit immediate is placed in bits `[63:47]` of the 64-bit result, with low 47 bits zero. CSR instructions use a dedicated I-format subencoding: `[15:4]` is the 12-bit CSR address and `[3:0]` is the CSR operation/source mode; the CSR subformat does not use the generic 12-bit immediate.

The 6-bit major opcode namespace is partitioned as follows. For I/S/B/U groups, the `minor` selector is the format-specific field shown above. The opcode CSV records major, format, and minor values. Unassigned values are reserved and must trap as illegal instructions.

| Major | Class | Format | Assigned operations |
|---:|---|---|---|
| 0x00 | System/NOP | R | NOP, HALT, ECALL, EBREAK, MRET (minor field) |
| 0x01 | Integer register-register | R | ADD, SUB, AND, OR, XOR, NOR, SLT, SLTU |
| 0x02 | Shift | R | SLL, SRL, SRA |
| 0x03 | Multiply/divide | R | MUL, MULH, MULHU, DIV, DIVU, REM, REMU |
| 0x04 | Integer immediate | I | ADDI, ANDI, ORI, XORI, SLTI, SLTIU |
| 0x05 | Shift immediate | I | SLLI, SRLI, SRAI |
| 0x06 | Load | I | LB, LBU, LH, LHU, LW, LWU, LD |
| 0x07 | Store | S | SB, SH, SW, SD |
| 0x08 | Conditional branch | B | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| 0x09 | Direct jump | J | JAL; destination/link register is implicit x1 in this baseline |
| 0x0A | Indirect jump | I | JALR |
| 0x0B | Upper immediate | U | LUI, AUIPC |
| 0x0C | Ordering | R | FENCE, FENCE.I |
| 0x0D | CSR | I | CSRRW, CSRRS, CSRRC and immediate forms |
| 0x0E | Atomic | R | LR.D, SC.D, AMOSWAP.D, AMOADD.D, AMOXOR.D, AMOAND.D, AMOOR.D |
| 0x0F | FP scalar | Extension | Reserved for separate F-profile specification |
| 0x10 | SIMD/vector | Extension | Reserved; no base instruction assigned |
| 0x11–0x3E | Reserved | — | Illegal instruction |
| 0x3F | Custom/platform | Extension | Disabled in base profile; implementation-specific only under an extension ID |

### Minor opcode allocation

Within R-format groups, `minor[5:0]` selects the operation. The initial allocation is:

| Minor | Integer ALU | Shift | M-extension | System |
|---:|---|---|---|---|
| 0 | ADD | SLL | MUL | NOP |
| 1 | SUB | SRL | MULH | HALT |
| 2 | AND | SRA | MULHU | ECALL |
| 3 | OR | — | DIV | EBREAK |
| 4 | XOR | — | DIVU | MRET |
| 5 | NOR | — | REM | — |
| 6 | SLT | — | REMU | — |
| 7 | SLTU | — | — | — |

For system group 0x00, `rd`, `rs1`, `rs2`, `shamt` must be zero unless the operation's later privileged specification defines them. For all R-format operations, unused fields must be zero; nonzero reserved bits trap.

For R-format groups, the selector is the low six-bit minor field. For I/S/B/U groups, the selector is the format-specific minor field shown above. The CSR subformat is separately encoded as described above. The machine-readable opcode table in `docs/isa/MXISA64_OPCODE_TABLE.csv` is the candidate source for software tooling. This document remains a proposal pending full consistency review.

## 3. Integer semantics

- ADD/SUB/ADDI wrap modulo \(2^{64}\).
- AND/OR/XOR/NOR are bitwise.
- SLT/SLTI compare signed two's-complement values; SLTU/SLTIU compare unsigned values. Result is zero or one.
- Shift amount is `rs2[5:0]` for register shifts and `imm16[5:0]` for immediate shifts.
- SRA sign-fills; SRL zero-fills.
- MUL returns low 64 product bits. MULH returns high 64 bits of signed × signed; MULHU returns high 64 bits unsigned × unsigned.
- DIV/DIVU/REM/REMU corner cases shall be fixed as follows for the baseline: divide-by-zero returns all-ones quotient and original dividend remainder; signed minimum divided by -1 returns signed minimum quotient and zero remainder. These cases do not trap.

## 4. Load/store semantics

Effective address is `GPR[rs1] + sign_extend(imm12)`, modulo \(2^{64}\), followed by canonicality, translation, permission, and alignment checks.

- LB/LH/LW sign-extend 8/16/32 bits to 64.
- LBU/LHU/LWU zero-extend.
- LD loads 64 bits.
- SB/SH/SW/SD store the low 8/16/32/64 bits of `GPR[rs2]`.
- Misalignment raises a precise address-misaligned exception before any architectural side effect.
- A store is speculative in the store queue but may become globally visible only after retirement authorization.

## 5. Control flow

- Conditional branch target: `PC + sign_extend(imm12) * 4`.
- JAL target: `PC + sign_extend(imm26) * 4`; writes `PC+4` to x1.
- JALR target: `(GPR[rs1] + sign_extend(imm12)) & ~3`; writes `PC+4` to `rd`.
- Branches and jumps must be resolved against the architectural semantics, independent of prediction.
- Any misprediction flushes younger speculative work and restores a valid rename checkpoint.

## 6. Ordering and atomics

The initial product is single-core. Ordinary loads/stores are ordered according to the program order contract selected for H1. The conservative baseline is sequentially consistent architectural behavior for ordinary memory operations; the implementation may execute speculatively only if retirement/forwarding/replay logic preserves that observable order. FENCE is a full memory-ordering barrier. FENCE.I synchronizes prior stores to instruction memory with subsequent instruction fetch.

Atomic operations are a gated extension: they require an indivisible aligned 64-bit transaction and a precisely specified reservation/coherence contract. They are not considered implemented merely because opcode names are listed. H1 cannot close until atomic semantics and external memory-system assumptions are fully specified; otherwise the atomic major opcode remains reserved.

## 7. Exceptions

Precise exception classes:
- Illegal instruction / reserved encoding.
- Instruction address misaligned.
- Instruction access fault.
- Breakpoint.
- Environment call.
- Load/store address misaligned.
- Load/store access fault.
- Instruction/load/store page fault when translation is enabled.

Trap cause values, delegation, privilege transition, `EPC`, `CAUSE`, `TVAL`, and trap-vector behavior are defined in the privileged profile. A trap is taken at retirement; no younger instruction may commit.

## 8. Freeze blockers

This proposal is not frozen until:
1. The candidate format/selector map is independently reviewed and exhaustively round-trip tested.
2. CSR subencoding is verified against the 12-bit CSR address and operation/source mode.
3. Atomic extension and memory model are either fully specified or removed from base.
4. Privilege levels, reset vector, trap CSR map, and translation format are reviewed.
5. ABI register roles, stack alignment, ELF machine ID, relocation types, and calling convention are approved.
6. Encoder, decoder, disassembler, and reference model pass exhaustive encoding consistency checks.
