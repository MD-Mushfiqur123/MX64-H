# MX64 RTL Module Contracts

Version: 1.0-draft

All interfaces are synchronous to `clk` unless explicitly stated. `valid`/`ready` transfers occur on a rising edge when both are asserted. Payload must remain stable while `valid && !ready`. Reset/flush priority is specified per module.

## Global conventions

- Data width: 64 bits.
- Virtual address width: 48 bits.
- Physical address width: `PADDR_W`.
- ROB tag width: `$clog2(ROB_DEPTH)` plus generation/valid handling as needed.
- Physical register tag width: `$clog2(PHYS_REG_COUNT)`.
- All queue pointers must distinguish full from empty.
- No X/Z value may be treated as a legal control decision in synthesizable operation.
- Every module must define reset, flush, backpressure and simultaneous enqueue/dequeue behavior.

## Contracts

### `fetch_unit`
Inputs: `clk`, `rst`, redirect valid/target, instruction-cache request ready, instruction-cache response valid/data, predictor response.
Outputs: fetch request valid/address, decode packet valid/data, predicted next PC, exception metadata.
Guarantees: preserves instruction order; stops/redirects on flush; does not issue non-canonical fetch addresses without fault handling.
Verification: sequential fetch, redirect, cache stall, response error, boundary crossing.

### `decode_unit`
Inputs: fetch packet.
Outputs: decoded micro-op packet, source architectural register IDs, destination ID, immediate, operation class, illegal flag.
Guarantees: deterministic decode; all reserved encodings become illegal instruction.
Verification: exhaustive opcode decode, malformed fields, all immediate sign-extension cases.

### `rename_unit`
Inputs: decoded uops, RAT, free-list availability, ROB allocation availability, flush/checkpoint restore.
Outputs: renamed uops with physical source/destination tags, old destination mapping, allocation requests, checkpoint metadata.
Guarantees: x0 never allocates; source operands use the mapping visible before the current instruction's destination update; dual-rename same-register dependencies are handled in program order.
Verification: RAW/WAR/WAW, two-wide same-destination, free-list exhaustion, flush recovery.

### `reorder_buffer`
Inputs: dispatch allocations, execution completion tags, exception reports, branch recovery, retirement ready.
Outputs: head entries, retirement valid/payload, full/empty, commit events.
Guarantees: allocation in program order; completion may be out of order; retirement strictly in order; no younger retirement past older incomplete/faulting entry.
Verification: wraparound, simultaneous alloc/retire, duplicate completion, exception at head, branch-tag lookup, selective younger-entry kill.

### `physical_regfile`
Inputs: read tags, writeback ports, reset/valid state.
Outputs: read data and readiness.
Guarantees: x0 is external constant; write/read same-cycle behavior is explicitly bypassed or specified; multiple write ports cannot silently collide.
Verification: RAW forwarding, port collision, reset, uninitialized-tag detection.

### `issue_queue`
Inputs: renamed uops, source-ready/value/tag, completion broadcasts, full flush, branch-recovery sequence and execution-unit ready.
Outputs: selected uops and valid/ready.
Guarantees: only ready operands issue; killed uops never issue; selection respects configured age/priority policy.
Verification: wakeup/select same cycle, multiple completions, starvation bounds, flush during backpressure.

### `execution_units`
Inputs: issued uop and operands.
Outputs: completion valid, ROB tag, physical destination tag, result, exception, branch outcome/target.
Guarantees: operation latency and throughput are documented; no duplicate completion; tags remain associated with the originating uop.
Verification: arithmetic corner cases, variable latency, backpressure, kill/flush.

### `load_store_unit`
Inputs: renamed memory uops, translation responses, cache request/response, older store queue entries, flush/retire.
Outputs: load/store completion, store commit request, memory exception, replay request.
Guarantees: speculative loads may execute subject to ordering policy; stores do not become externally visible before commit; forwarding uses youngest older matching store and byte masks.
Verification: forwarding, partial overlap, aliasing, violation replay, faults, flush.

