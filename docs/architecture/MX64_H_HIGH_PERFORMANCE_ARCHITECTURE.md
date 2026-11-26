# MX64-H: High-Performance Core Architecture Direction (Research Baseline)

**Document status:** proposal for architecture review. This is not a claim that MX64 has AMD Zen performance, transistor-level similarity, or completed RTL.

## 1. Objective and honesty boundary

MX64-H targets the engineering scope of a modern high-performance desktop/server CPU core: wide front end, speculative out-of-order execution, independent integer and floating-point domains, high-throughput load/store, virtual memory, coherent cache interfaces, precise exceptions, performance counters, and a scalable SoC boundary.

AMD Zen 4 is used as a public reference point because AMD published a processor optimization presentation containing a simplified Zen 4 microarchitecture diagram. AMD's internal implementation details remain proprietary. The public diagram is incomplete and must not be treated as a full implementation specification. MX64 is an independent custom ISA and microarchitecture.

## 2. Publicly documented reference facts

AMD's March 2024 GDC public presentation shows the following simplified Zen 4 facts:
- 32 KiB, 8-way instruction cache and branch prediction.
- Decode path: 4 instructions/cycle.
- Op-cache path: 9 macro-ops/cycle.
- Dispatch: 6 macro-ops/cycle.
- Separate integer and floating-point rename domains.
- Four integer scheduler blocks and two FP scheduler blocks in the diagram.
- Integer-side execution diagram includes ALU/branch and AGU resources.
- FP/SIMD side has a separate register file and execution resources.
- Load/store queue diagram lists 3 loads/cycle and 2 stores/cycle.
- 32 KiB, 8-way D-cache and 1 MiB, 8-way unified L2 in that diagram.
- Zen 4 improvements called out include a 6.75K-op cache, 1 MiB L2, improved load/store and branch prediction, and AVX-512 support.

These are slide-level public facts, not a complete microarchitectural specification. The presentation does not disclose every queue depth, exact ROB size, all pipeline latencies, predictor internals, physical register counts, or every arbitration rule. MX64 will not invent those values and attribute them to AMD.

## 3. Proposed MX64-H design point

The following are MX64 engineering targets, not AMD specifications. They are ambitious and must be validated by timing/area feasibility later.

### 3.1 Front end
- 64-bit custom ISA, fixed-width base instruction encoding initially; optional compressed encoding only after the base ISA is frozen.
- 4-instruction/cycle decode target.
- 8-uop/cycle decoded-op-cache delivery target for hot loops (initial target, subject to timing/area).
- 6-uop/cycle dispatch target.
- Multi-level prediction: fast BTB/next-line predictor plus backing direction predictor (gshare/TAGE-class evaluation later), return-address stack, indirect-target predictor.
- Fetch queue and decoded-op queue with prediction metadata, epoch tags and precise redirect handling.
- I-TLB and L1I; page-crossing and fetch-fault handling.

### 3.2 Rename and speculative state
- Separate integer and FP/vector rename domains.
- Explicit physical register renaming with busy/ready tracking.
- Committed map state plus speculative map state.
- Branch checkpoints with allocation tracking that cannot leak freed/reallocated physical registers.
- ROB identity includes slot plus sufficiently wide generation/epoch; stale completions must be rejected.
- Rename/dispatch width 6 target; exact implementation may use banking or staged allocation to meet timing.
- SMT is not in the first implementation. Design structures may carry thread ID only if it does not complicate correctness; SMT comes after single-thread core.

### 3.3 Scheduling and execution
- Multiple scheduler domains: integer, branch, load/store, FP/SIMD.
- Integer execution target: multiple simple ALUs, dedicated branch execution, multiple AGUs, pipelined multiply, iterative/pipelined divide.
- FP/SIMD domain: separate physical register file, rename, issue queues and execution pipeline.
- Result/writeback network designed for multiple simultaneous completions; avoid assuming a single global CDB.
- Issue selection policy must consider age, port compatibility, unit availability and starvation avoidance.
- Variable-latency units must support kill/flush semantics and never return a result into a reused ROB identity.

### 3.4 Retirement and precise state
- 6-uop/cycle retirement target, independently parameterized from dispatch.
- In-order commit, precise exception boundary, branch recovery and replay support.
- Stores become externally visible only after retirement authorization.
- Stale physical destinations reclaimed only when the owning instruction commits.
- Separate committed rename maps support fast precise recovery; compare area/timing against ROB rollback.

### 3.5 Memory hierarchy
- Initial L1I/L1D target: 32 KiB each, 8-way, 64-byte lines (proposal, not frozen).
- Initial private L2 target: 1 MiB, 8-way, 64-byte lines (proposal; later evaluate unified vs split).
- Nonblocking caches with MSHRs, refill/writeback queues and transaction IDs.
- D-side target throughput: up to 3 loads and 2 stores/cycle at the LSU/cache interface, subject to bank conflicts, cache misses, TLB misses and external bandwidth.
- Load queue, store queue, committed store buffer, store-to-load forwarding, byte-mask merge, violation detection and replay.
- Explicit memory types: cacheable, non-cacheable, device/MMIO, idempotent/non-idempotent.
- No speculative MMIO side effects.

### 3.6 Virtual memory and protection
- 48-bit virtual-address target is provisional until canonical-address rules and page-table format are frozen.
- Separate ITLB and DTLB, page-table walker, ASID, invalidation protocol.
- PMP/PMA-like physical access checks before external transactions.
- Precise page/access faults flow through the ROB.

