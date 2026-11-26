# MX64 Master Work Breakdown Structure (WBS)

**Project rule:** Simulation and formal verification are deliberately deferred until the implementation and integration work packages are complete. During the build phase, do source review, interface review, lint-oriented static checks only if explicitly allowed later; do not call these simulation.

**Architecture target:** MX64, custom 64-bit ISA, 2-wide speculative out-of-order core, in-order retirement, FPGA-first integration followed by ASIC feasibility.

**Status convention**
- `EXISTING-DRAFT`: RTL/documentation exists but has not been established as correct.
- `NEW-TASK`: must be designed and implemented.
- `INTEGRATION`: connect completed blocks and define end-to-end contracts.
- `VERIFY-LATER`: reserved for the final verification campaign.

## 0. Project governance and architecture control

### 0.1 Requirements baseline
- 0.1.1 Define product goals: embedded/application class, expected software, performance goals, power envelope, area envelope.
- 0.1.2 Define target platforms: simulation reference platform, FPGA board, ASIC target class.
- 0.1.3 Define non-goals for first silicon: SMT, out-of-order vector, coherent multicore, hypervisor, speculative MMIO.
- 0.1.4 Maintain a requirement-to-module traceability matrix.
- 0.1.5 Assign a stable ID to every architectural requirement and interface.

**Deliverables:** `docs/architecture/REQUIREMENTS.md`, traceability matrix, glossary.

### 0.2 Architecture decision records
- 0.2.1 Freeze XLEN=64 and instruction alignment.
- 0.2.2 Freeze custom ISA identity and encoding policy.
- 0.2.3 Decide endianness, atomicity, alignment and exception rules.
- 0.2.4 Decide virtual address canonicality and physical address width.
- 0.2.5 Decide memory consistency model.
- 0.2.6 Decide interrupt controller and external bus contract.
- 0.2.7 Decide reset, boot and debug entry behavior.
- 0.2.8 Record every trade-off in an ADR; never silently change a frozen decision.

**Deliverables:** `docs/architecture/decisions/ADR-*.md`.

## 1. ISA and programmer-visible architecture

### 1.1 Integer ISA
- 1.1.1 Define R/I/S/B/U/J or custom formats with non-overlapping encoding.
- 1.1.2 Define ADD/SUB, logical operations, compare, shifts, rotates if desired.
- 1.1.3 Define immediate widths and sign/zero extension.
- 1.1.4 Define branch and jump target calculation.
- 1.1.5 Define load/store widths: byte, halfword, word, doubleword.
- 1.1.6 Define signed and unsigned load behavior.
- 1.1.7 Define alignment fault behavior.
- 1.1.8 Define illegal instruction behavior and reserved encoding policy.
- 1.1.9 Define fences and instruction synchronization.
- 1.1.10 Define atomic extension or explicitly defer it.

### 1.2 Privileged ISA
- 1.2.1 Define M, S and U modes and legal transitions.
- 1.2.2 Define CSR address map, read/write masks and privilege checks.
- 1.2.3 Define synchronous exception causes and trap-value semantics.
- 1.2.4 Define external, timer and software interrupts.
- 1.2.5 Define trap vector modes and return instructions.
- 1.2.6 Define page-table formats, page sizes and translation modes.
- 1.2.7 Define TLB invalidation and address-space identifiers.
- 1.2.8 Define protection model (PMP/PMA-equivalent).
- 1.2.9 Define counters and event selectors.
- 1.2.10 Define debug mode, breakpoints, single-step and halt/resume.

### 1.3 Software contract
- 1.3.1 Assembler syntax and encoding reference.
- 1.3.2 Linker script and executable image format.
- 1.3.3 Boot ROM ABI and reset vector.
- 1.3.4 Calling convention and ABI.
- 1.3.5 Minimal runtime and bare-metal example programs.
- 1.3.6 Later: compiler backend/toolchain support.

**Gate G1:** ISA and privileged architecture documents are internally consistent and frozen before dependent RTL is considered complete.