### `l1_cache`
Inputs: CPU-side request/response, lower-level refill/evict interface, maintenance/flush.
Outputs: response, miss request, writeback.
Guarantees: stable request protocol, correct byte masks, replacement state, valid/dirty tracking, no silent lost dirty line.
Verification: hit/miss, refill, eviction, writeback, backpressure, reset invalidation.

### `l2_cache_controller`
Inputs: requests from L1s / integration ports, memory-side request/response.
Outputs: response, refill/writeback, arbitration.
Guarantees: deterministic arbitration; correct line data and byte masks; documents ordering and coherence assumptions.
Verification: simultaneous I/D requests, conflict misses, dirty eviction, memory backpressure.

### `commit_unit`
Inputs: ROB head entries, CSR/trap state, store queue status.
Outputs: retire signals, architectural map updates, store authorization, trap/redirect.
Guarantees: in-order precise retirement; stores become visible only at approved commit point; traps suppress younger retirement.
Verification: two-wide retire dependency, exception precision, store commit, interrupt boundary.

### `mmu_tlb`
Inputs: virtual request, access type, privilege, page-table walker response.
Outputs: physical address, permission result, page/access fault.
Guarantees: canonicality and permissions checked before side effects; translation response tagged to request.
Verification: TLB hit/miss, permission, invalid PTE, canonicality, page-walk fault, flush.

## Top-level integration contract

`mx64_top` exposes:
- clock/reset;
- instruction/data memory-system interfaces;
- interrupt inputs (when interrupt architecture is frozen);
- debug/trace outputs;
- parameterized `PADDR_W`;
- test-only observability behind a synthesis-excluded interface.

Top-level must not depend on simulation-only constructs.

## M1.2 implementation note

Initial RTL drafts now exist for `free_list`, `rename_unit` and `reorder_buffer`. They are scaffolds pending compile, directed simulation, formal properties and integration review. See `verification/ROB_RENAME_STATUS.md`.

### M2 issue queue draft interface note

The current `issue_queue.sv` draft uses a grant-style execution interface: `issue_valid[p]` is asserted only when a ready candidate exists **and** `issue_ready[p]` is high. Therefore an execution port that is not ready sees no transfer and no stalled valid payload. This avoids candidate instability when a newly awakened older uop changes age priority. If the integration later requires conventional decoupled valid/ready semantics, add per-port reservation/skid state and verify payload stability under backpressure.


### M2.7 committed rename-map contract

The rename subsystem maintains two maps:
- speculative RAT, updated only when a renamed uop is accepted and restored
  from the branch checkpoint selected by recovery control;
- committed RAT, updated only on accepted, non-exception ROB retirement.

Each ROB entry carries the architectural destination, new physical destination,
and previous physical destination. On a normal retirement handshake, the
committed RAT installs the new physical destination and the free-list receives
the previous physical destination. For dual retirement, updates are applied in
program order (lane 0 then lane 1), so lane 1 wins for repeated writes to the
same architectural register.

This is a source-level integration contract, not yet simulation- or
formal-verified. Exception/trap recovery and atomic branch checkpoint capture
remain separate required work.

The physical free-list reserves p0 permanently. Initial identity mappings
p1..p31 are unavailable at reset, but once a committed destination replaces
one of them, that previous physical tag becomes reclaimable. Checkpoint restore
must provide a bitmap consistent with both the restored speculative RAT and
committed RAT; only p0 is forcibly masked by the free-list.

### `branch_checkpoint_manager`

Captures the speculative RAT, free-list bitmap, full ROB tag and global dispatch
sequence at an accepted control-transfer dispatch. Checkpoints are ordered by
capture age. Correct resolution releases exactly the matching checkpoint and
compacts the age list. A misprediction restores the matching snapshot, discards
that checkpoint and every younger checkpoint, and preserves older unresolved
branches. Resolution is accepted only when the ROB independently confirms the
full tag is still live, and the manager changes state only on an explicit
`resolve_valid` handshake. The per-lane snapshot is taken after the branch's own
rename stage, excluding younger same-cycle dispatch work. Commit frees from older
retiring instructions are merged into every active snapshot so recovery cannot
resurrect an already-released physical register.

### Branch recovery integration

