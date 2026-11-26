# MX64 Full-Core Architecture — Design Target M3

**Status:** architectural target and implementation plan; not a claim that all blocks are implemented.

## 1. Design intent

MX64 is a custom 64-bit application-class processor intended to evolve toward FPGA prototyping and then an ASIC implementation. It is not binary-compatible with RISC-V. RISC-V and open-source cores are used as engineering references only.

The design target is a two-wide, speculative, out-of-order core with in-order retirement and precise architectural state.

## 2. Top-level block inventory

| Subsystem | Required blocks | Current status |
|---|---|---|
| Frontend | PC generator, I-TLB, I-cache, fetch queue, predecode, branch predictor, BTB, return stack | Branch predictor first RTL draft added; rest planned |
| Decode | instruction aligner, decoder, illegal-instruction detector, micro-op generation | Types exist; complete decoder not integrated |
| Rename | map table, free list, physical register file, busy/ready tracking, checkpoint/restore | Building blocks exist; end-to-end recovery incomplete |
| Dispatch | dual-wide atomic resource reservation, ROB allocation, issue-queue enqueue | Controller draft exists; not verified |
| Scheduling | integer issue queue, memory issue queue, wakeup/select, age ordering | Integer queue draft exists; memory queues planned |
| Execution | ALU, branch unit, pipelined multiply, iterative divide, LSU, optional FPU/vector | ALU exists; branch/muldiv/LSU/FPU implementation pending |
| Commit | ROB, in-order retire, exception selection, stale physical-register reclaim | ROB draft exists; stale-register reclaim not end-to-end |
| Memory | load queue, store queue, store buffer, forwarding, replay, ordering checks | Not implemented as a complete subsystem |
| Translation/protection | ITLB, DTLB, page-table walker, PMP-like protection, PMA | Not implemented |
| Cache | private L1I/L1D, shared L2 interface, refill/writeback, miss-status holding registers | Shell only |
| Privilege | privilege modes, CSR file, trap entry/return, interrupts, counters | Initial machine CSR draft added; integration incomplete |
| Debug | halt/resume, breakpoints, single-step, debug register access | Planned |
| Platform | AXI-like memory interface, interrupt controller interface, timer, reset/clock, boot ROM | Not frozen |
| Reliability | parity/ECC, error reporting, timeout handling, performance counters | Planned |
| Physical design | DFT scan, MBIST, clock/reset tree, floorplan, SRAM macros, timing closure | Flow contract only |

## 3. Proposed pipeline

1. **F0 — PC generation:** choose sequential PC, predicted target, trap vector, or redirect.
2. **F1 — instruction fetch:** translate VA, access I-cache, track outstanding requests.
3. **F2 — align and fetch queue:** form up to two instruction slots; preserve PC and prediction metadata.
4. **D — decode:** classify instruction, source/destination registers, immediate, exception, execution class.
5. **R — rename:** map architectural sources to physical tags; allocate new destination tags; update map in program order.
6. **DP — dispatch:** atomically reserve ROB and the appropriate issue queue(s).
7. **IS — issue:** select ready operations using operand-ready bits and wakeup broadcasts.
8. **EX — execute:** ALU, branch, multiply/divide, address generation, load/store.
9. **WB — writeback:** broadcast physical destination tag and result; wake dependent operations; mark ROB complete.
10. **C — commit:** retire up to two completed instructions in order; update architectural state; reclaim stale physical registers.
11. **REC — recovery:** on misprediction or exception, squash younger work, restore rename state, and restart at the correct PC.

Stage count is a logical decomposition, not a fixed clock-stage commitment. Physical pipelining will be chosen after synthesis and timing analysis.

## 4. Initial microarchitecture parameters

- XLEN: 64
- Architectural integer registers: 32; x0 hardwired to zero
- Physical integer registers: 80 (initial experiment; may be raised after rename pressure analysis)
- ROB: 48 entries
- Dispatch / retire target: 2 instructions per cycle
- Integer issue queue: 16 entries
- Load queue / store queue target: 16 entries each
- Fetch buffer target: 8 packets
- Branch predictor target: 64-entry direct-mapped BTB with 2-bit saturating direction counters (first draft RTL added)
- VA width: 48 bits; canonical-address rule must be frozen in the ISA/privileged spec
- PA width: platform-defined; current 40-bit value is a compile scaffold only
- Cache line target: 64 bytes; L1/L2 capacity and associativity remain tunable parameters

These are design hypotheses. They must be stress-tested for queue-full conditions, rename exhaustion, branch-heavy workloads, and memory-level parallelism before being frozen.

## 5. ISA and architectural contract

