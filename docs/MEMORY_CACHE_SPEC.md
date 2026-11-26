# MX64 Memory, Cache and Address Specification

Version: 1.0-draft

## Address model

- Virtual address width: 48 bits.
- Canonical virtual address: bits 63:48 equal sign-extension of bit 47.
- Physical address width: `PADDR_W`, selected by SoC/platform integration and commercial PDK/memory map.
- No physical width is assumed by the ISA.
- Address translation and permissions must complete before externally visible memory effects.

## Cache hierarchy targets

| Level | Organization | Target capacity | Target line | Policy |
|---|---|---:|---:|---|
| L1I | Private | 32 KiB | 64 B | Read-only from core |
| L1D | Private | 32 KiB | 64 B | Write-back, write-allocate |
| L2 | Shared interface/controller | 256 KiB | 64 B | Write-back target |

These are initial modeling targets. Actual organization depends on foundry SRAM compiler macros, banking, port count, timing and area.

## Cache interface requirements

- Request valid/ready and response valid/ready.
- Request ID or transaction tag to support outstanding misses.
- Byte-enable support at data interface.
- Error response propagation.
- Flush/invalidate/maintenance interface.
- Explicit reset invalidation.
- Defined ordering for same-line simultaneous requests.
- Refill and writeback buffering.
- Backpressure propagation without dropping transactions.

## L1D and LSU interaction

- Store queue retains speculative stores until retirement.
- Committed stores drain to L1D in program order unless the selected memory model explicitly permits a different implementation preserving architectural ordering.
- Loads may forward from older stores.
- Partial store-to-load forwarding requires byte-granular masks and merge logic.
- Memory dependence prediction is optional; correctness cannot depend on predictor accuracy.
- A detected violation must replay the load or squash/restart the affected speculative window.

## L1I and instruction visibility

FENCE.I or equivalent instruction synchronization must ensure stores to executable memory become visible to subsequent instruction fetch. The exact cache maintenance and ordering sequence must be defined in the ISA.

## L2 and coherence

Baseline is single-core. L2 controller must provide a coherent view to L1I/L1D within that core. Multicore coherence protocol is not frozen. Do not label the design coherent for multiple cores until a protocol, state machine, transient states, ordering rules and verification suite exist.

## Atomics

Atomic operations are not enabled in the initial RTL baseline. Before enabling them, define reservation granularity, LR/SC failure conditions, AMO serialization, cache-line locking and interaction with interrupts/flushes.

## Virtual memory

Page table format, page sizes, TLB sizes, ASID, privilege permissions and page-walker interface remain open decisions. The core must not claim a complete MMU until these are specified and verified.