## 2. Core-wide interfaces and protocols

### 2.1 Common types
- 2.1.1 Define `mx64_pkg`: XLEN, VA/PA widths, instruction width, exception types.
- 2.1.2 Define `uop_t` with PC, instruction, source/destination tags, immediate, FU class, ROB ID, branch metadata and exception metadata.
- 2.1.3 Define ROB tag with slot index plus sufficiently wide generation/epoch.
- 2.1.4 Define transaction IDs for cache, TLB and external bus requests.
- 2.1.5 Define privilege and memory-attribute types.

### 2.2 Protocols
- 2.2.1 Define ready/valid semantics for all decoupled channels.
- 2.2.2 Define cancellation and flush semantics.
- 2.2.3 Define reset values and reset release sequencing.
- 2.2.4 Define backpressure propagation.
- 2.2.5 Define ordering guarantees for multiple completion ports.
- 2.2.6 Define request/response ID lifetime and stale-response handling.
- 2.2.7 Define clock-domain assumptions; no CDC unless explicitly designed.

### 2.3 Global control
- 2.3.1 Single redirect arbiter with age/priority policy.
- 2.3.2 Single exception/interrupt arbitration policy.
- 2.3.3 Single global squash contract.
- 2.3.4 Pipeline drain protocol for fences, debug and privilege changes.
- 2.3.5 Deadlock-avoidance rules for cyclic backpressure.

**Gate G2:** every module port is described by a protocol contract before integration.

## 3. Frontend

### 3.1 PC and redirect
- 3.1.1 Sequential PC generator.
- 3.1.2 Redirect sources: branch mispredict, exception, interrupt, debug, return.
- 3.1.3 Redirect arbitration and epoch increment.
- 3.1.4 Prevent stale fetch responses from entering the queue after redirect.

### 3.2 Branch prediction
- 3.2.1 BTB lookup/update and tag validation. `mx64_branch_predictor.sv` is an initial draft.
- 3.2.2 BHT direction counters.
- 3.2.3 Return address stack.
- 3.2.4 Optional global history/gshare after baseline.
- 3.2.5 Predictor update only from resolved branches.
- 3.2.6 Checkpoint prediction metadata per fetched instruction.
- 3.2.7 Measure aliasing and prediction accuracy only during final evaluation.

### 3.3 Fetch path
- 3.3.1 I-TLB request/response contract.
- 3.3.2 L1I request/response interface.
- 3.3.3 Outstanding fetch transaction table.
- 3.3.4 Fetch packet formation, up to two instructions per cycle.
- 3.3.5 Fetch FIFO with PC and prediction metadata.
- 3.3.6 Instruction boundary and cross-line handling.
- 3.3.7 Access fault and page fault metadata.

### 3.4 Decode frontend
- 3.4.1 Decoder for every frozen opcode.
- 3.4.2 Illegal/reserved instruction detection.
- 3.4.3 Immediate generator.
- 3.4.4 Micro-op generation.
- 3.4.5 Multi-uop instruction policy (avoid in first version unless required).
- 3.4.6 Two-wide decode ordering and partial-lane acceptance.

**Gate G3:** frontend emits correctly ordered, tagged micro-ops and discards all younger stale responses after redirect.

## 4. Rename and physical register management

### 4.1 Physical register file
- 4.1.1 Integer PRF with two or more read ports per issue needs and sufficient write ports.
- 4.1.2 x0 mapping/constant-zero semantics.
- 4.1.3 Writeback arbitration and same-cycle read-after-write behavior.
- 4.1.4 Optional ECC/parity.
- 4.1.5 Banked PRF evaluation if port count becomes too expensive.

### 4.2 Rename map
- 4.2.1 Architectural-to-physical map table.
- 4.2.2 Busy/ready table.
- 4.2.3 Two-wide intra-packet dependency forwarding (lane 1 sees lane 0 rename).
- 4.2.4 Old physical destination capture.
- 4.2.5 No-destination instruction handling.

