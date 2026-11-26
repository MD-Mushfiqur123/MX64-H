# MXISA-64 Privileged Architecture Profile — Proposal

**Revision:** 0.1  
**Status:** Design baseline only; privileged RTL is not complete.

## 1. Privilege model

Initial profile proposes two privilege levels:
- M (Machine): highest privilege; reset entry and platform firmware execute here.
- U (User): unprivileged application execution.

Supervisor mode is not included in the first profile. Adding an OS-facing S-mode requires a separate architecture decision and a page-table/interrupt delegation review. Debug mode is an external debug state, not a normal software privilege level.

## 2. CSR address map proposal

CSR instructions use the dedicated I-format subencoding: bits [15:4] carry the 12-bit CSR address and bits [3:0] select CSR operation/source mode. The generic I-format immediate is not used by CSR operations. Access permissions are enforced by current privilege and per-CSR policy. The exact four-bit operation/source map must be finalized before RTL implementation.

| CSR | Address | Access | Purpose |
|---|---:|---|---|
| mstatus | 0x300 | R/W | Global machine status and interrupt enable |
| misa | 0x301 | R/O | Implemented ISA extensions |
| medeleg | 0x302 | R/W | Reserved until S-mode exists |
| mideleg | 0x303 | R/W | Reserved until S-mode exists |
| mie | 0x304 | R/W | Interrupt enable |
| mtvec | 0x305 | R/W | Trap vector base/mode |
| mcounteren | 0x306 | R/W | User counter access control |
| mscratch | 0x340 | R/W | Machine scratch |
| mepc | 0x341 | R/W | Exception PC |
| mcause | 0x342 | R/W | Trap cause |
| mtval | 0x343 | R/W | Trap value |
| mip | 0x344 | R/W | Pending interrupt state |
| mcycle | 0xB00 | R/O or privileged R/W policy TBD | Cycle counter |
| minstret | 0xB02 | R/O or privileged R/W policy TBD | Retired instruction counter |

Unimplemented CSR accesses trap as illegal instruction. Read-only writes trap. Reset values must be explicitly set in the platform specification.

## 3. Synchronous trap behavior (proposal)

A synchronous trap is taken at the retirement boundary:
1. Stop committing younger instructions. A lane-1 fault waits until all older
   lane-0 work has retired and the fault becomes the ROB head.
2. Record the faulting instruction PC in `mepc` (the base encoding is 32-bit,
   so the low two bits are cleared).
3. Record the architectural cause code in `mcause`.
4. Record the faulting address or instruction metadata in `mtval` when defined.
5. Update machine status and privilege state according to the selected profile.
6. Redirect fetch to `mtvec` using the selected direct/vectored policy.
7. Flush speculative frontend/backend state and restore the committed rename map
   and a free-list bitmap reconstructed from that map.

The current cause-code proposal is:

| Exception class | `mcause` code |
|---|---:|
| Instruction address misaligned | 0 |
| Instruction access fault | 1 |
| Illegal instruction / reserved encoding | 2 |
| Breakpoint | 3 |
| Load address misaligned | 4 |
| Load access fault | 5 |
| Store/AMO address misaligned | 6 |
| Store/AMO access fault | 7 |
| Environment call from U-mode | 8 |
| Environment call from M-mode | 11 |
| Instruction page fault | 12 |
| Load page fault | 13 |
| Store/AMO page fault | 15 |

`mtval` proposal: illegal instruction records the 32-bit instruction word in
its low bits; address-misaligned, access-fault and page-fault classes record the
faulting virtual address; environment-call and breakpoint traps record zero.
The faulting instruction PC is always carried separately in `mepc`.

Interrupt priority, external interrupt controller interface, NMI behavior,
nested trap policy, and complete privilege-state update remain open decisions.
The table is a proposal and is not a frozen compatibility commitment.

## 4. Address translation

The initial target uses 48-bit virtual and 48-bit physical address widths in the configuration draft. This is a sizing target, not a complete page-table architecture. Before enabling translation, freeze:
- Page-table levels and entry format.
- Page sizes and superpage rules.
- PTE permissions, accessed/dirty update policy.
- ASID width and TLB tagging.
- Page-table walker memory interface and fault reporting.
- TLB shootdown/invalidation contract.
- Canonical-address definition.
- Physical memory attributes and I/O ordering.

Until these are frozen and verified, the platform may boot with translation disabled. A future OS-capable profile must not infer compatibility with an existing ISA page-table format.

## 5. Debug and performance monitoring

- EBREAK requests a precise debug entry or breakpoint trap according to debug configuration.
- External debug halt must stop at a recoverable architectural boundary.
- Single-step must retire no more than one instruction before re-entry.
- `mcycle` counts core cycles; `minstret` counts architecturally retired instructions.
- Event counters and event IDs are TBD; counter overflow behavior must be specified.
- Debug authentication, trace export, and trigger resources are platform integration decisions.