The ISA specification must define:
- instruction formats and opcode map;
- arithmetic overflow and shift semantics;
- branch and jump target formation;
- load/store sizes, sign extension, alignment, and endianness;
- atomic memory operations and fences;
- privileged instructions and CSR access;
- synchronous exceptions and asynchronous interrupts;
- virtual-memory modes, page sizes, canonical VA rules, and TLB shootdown;
- debug behavior and performance-counter semantics;
- memory consistency model and ordering rules.

Do not borrow an instruction encoding implicitly from another ISA. Every encoding and visible behavior must be explicitly specified in `docs/ISA_SPEC.md`.

## 6. Speculation and precise state

- Rename removes WAR/WAW name dependencies; RAW dependencies remain through physical tags.
- Every dispatched instruction receives one unique live ROB identity.
- Completion may occur out of order; retirement is strictly in order.
- Stores may execute address/data generation speculatively, but globally visible store effects occur only after retirement and memory-order checks.
- Loads may execute speculatively only when their memory type permits it; MMIO/non-idempotent accesses must not be speculated.
- A branch checkpoint must include enough rename/free-list state to recover without double allocation or leaking physical registers.
- Exceptions become architectural only when the faulting instruction reaches the ROB head.
- A redirect must invalidate younger frontend, decode, rename, issue, and execution state according to a single age-based squash contract.

## 7. Memory subsystem

The memory subsystem is decomposed into:
- LSU address-generation units;
- load queue with dependency tracking and replay;
- store queue with address/data capture;
- store buffer for committed stores;
- store-to-load forwarding and byte-mask merging;
- load/store ordering checks and fence handling;
- DTLB and page-table walker;
- PMA/PMP checks before external side effects;
- private L1I and L1D;
- shared L2 interface and external memory fabric.

Non-idempotent MMIO regions require conservative handling: speculative reads may have side effects. The PMA map therefore needs explicit executable, cacheable, and non-idempotent attributes.

## 8. Privilege, traps, and interrupts

The first implementation target is M-mode only, followed by U-mode and S-mode only after trap/return and memory protection are verified. The CSR draft in `rtl/csr/mx64_csr_file.sv` is a starting point, not a complete privileged architecture. It does not yet arbitrate asynchronous interrupts, enforce all CSR read/write masks, or integrate a page-table walker.

Trap handling requirements:
- capture faulting PC, cause, and trap value;
- update privilege and interrupt-enable stack;
- redirect fetch to the configured trap vector;
- prevent younger instructions from committing;
- support precise return to the saved PC;
- distinguish interrupt causes from synchronous exceptions.

## 9. Verification strategy

Use independent reference models and directed/randomized tests. Minimum gates:
1. unit tests for each leaf module;
2. protocol assertions for every ready/valid interface;
3. rename/ROB/issue queue invariants;
4. branch misprediction and exception recovery tests;
5. load/store forwarding, replay, and ordering tests;
6. cache refill/eviction/dirty-writeback tests;
7. privilege/CSR/trap tests;
8. architectural instruction tests against an independent ISA model;
9. constrained-random and coverage closure;
10. formal proofs for bounded local invariants and selected end-to-end properties;
11. synthesis, timing, CDC/RDC, DFT, and physical signoff.

A structural Python checker is not an RTL test. A passing leaf test is not full-core verification.

## 10. Implementation sequence

- M3.0: frontend contract, fetch queue, branch predictor, redirect protocol.
- M3.1: complete decode and illegal-instruction path.
- M3.2: physical-register busy table, rename checkpoint and recovery.
- M3.3: ROB identity/generation redesign and stale-register reclamation.
- M3.4: branch execution, redirect, and squash.
- M3.5: multiplier/divider and execution backpressure.
- M4.0: load/store queues, forwarding, replay, and store commit.
- M4.1: CSR/trap/interrupt integration and privileged ISA freeze.
- M4.2: TLB/PTW/protection.
- M5.0: L1I/L1D controllers and refill/writeback.
- M5.1: shared L2 interface and memory fabric.
- M6.0: debug, performance counters, ECC/parity, DFT.
- M7.0: full-core regression, formal, synthesis and FPGA prototype.
- M8.0: selected PDK integration, physical design and signoff.

## 11. Reference architecture study

The design decomposition is informed by:
- Berkeley BOOM frontend/fetch-buffer, rename, issue, ROB, and speculative execution documentation;
- OpenHW CVA6 application-core documentation for pipeline, branch prediction, LSU, TLB/PTW, PMP/PMA, CSR and AXI integration;
- the official RISC-V privileged architecture as a reference for privilege/trap concepts only.

MX64 remains a custom ISA and must not claim compatibility with those projects.