### 4.3 Free list and recovery
- 4.3.1 Allocation only on accepted atomic dispatch.
- 4.3.2 Return stale physical destination only at retirement.
- 4.3.3 Branch checkpoint allocation and release.
- 4.3.4 Restore map and free-list state after misprediction.
- 4.3.5 Prevent double-free, leak and reallocation of live physical registers.
- 4.3.6 Define behavior when free list is exhausted.
- 4.3.7 Define checkpoint exhaustion behavior.

### 4.4 Rename integration
- 4.4.1 Connect PRF read ports and busy table to issue/operand read.
- 4.4.2 Connect ROB stale destination to commit-time reclaim.
- 4.4.3 Connect branch checkpoint metadata to ROB.
- 4.4.4 Define squash of younger rename allocations.

**Gate G4:** every live architectural mapping references a live physical register; every allocated physical register has exactly one owner or a documented transient state.

## 5. Dispatch, scheduling and execution

### 5.1 Dispatch
- 5.1.1 Reserve ROB slots and issue queue entries atomically.
- 5.1.2 Route uops by execution class.
- 5.1.3 Handle one-lane and two-lane acceptance.
- 5.1.4 Handle resource-full stalls without side effects.
- 5.1.5 Define kill/flush interaction with same-cycle dispatch.
- 5.1.6 Connect old destination and checkpoint metadata.

### 5.2 ROB
- 5.2.1 ROB allocation and circular pointers.
- 5.2.2 Robust tag generation/epoch to reject stale completions.
- 5.2.3 Out-of-order completion.
- 5.2.4 In-order retirement up to two instructions.
- 5.2.5 Exception-at-head semantics.
- 5.2.6 Branch metadata and mispredict recovery.
- 5.2.7 Store commit handshake.
- 5.2.8 Reclaim old physical register on retirement.
- 5.2.9 Flush younger entries without corrupting older entries.

### 5.3 Issue queues
- 5.3.1 Integer queue.
- 5.3.2 Branch queue or shared integer queue policy.
- 5.3.3 Load queue issue eligibility.
- 5.3.4 Store queue dispatch/commit path.
- 5.3.5 Wakeup from all writeback ports.
- 5.3.6 Oldest-ready selection or documented age policy.
- 5.3.7 Multi-issue arbitration.
- 5.3.8 Queue flush and transaction-tag invalidation.

### 5.4 Execution units
- 5.4.1 ALU: all arithmetic/logical/shift/compare operations.
- 5.4.2 Branch unit: compare, target, mispredict and redirect.
- 5.4.3 Pipelined multiplier.
- 5.4.4 Iterative or pipelined divider.
- 5.4.5 CSR execution unit with serialization rules.
- 5.4.6 Result arbitration and multiple writeback ports.
- 5.4.7 Exception and replay metadata.
- 5.4.8 Execution backpressure and kill behavior.

**Gate G5:** no uop can execute without a live ROB identity; every completion is matched to exactly one live ROB entry.

## 6. Load/store and memory ordering

### 6.1 LSU address generation
- 6.1.1 Effective address generation.
- 6.1.2 Access size, sign extension and byte enables.
- 6.1.3 Alignment checks.
- 6.1.4 Translation and protection request.
- 6.1.5 Access fault propagation.

### 6.2 Load queue
- 6.2.1 Allocate at dispatch.
- 6.2.2 Track age, address-known, data-returned and ROB identity.
- 6.2.3 Forward from older stores with byte-mask merge.
- 6.2.4 Detect unknown older store address conflicts.
- 6.2.5 Replay loads after ordering violation.
- 6.2.6 Cancel killed loads and reject stale responses.

### 6.3 Store queue and buffer
- 6.3.1 Capture address and data speculatively.
- 6.3.2 Hold stores until retirement authorizes commit.
- 6.3.3 Move committed stores into non-speculative store buffer.
- 6.3.4 Drain in defined order to cache/fabric.
- 6.3.5 Handle partial writes and alignment.
- 6.3.6 Never expose a squashed store to memory.

