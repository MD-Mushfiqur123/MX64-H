# MX64 Microarchitecture Overview

Version: 1.0-draft

## 1. Product definition

MX64 is a single-core baseline 64-bit superscalar processor with out-of-order execution and in-order retirement. It is designed for eventual ASIC implementation using a commercial foundry PDK selected by the project owner.

### Fixed baseline targets

| Parameter | Baseline |
|---|---:|
| ISA integer width | 64 bits |
| Architectural integer registers | 32 |
| `x0` | Constant zero |
| Fetch/decode/rename/dispatch/retire width | 2 instructions/cycle target |
| Physical integer registers | 80 entries, configurable |
| Reorder buffer | 48 entries, configurable |
| Integer issue queue | 16 entries, configurable |
| Load queue | 16 entries, configurable |
| Store queue | 16 entries, configurable |
| Integer ALUs | 2 |
| Branch units | 1 |
| Multiply units | 1 pipelined |
| Divide units | 1 iterative |
| L1 instruction cache | Private, 32 KiB target, 4-way target |
| L1 data cache | Private, 32 KiB target, 4-way target |
| Shared L2 cache | 256 KiB target, 8-way target |
| Virtual address | 48-bit canonical |
| Physical address | `PADDR_W` integration parameter; no default signoff value |
| Cache line | 64 bytes target |
| Endianness | Little-endian |
| Retirement | In program order |
| Execution | Out of program order |

Cache sizes/associativities above are design targets, not frozen physical implementation facts. They may be changed after SRAM compiler availability, area estimation and timing analysis.

## 2. Datapath flow

Fetch → Decode → Rename → Dispatch → Issue/Select → Execute → Writeback → Commit.

The frontend and retirement preserve program order. The scheduler may issue any ready instruction subject to age policy, functional-unit availability, and memory-dependence constraints.

## 3. Register renaming

- Architectural register map: 32 entries.
- Physical register file: 80 × 64-bit entries in the baseline configuration.
- `x0` always maps to a constant-zero source and never allocates a physical destination.
- Rename map table (RAT) maps each architectural register to its current speculative physical register.
- A committed map table (RAT/retirement map) tracks architectural state at the retirement boundary.
- Free list allocates destination physical registers.
- Each ROB entry records destination architectural register, new physical destination, and previous physical mapping.
- On retirement, the previous physical mapping is returned to the free list only when no architectural/speculative reference remains under the selected rename bookkeeping scheme.
- On misprediction/exception, speculative rename state is restored from a checkpoint or reconstructed from committed state plus surviving ROB entries.

The implementation must prove no physical register is freed while still referenced by an in-flight instruction or committed mapping.

## 4. ROB and precise retirement

- ROB is circular, 48 entries by baseline.
- Each entry records valid, sequence/age, operation class, completion, exception, destination mapping, branch metadata, and store-commit metadata.
- Instructions may complete out of order.
- Only the oldest completed non-faulting instruction(s) retire.
- Stores become globally visible only at the architecturally permitted commit point.
- A faulting instruction prevents younger instructions from retiring.
- Exceptions are reported precisely at the oldest faulting instruction.

## 5. Issue queues and execution

- Integer issue queue: 16 entries target, age-aware selection.
- Each source operand is represented as ready value or producer tag.
- Wakeup broadcasts completion tags; select chooses ready operations.
- Initial design may use a centralized common-data-bus-style completion network, but fanout/timing must be measured.
- ALU pipelines are single-cycle target unless timing analysis requires multi-cycle staging.
- Multiply is pipelined; exact latency is implementation parameter.
- Divide is iterative; exact latency is implementation parameter.
- Functional units return ROB/physical destination tags, result, exception and branch-resolution metadata.

## 6. Branch prediction and recovery

Initial implementation:
- Static not-taken predictor for bring-up.
- BTB and dynamic predictor are later feature gates.
- Branch resolution occurs in execution.
- Misprediction flushes younger instructions, restores rename/free-list state, redirects fetch and invalidates younger speculative queue entries.
- Predictor updates occur at a defined resolution or retirement point; the policy must be consistent and tested.

No speculative store may modify externally visible memory before retirement.

## 7. Memory subsystem

- Private L1I and L1D; shared L2 interface.
- 64-byte cache-line target.
- Write-back, write-allocate L1D target.
- L1I is read-only from the core; instruction/data coherence and self-modifying-code behavior require explicit fence/maintenance semantics.
- LSU contains load queue and store queue.
- Loads may bypass older stores only when address/data-dependence rules prove safe.
- Store-to-load forwarding must select the youngest older matching store and support byte masks.
- Memory-order violation detection must replay affected loads or squash/restart according to a documented policy.
- L2 coherence protocol is not selected in this single-core baseline. For multicore expansion, select a protocol and define ownership, invalidation, ordering and atomic interactions before implementation.

## 8. Virtual memory and translation

- Virtual address width: 48 bits.
- Canonicality rule: addresses must be sign-extended from bit 47; non-canonical accesses fault.
- Translation architecture: page-table format and page sizes remain an open decision.
- ITLB and DTLB are required when virtual memory is enabled.
- TLB miss handling requires a page-table walker or a platform translation interface.
- Physical address width is parameterized by `PADDR_W`.
- TLB permissions and privilege checks occur before cacheable memory side effects.
- Physical address width must be compatible with selected SoC interconnect and PDK memory macros.

## 9. Reset and clocking

- One primary core clock domain in baseline.
- Synchronous internal reset is preferred after reset synchronization at the integration boundary.
- Reset state: frontend stopped, ROB empty, issue queues empty, caches invalid, translation structures invalid, architectural registers zeroed or architecturally unspecified as frozen by ISA.
- Reset values must be specified for every architecturally visible state element.
- No asynchronous clock crossing is permitted inside the core without explicit CDC structures and verification.

## 10. Parameterization

Parameters must be centralized in `mx64_config_pkg.sv` or top-level parameters. Parameters affecting correctness (ROB depth, physical register count, widths, queue depths) require elaboration-time assertions and parameterized regression tests.