### 3.7 Platform and system
- Boot ROM/reset vector, timer and interrupt interfaces, debug halt/resume/single-step, performance counters.
- External memory interface abstracted behind a stable protocol; AXI4 adapter can be a platform implementation, not an ISA requirement.
- ECC/parity strategy for arrays and queues.
- DFT/scan/MBIST hooks planned from the start of physical implementation.
- Multi-core, coherent fabric and chiplet topology are future SoC-level projects, not first-core scope.

## 4. Why the current MX64 baseline must change

The existing M2/M3 drafts use a 2-wide dispatch/retire target, a small integer-only issue path, 80 physical integer registers, 48-entry ROB, and no integrated FP rename, full LSU, MMU or complete cache controllers. These are useful prototypes but do not match the proposed MX64-H scope.

Therefore:
- Preserve useful leaf RTL only after interface and semantics review.
- Do not scale counters/arrays mechanically and call it a high-performance core.
- Redesign uop formats, ROB tags, rename checkpoint model, issue ports, writeback network and dispatch reservation around the 6-wide target.
- Keep the early 2-wide implementation as a bring-up configuration only if the architecture can parameterize width without duplicating semantics.
- The new high-performance architecture becomes the normative design; old drafts are marked legacy/prototype until migrated.

## 5. Research-derived design principles

### 5.1 Separate fast and accurate prediction
BOOM documents a fast next-line predictor/BTB and a slower backing predictor such as GShare, with speculative global history requiring recovery on misprediction. MX64 should therefore track prediction metadata and history checkpoints through fetch/rename/execute; the current simple direct-mapped BTB is only a seed block.

### 5.2 Explicit rename requires lifecycle correctness
BOOM's rename documentation explains map tables, busy tables, free lists, branch snapshots and stale physical destination reclamation. It also documents a subtle physical-register leak when a simplistic free-list snapshot is restored after a register has been freed and reallocated. MX64 must use allocation lists/epochs or a proven checkpoint scheme rather than naïve bitmap restore.

### 5.3 Split scheduling by execution class
BOOM documents split issue queues for integer, FP and memory operations, with wakeup, select and unit-availability handling. MX64-H should separate scheduling domains and provide multiple result paths, rather than expanding a single small integer queue to cover every unit.

### 5.4 ROB is the precise-state boundary
BOOM's ROB documentation describes in-flight tracking, out-of-order completion, in-order commit, exception-at-head handling, store authorization at commit and stale physical register release. These contracts become mandatory MX64-H invariants.

### 5.5 Width is a system-level budget
A 6-wide dispatch target requires coordinated capacity across decode, rename, free-list allocation, ROB banks, issue queues, PRF read/write ports, execution units, result buses, LSQ, cache ports and retirement. Increasing only dispatch width creates bubbles or bottlenecks elsewhere. MX64 will specify per-stage width and per-cycle port budgets in an explicit bandwidth matrix.

## 6. Architecture freeze decisions required before major RTL

1. Base ISA instruction formats and exact encoding.
2. Privilege levels and trap model.
3. FP/SIMD register width and architectural state.
4. Memory consistency model and atomic operations.
5. Virtual memory format, page sizes and canonical VA.
6. Dispatch, issue, execute, writeback and retire widths.
7. ROB, integer/FP physical register and queue sizing.
8. Cache topology, line size, associativity and MSHR targets.
9. Interrupt/debug architecture.
10. External bus, boot and memory map.

## 7. Work breakdown changes

The master WBS is updated by adding a high-performance architecture freeze before frontend/backend expansion:
- H0: requirements and target workloads.
- H1: ISA + privileged + FP/SIMD architectural state.
- H2: bandwidth matrix and queue/port budget.
- H3: frontend and op-cache architecture.
- H4: split integer/FP rename and checkpoint design.
- H5: multi-scheduler, multi-execution and writeback network.
- H6: high-throughput LSU and nonblocking cache hierarchy.
- H7: MMU, protection, interrupts and debug.
- H8: full-core integration and source review.
- H9: deferred simulation/formal campaign.
- H10: synthesis, PPA, FPGA and ASIC flow.

## 8. Sources

1. AMD GPUOpen, *AMD Ryzen Processor Software Optimization*, GDC 2024, especially the Zen 4 microarchitecture diagram and resource-sharing slides:
   https://gpuopen.com/download/GDC2024_AMD_Ryzen_Processor_Software_Optimization.pdf
2. Berkeley BOOM documentation, pipeline:
   https://docs.boom-core.org/en/latest/sections/intro-overview/boom-pipeline.html
3. Berkeley BOOM documentation, branch prediction:
   https://docs.boom-core.org/en/latest/sections/branch-prediction/
4. Berkeley BOOM documentation, rename:
   https://docs.boom-core.org/en/latest/sections/rename-stage.html
5. Berkeley BOOM documentation, issue units:
   https://docs.boom-core.org/en/latest/sections/issue-units.html
6. Berkeley BOOM documentation, ROB and dispatch:
   https://docs.boom-core.org/en/latest/sections/reorder-buffer.html
7. Kithany et al., *An Out-of-Order RISC-V 32IM Processor with Explicit Register Renaming*:
   https://yugalkithany.github.io/media/ECE411_FPJ.pdf

## 9. Verification boundary

This architecture proposal is research-informed, but the current RTL has not been migrated to this target, compiled, simulated, formally checked or synthesized. The simulator remains deliberately deferred until the planned implementation and source-review gates are complete.


## Software deliverables and scope boundary

Software deliverables and physical-hardware limitations are defined in `docs/SOFTWARE_ONLY_SCOPE.md`. The current draft ISA tooling is under `tools/mx64/`; it is provisional until H1 ISA freeze. Simulation/formal/synthesis remain deferred by `software/BUILD_PHASE_POLICY.md`.