### 6.4 Memory model
- 6.4.1 Define load-load, load-store, store-load and store-store ordering.
- 6.4.2 Define fence semantics.
- 6.4.3 Define atomic operation serialization.
- 6.4.4 Define MMIO/non-idempotent access policy.
- 6.4.5 Define cacheability and shareability attributes.

**Gate G6:** no architectural memory side effect from an unretired or squashed store.

## 7. Cache and external memory fabric

### 7.1 L1 instruction cache
- 7.1.1 Set/way organization and line size.
- 7.1.2 Tag/data arrays and valid bits.
- 7.1.3 Refill request and response tracking.
- 7.1.4 Miss handling and fetch replay.
- 7.1.5 Flush/fence.i behavior.

### 7.2 L1 data cache
- 7.2.1 Read/write hit path.
- 7.2.2 Write-through vs write-back decision.
- 7.2.3 Dirty eviction/writeback.
- 7.2.4 Store buffer interface.
- 7.2.5 Miss-status holding registers (MSHRs).
- 7.2.6 Replay and backpressure.

### 7.3 L2 and fabric
- 7.3.1 Shared L2 interface and arbitration.
- 7.3.2 Memory controller protocol.
- 7.3.3 AXI-like adapter or custom fabric freeze.
- 7.3.4 Transaction IDs, ordering and response routing.
- 7.3.5 Timeout/error handling.
- 7.3.6 ECC/parity boundary.

**Gate G7:** request/response IDs remain unique until completion; cache misses and evictions preserve data and ordering.

## 8. MMU and protection

- 8.1 Freeze virtual-memory format and page sizes.
- 8.2 Implement ITLB and DTLB.
- 8.3 Implement TLB lookup, refill and replacement.
- 8.4 Implement hardware page-table walker.
- 8.5 Implement page permission checks.
- 8.6 Implement ASID and TLB invalidation.
- 8.7 Implement PMP/PMA-equivalent checks.
- 8.8 Check page-walker accesses against physical protection.
- 8.9 Integrate page/access faults with ROB precise exceptions.
- 8.10 Define physical-mode boot and transition into virtual memory.

**Gate G8:** instruction/data translations, protection faults and invalidation semantics are consistent.

## 9. Privilege, interrupts, debug and platform

### 9.1 CSR/trap
- 9.1.1 Complete CSR address map and masks.
- 9.1.2 Trap entry/return and privilege stack.
- 9.1.3 Synchronous exception arbitration.
- 9.1.4 Interrupt pending/enable/priority.
- 9.1.5 Interrupt sampling at precise boundaries.
- 9.1.6 Counter inhibit and event selection.
- 9.1.7 Serialize architecturally sensitive CSR operations.

### 9.2 Debug
- 9.2.1 Debug halt request and drain policy.
- 9.2.2 Resume and single-step.
- 9.2.3 Hardware breakpoints.
- 9.2.4 Debug register access.
- 9.2.5 Debug exception and reset behavior.

### 9.3 Platform
- 9.3.1 Reset controller and clock/reset contract.
- 9.3.2 Boot ROM and reset vector.
- 9.3.3 Timer and interrupt source interface.
- 9.3.4 UART/GPIO or simple bring-up peripherals.
- 9.3.5 External bus and memory map.
- 9.3.6 FPGA top-level wrapper and constraints.

**Gate G9:** bare-metal boot, traps, interrupts and debug are architecturally specified and integrated.

## 10. Reliability, performance and optional extensions

- 10.1 Performance counters for cycles, retired instructions, branch misses, cache misses and stalls.
- 10.2 Assertions and error reporting in RTL.
- 10.3 Parity/ECC for PRF, queues and caches where justified.
- 10.4 Clock gating strategy and safe enable generation.
- 10.5 FPU extension (separate scope).
- 10.6 Vector/SIMD extension (separate scope).
- 10.7 Atomic extension (if not in base ISA).
- 10.8 Coherent multicore/LLC (future generation; not first-core requirement).

