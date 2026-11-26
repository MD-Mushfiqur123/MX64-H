# Open Architecture Decisions

These are explicit blockers or future freeze items. Agents must not silently invent values.

## Blocking before full RTL implementation

1. Commercial foundry, process node, PDK revision and authorized access.
2. Exact instruction encoding, opcode allocation and instruction length policy.
3. Privilege levels and CSR/trap architecture.
4. Page-table format, page sizes, TLB organization and page-walker contract.
5. Memory consistency model and fence semantics.
6. Misaligned access behavior (baseline proposal: precise exception).
7. Interrupt model and interrupt retirement boundary.
8. Debug architecture, trace interface and halt semantics.
9. Cache exact sizes/associativity/latencies after SRAM macro evaluation.
10. External memory/interconnect protocol and transaction ID limits.
11. Clock frequency, voltage, temperature and PVT corners.
12. Scan, MBIST, JTAG, DFT and safety requirements.
13. Whether target is a reusable CPU IP block or standalone SoC/chip.

## Proposed defaults pending approval

- Single core for first silicon.
- Little-endian.
- 48-bit canonical virtual addresses.
- Physical address width parameter `PADDR_W`.
- 64-byte cache lines.
- Private 32 KiB L1I and 32 KiB L1D; shared 256 KiB L2 target.
- Static not-taken branch predictor for first functional bring-up.
- No atomics in initial release.
- Misaligned accesses trap precisely.
- 2-wide dispatch and retirement.
- In-order retirement and no speculative external store visibility.

## Decision process

Every decision must have:
- ID and owner;
- alternatives considered;
- rationale;
- affected specs/modules/tests;
- compatibility impact;
- approval date and version.