`mx64_dispatch_controller` exposes a dedicated control-transfer dispatch path
(`branch_dispatch_valid/ready/uop`) so branches and jumps are not enqueued into
the integer ALU issue queue. The branch execution unit must return the full ROB
tag, misprediction indication, actual next PC and destination result value. The
result value is separate from the next PC (for example, JAL writes PC+4). On
misprediction the dispatch controller restores RAT/free-list state, the ROB retains entries through the
branch and moves its tail to the first younger slot, and the integer issue queue
removes entries whose 32-bit dispatch sequence is younger than the branch.
Allocation, issue and retirement are held for the recovery cycle. The branch
unit holds its result until `branch_resolve_ready`; an accepted result uses the
extra ROB completion port. The frontend must redirect to `recovery_pc`; the
branch unit must use `recovery_seq` to remove younger control-transfer work from
its own structures. Sequence comparisons use signed modular ordering and require
fewer than 2^31 live dispatches of distance.

This is a source-level integration contract; branch execution, frontend wiring,
HDL compilation, simulation, formal verification and synthesis are still
required before the recovery path can be considered proven.

### ROB precise exception rule

If the oldest completed ROB entry is exceptional, it is the only retirement
candidate in that cycle. A younger completed entry must not retire alongside
it. The ROB carries the exception enum and `mtval` payload from allocation-time
(decode/front-end faults) or completion-time (execution/LSU faults) through the
retirement interface.

### `mx64_trap_controller`

Inputs: two-wide ROB retirement candidates, exception enum/`mtval`, normal
retirement readiness, current privilege and CSR-computed trap vector.
Outputs: ROB retirement readiness, CSR trap pulse/PC/cause/`mtval`, speculative
flush/redirect, and a 0..2 `minstret` increment.
Guarantees: a fault in lane 1 is held while older lane 0 retires; only a fault at
ROB head may trap; the faulting instruction does not increment `minstret`; no
younger instruction retires with a head trap. Interrupt arbitration and MRET
privilege restoration are intentionally outside this synchronous-exception
block.

Precise trap integration contract: connect `trap_valid`, `trap_pc`,
`trap_cause`, `trap_value`, and `trap_is_interrupt` to `mx64_csr_file`; connect
`trap_vector` from CSR to the controller; connect `rob_retire_ready` back to the
ROB retirement-ready input; and use `flush_speculative` as the dispatch/core
flush. For that flush, the rename restore mux must select `committed_rat_debug`
and `committed_free_bitmap_debug` from the dispatch controller. The latter is
reconstructed from the committed RAT so no uncommitted physical mapping is
resurrected. Feed `retired_count` to the CSR `minstret` counter.


### Phase 36.2 committed-store error sink extension
`mx64_lsu_cache_subsystem` exposes `store_error_valid`,
`store_error_lifecycle_slot`, and accepts `store_error_ready`. For an accepted
committed store that later receives a cache error, the cache response is held
until both `cache_rsp_ready` and `store_error_ready` are asserted. The platform
must connect this channel to a non-speculative machine-check/asynchronous-store
error handler. This extension is not yet connected at `mx64_top`.


## Phase 37.1 memory dispatch separation

Load/store uops are routed to `mx64_memory_issue_queue`; only non-memory, non-branch, non-exception integer uops enter `integer_execution_cluster`. The memory queue issues the oldest resident memory uop only, preserves output payload under downstream backpressure, and tracks unresolved source physical-register references.


## Phase 37.1 — Memory issue queue boundary

- Load/store uops do not enter the integer ALU issue queue. They are accepted by `mx64_memory_issue_queue` through the dedicated memory-dispatch handshake.
- The memory issue queue issues the oldest live memory uop only; younger memory uops cannot pass an older unresolved memory uop.
- Source operands are tag-woken from integer, branch-link, or memory writeback. Unresolved source references are acquired at enqueue and released on wakeup or flush/recovery kill.
- `memory_issue_valid/ready/uop` is an external boundary to the LSU operand/translation admission adapter. It is not yet wired directly to `mx64_lsu_cache_subsystem`, because that subsystem currently accepts already-computed address/data operands and has no ROB-destination completion metadata.