## 11. Full integration and source review — before simulation

- 11.1 Instantiate frontend, decode, rename, dispatch, backend, ROB, LSU, MMU, caches, CSR and platform interfaces.
- 11.2 Review all module port contracts.
- 11.3 Review combinational loops and ready/valid dependencies.
- 11.4 Review reset and flush fanout.
- 11.5 Review transaction ID lifetime.
- 11.6 Review exception/interrupt priority.
- 11.7 Review physical-register ownership and reclamation.
- 11.8 Review store side-effect boundary.
- 11.9 Review deadlock risks and resource reservation.
- 11.10 Update architecture and interface diagrams.
- 11.11 Freeze RTL feature set for verification.

**Gate G10:** no known missing architectural connection; all interfaces have documented semantics; implementation source review signed off.

## 12. Final verification campaign — simulation starts here

This is intentionally the first stage where simulator execution begins.

- 12.1 Install/pin simulator versions and record reproducible build commands.
- 12.2 Compile/lint all RTL and resolve all errors/warnings.
- 12.3 Unit tests for every leaf block.
- 12.4 Protocol tests for ready/valid, reset, flush and backpressure.
- 12.5 Rename/free-list/PRF invariants.
- 12.6 ROB wraparound, generation and precise retirement.
- 12.7 Dual-wide dispatch atomicity and resource exhaustion.
- 12.8 Branch prediction, redirect and recovery tests.
- 12.9 Mul/div latency, kill and result routing tests.
- 12.10 LSU forwarding, replay, alignment and ordering tests.
- 12.11 Cache refill, eviction, dirty writeback and miss concurrency.
- 12.12 TLB/PTW, permissions and page-fault tests.
- 12.13 CSR/trap/interrupt/debug tests.
- 12.14 Full-system bare-metal boot and software tests.
- 12.15 Constrained-random regression and coverage closure.
- 12.16 Formal properties for local invariants and selected end-to-end guarantees.
- 12.17 Regression triage; never delete/relax a failing test to claim a pass.

**Gate G11:** agreed functional coverage and regression criteria pass. A single smoke test is not sufficient.

## 13. Synthesis, FPGA and ASIC

- 13.1 Synthesis scripts and constraints.
- 13.2 Memory macro inference/mapping review.
- 13.3 Area report and critical path analysis.
- 13.4 Clock/reset and CDC/RDC review.
- 13.5 FPGA implementation and board bring-up.
- 13.6 DFT/scan/MBIST plan.
- 13.7 Floorplan and power grid.
- 13.8 Placement and clock-tree synthesis.
- 13.9 Routing and extraction.
- 13.10 STA across PVT corners.
- 13.11 IR drop, EM, antenna and DRC/LVS.
- 13.12 Signoff and GDS release.

**Gate G12:** no PPA, FPGA, or ASIC signoff claim without actual tool reports.

## Global completion criteria

The CPU is not called complete until:
1. ISA and privileged architecture are frozen.
2. All required blocks exist and are integrated.
3. No unresolved critical source-review issue remains.
4. Full simulation regression passes.
5. Selected formal properties pass.
6. Bare-metal software runs through the defined boot path.
7. Synthesis and timing reports are reviewed.
8. FPGA or ASIC target evidence matches the claimed deliverable.

## Engineering rule

Build the entire planned design first, but keep each subsystem modular and reviewable. Deferring simulation does not mean deferring architecture reviews, interface contracts, or correctness reasoning. Never invent passing results.


## High-performance target update

The normative performance ambition is now defined in `MX64_H_HIGH_PERFORMANCE_ARCHITECTURE.md`. Earlier 2-wide/80-physical-register/48-entry-ROB values are prototype-era parameters only and must not be treated as the final high-performance target. The H-series gates in that document supersede the earlier generic width assumptions. No simulation is scheduled before H8 source integration/review.
