# MXISA-64 / MX64 CPU / MXAGENT Repository

**Status:** Architecture baseline v1.0-draft  
**Target:** 64-bit, 2-wide superscalar, out-of-order CPU; private L1 I/D caches; shared L2; 48-bit virtual addressing; platform-defined physical address width; commercial-foundry ASIC flow.

This repository is an implementation-oriented specification and RTL scaffold. It is **not** a completed CPU, a verified RTL implementation, a foundry-qualified design, or a tapeout-ready GDSII.

## Important architecture boundaries

1. `MXISA-64` is a new ISA. The earlier MXISA v0.1 encoding is not binary-compatible and is not reused.
2. Architectural registers: 32 × 64-bit integer GPRs; `x0` is constant zero.
3. Initial microarchitecture target: 2-wide fetch/decode/rename/dispatch/retire; out-of-order issue and execution.
4. Initial execution resources: two integer ALU pipelines, one branch unit, one pipelined multiply unit, one iterative divide unit, one load/store pipeline.
5. Initial speculation is in-order at the frontend and retirement, out-of-order in execution. Architectural state changes only at retirement.
6. Virtual addresses are 48-bit canonical addresses. Physical address width is a platform parameter supplied by the selected PDK/SoC integration; it is not guessed here.
7. L1 instruction and data caches are private to the core; L2 is shared at the core boundary. The initial repository models one core and a shared-L2 interface that can later connect multiple cores.
8. Cache coherence, multicore consistency, privilege/virtual-memory details, interrupts, debug, and external bus protocol must be frozen before full-system implementation. The current documents define a conservative single-core baseline and mark integration choices explicitly.
9. A commercial PDK is not identified. The technology layer is therefore abstract and requires foundry NDA collateral, libraries, SRAM macros, RC corners, DRC/LVS decks, and signoff tools from the chosen provider.

## Repository map

- `docs/` — ISA, microarchitecture, memory, exception, cache and PDK integration specifications.
- `rtl/` — synthesizable module shells and package/interface definitions; intentionally incomplete.
- `verification/` — verification strategy, test matrix, assertions and reference-model interface.
- `synthesis/` — technology-independent synthesis entry points and constraint templates.
- `physical_design/` — OpenROAD-oriented flow contract and PDK integration checklist.
- `mxagent/` — agent roles, workflow contract, tool permissions and acceptance gates.
- `scripts/` — repository checks and configuration validation.

## Quick start

```bash
python3 scripts/check_repo.py
python3 tools/mx64/boot_image_tests.py
python3 tools/mx64/platform_tests.py
```

This checks repository structure and required specification markers. It does not compile or verify the CPU.

When a simulator is installed and RTL implementation begins, add simulator-specific targets. Do not report simulation success until the simulator actually ran and returned exit code 0.

## First implementation order

1. Freeze unresolved decisions in `docs/OPEN_DECISIONS.md`.
2. Implement and verify package types, reset, CSR/exception baseline and register file.
3. Implement ROB, physical register file, rename map and free list.
4. Implement issue queues, wakeup/select and execution pipelines.
5. Implement branch recovery and precise retirement.
6. Implement LSU, store queue, load queue and memory ordering.
7. Implement MMU/TLB and private L1 caches.
8. Implement shared L2 interface/controller and memory-system integration.
9. Run independent simulation, formal and synthesis gates.
10. Integrate the selected commercial PDK and complete physical signoff.

## Non-goals of this baseline

No claim is made for frequency, IPC, area, power, process node, cache latency, transistor count, or fabrication readiness. These require implementation, library data, constraints and measurement.


## M1 progress (initial RTL units)

Added:
- `rtl/common/mx64_pkg.sv`: initial shared operation/exception/uop types.
- `rtl/execution/integer_alu.sv`: 64-bit combinational ALU.
- `rtl/rename/physical_regfile.sv`: parameterized multi-read/multi-write physical register file with valid bits and explicit same-cycle write forwarding.
- `verification/unit/`: directed ALU and physical-register-file testbenches.

These are first implementation units only. Rename recovery, ROB, issue queue, LSU, MMU and cache hierarchy remain incomplete. Run actual simulator tests before claiming RTL validation.


## M2.1 integer execution integration
- Added `rtl/execution/integer_execution_cluster.sv`: two-wide issue queue + two integer ALUs + registered completion/wakeup path. Draft only; not simulator-verified.


## M2.2 ROB + integer execution integration
- Added `rtl/core/mx64_integer_backend.sv` to connect integer completion lanes to the ROB and expose in-order retirement. Dispatch atomicity remains an upstream contract; RTL is not simulator-verified.


## M2.3 atomic dispatch controller
- Added `rtl/core/mx64_dispatch_controller.sv`; issue queue enqueue-ready now follows a capacity-only ready/valid contract. This remains an unverified integration draft.
- Free-list allocation now commits only on accepted rename handshakes (`alloc_take`), preventing physical-register leakage under backpressure (unverified).


## Windows CMD simulation
See `docs/WINDOWS_CMD_SIMULATION.md`. Run `scripts\run_alu_test_windows.bat` after activating OSS CAD Suite.
\n\n## Research and technical references\n\nSee `docs/REFERENCES.md` for public BOOM architecture documentation, a research paper on precise interrupts in Tomasulo scheduling, and Icarus Verilog installation guidance.\n

## M2.4 source audit

See `verification/RTL_AUDIT_M2_4.md` for the implementation gaps and verification gates identified during source review. The review is not an HDL compile or simulation result.


## M3 architecture expansion

See `docs/architecture/MX64_FULL_CORE_ARCHITECTURE.md` for the complete target block inventory, speculative pipeline, memory/privilege contracts, verification gates and staged implementation roadmap.

Added first-draft RTL:
- `rtl/frontend/mx64_branch_predictor.sv`: tagged direct-mapped BTB with 2-bit saturating direction counters.
- `rtl/csr/mx64_csr_file.sv`: initial machine-mode CSR/trap-state block.

These are architectural building blocks, not an integrated frontend or privileged subsystem. They have not yet been HDL-compiled, simulated, formally verified or synthesized. Research notes and source links are in `docs/architecture/M3_RESEARCH_NOTES.md`.


## Master work breakdown

The full implementation task tree, dependency gates, module-level deliverables, integration criteria, and deferred final verification campaign are defined in `docs/architecture/MX64_MASTER_WBS.md`. The project deliberately postpones simulator execution until the complete planned RTL integration and source review are finished. This is a plan, not a claim that all listed blocks already exist.


## MX64-H high-performance architecture direction

The research-informed high-performance target and its evidence boundary are documented in `docs/architecture/MX64_H_HIGH_PERFORMANCE_ARCHITECTURE.md`. This supersedes the earlier 2-wide prototype as the normative architecture direction. It distinguishes publicly documented AMD Zen 4 slide facts from MX64 engineering targets. Simulation remains deferred until full implementation and source review.


## Software-only delivery scope

See `docs/SOFTWARE_ONLY_SCOPE.md` and `software/BUILD_PHASE_POLICY.md`. The project includes a draft Python ISA reference model and encoder/decoder helpers to support software-level architecture work. The ISA is not frozen; these tools are provisional and must evolve with the ISA specification.

## Research sources

See `docs/research/AMD_ZEN_PUBLIC_REFERENCE.md` and `docs/research/OPEN_CORE_RESEARCH_NOTES.md`. Public Zen 4 slide facts are distinguished from MX64 engineering targets. No proprietary AMD implementation details are assumed.


## MX64-H H0/H1 requirements and ISA baseline work

The current architecture/requirements proposal is in:
- `docs/requirements/MX64H_SYSTEM_REQUIREMENTS.md`
- `docs/requirements/MX64H_REQUIREMENTS_TRACEABILITY.csv`
- `docs/isa/MXISA64_ISA_BASELINE.md`
- `docs/isa/MXISA64_OPCODE_TABLE.csv`
- `docs/isa/MXISA64_PRIVILEGED_PROFILE.md`
- `docs/architecture/MX64H_H0_H1_DECISIONS.md`
- `software/abi/MX64H_ABI_DRAFT.md`
- `software/toolchain/MX64H_TOOLCHAIN_ROADMAP.md`

These are H0/H1 proposals, not a frozen production ISA. In particular, CSR selector encoding, atomic semantics, privilege/VM details, and ABI/ELF identifiers remain explicit freeze blockers. Simulation, formal execution, and synthesis remain deferred to the final verification phase.

## Phase 9: loadable ELF executable prototype

The software linker now emits an ELF64 `ET_EXEC` with a page-aligned RX `PT_LOAD` program segment. The parser checks program-header and section-name-table bounds and segment alignment. This is still a single-segment software prototype—not a bootable FPGA image, registered ELF ABI, or platform loader. See `software/toolchain/MX64H_TOOLCHAIN_ROADMAP.md` for the exact limits.


## Phase 10: platform contract and boot-image envelope

- `tools/mx64/boot_image.py` defines a version-1 128-byte container header carrying an MX64-H ELF64 ET_EXEC payload, platform ID, entry point and SHA-256 payload digest.
- `tools/mx64/mxboot.py` provides `pack` and `inspect` commands; `make boot-image` builds the two-file software example and wraps it as a generic boot image.
- `platforms/fpga/template.json` and `platforms/asic/template.json` define explicit integration placeholders. Board part, PADDR width, reset vector, boot source and memory ranges remain null until a concrete platform is selected.
- `tools/mx64/platform_check.py` validates profile structure, configured address ranges, overlap and physical-address-width bounds.
- `docs/platform/PLATFORM_BOOT_CONTRACT.md` defines the loader obligations and security/validation boundary.

The container is not a hardware bootloader, ROM, signed update format or demonstrated FPGA/ASIC boot path. A real loader must validate each PT_LOAD destination against the selected RAM map, copy file bytes, zero `memsz-filesz`, and transfer control only after platform initialization. No simulator, formal tool or synthesis tool was run in this phase.


## Phase 11: multi-section ELF and BSS prototype

- The assembler/object writer now support `.text`, `.data`, `.bss`, local/global labels, alignment, basic data directives and per-section relocations.
- The linker produces separate RX and RW `PT_LOAD` segments, resolves ABS64 data pointers and preserves BSS alignment.
- `.bss` is `SHT_NOBITS`: a future loader must zero its `p_memsz - p_filesz` region.
- Boot-image validation rejects W+X and overlapping `PT_LOAD` segments.
- `load_image.py` is a software reference loader: it preflights platform memory ranges/permissions and models BSS zero-fill without performing hardware writes.
- `make test` includes multi-section, relocation, load-segment and BSS regression.
- This is still a software format prototype. A platform loader, boot firmware, compiler, completed RTL and hardware verification are not yet present.

For the 2026-11-25 research refresh, see `docs/research/MX64H_RESEARCH_UPDATE_2026-11.md`.


## Phase 11 — multi-section software image and RTL source audit

Phase 11 adds multi-section ELF64 linking (`.text`, `.data`, `.bss`), RX/RW `PT_LOAD` segments, BSS zero-fill metadata, a platform-aware reference-loader model, and expanded end-to-end examples. The ROB tag contract is now 22 bits for the current 48-entry profile (6-bit slot index + 16-bit per-slot epoch). Duplicate `reorder_buffer` module naming was removed. See `verification/RTL_AUDIT_M2_5.md` and `docs/research/MX64H_RESEARCH_UPDATE_2026-11.md`. Software/static regression passes; HDL compile, simulation, formal verification and synthesis remain deferred.


## Phase 12 — RTL contract hardening

Phase 12 widens the current ROB allocation epoch to 16 bits (22-bit total tag for the 48-entry profile), replaces hand-written occupancy arithmetic with an explicit accepted-allocation/retirement delta, and constrains the present ROB implementation to its actual dual-wide interface. Rename recovery now forces architectural x0 back to physical zero, and free-list recovery masks architectural physical registers as permanently reserved. The current issue-queue RTL also explicitly declares its dual-wide implementation constraint. A 16-bit epoch reduces stale-tag alias risk but does not replace long-latency cancellation/drain requirements. These are source-level corrections only; HDL compilation, simulation, formal verification, and synthesis remain pending.


## M2.6 physical register file collision-priority correction

A source audit found inconsistent priority for simultaneous same-address writes:
sequential storage selected port 0, while combinational bypass selected the
highest-numbered port. The bypass loop now uses the same port-0-wins policy.
The directed SystemVerilog testbench covers both the same-cycle forwarded value
and the post-edge stored value. This testbench has not been run; the Python RTL
source checker only validates the source-level priority contract.


## Phase 14 — retirement-driven rename commit metadata

The ROB now stores each instruction's new and previous physical destination
tags and returns them at retirement. The dispatch controller connects accepted,
non-exception retirement handshakes to a committed rename map and frees the old
physical mapping at commit. The speculative RAT remains separate and is
restored from externally selected checkpoint state on flush. This phase is
source-level only until HDL compilation, directed simulation and formal checks
are run.


## Phase 16 — selective branch recovery integration draft

The RTL now defines the core branch-recovery path across checkpoint management,
rename, ROB and integer issue queue. Each accepted branch/jump captures its
post-lane speculative RAT/free-list state, full ROB tag and dispatch sequence.
Correct resolution releases one checkpoint; misprediction restores the matching
snapshot, retains older ROB entries and the branch, removes younger ROB/IQ work,
and exports the actual redirect PC. Control-transfer uops use a dedicated branch
dispatch interface rather than the integer ALU queue. The branch unit and frontend
are not yet instantiated by `mx64_top`; this phase is source-level only.


## Phase 17 — precise synchronous exception path (RTL draft)

The ROB now stores exception enums and `mtval` payloads from decode-time
allocation or execution-time completion through retirement. Decode exceptions
are sent directly to the ROB rather than an execution queue. The new
`mx64_trap_controller` holds lane-1 faults behind older lane-0 retirement,
takes a trap only at the ROB head, generates a CSR trap pulse and `mtvec`
redirect, flushes speculative work, and reports a 0..2 retirement count for
`minstret`. The issue queue now blocks issue/enqueue immediately during the
trap flush cycle. The rename unit exports a free bitmap derived from the
committed RAT for precise trap restore. The CSR `mcause` width and `mepc`
alignment handling were corrected.

This is a module-level RTL contract, not a completed top-level CPU integration.
The wrapper must connect the trap controller to the CSR and dispatch flush,
and restore the committed RAT/free bitmap on trap. Interrupts, MRET privilege
restoration, debug entry, LSU exception sources, HDL compile/simulation, formal
verification and synthesis remain outstanding. See
`verification/ROB_RENAME_STATUS.md` and
`docs/isa/MXISA64_PRIVILEGED_PROFILE.md`.


## Phase 18 control integration

See `docs/PHASE18_INTEGRATION.md` and `rtl/core/mx64_control_subsystem.sv`. This is a control-subsystem integration slice, not a complete CPU top.


## Phase 19 frontend

See `docs/PHASE19_FRONTEND.md`. Fetch, decode and branch prediction are now available as a reusable frontend slice; `mx64_top` and the complete control path are not yet a fully integrated CPU.


## Phase 20 integration slice

See `docs/PHASE20_FRONTEND_BACKEND_INTEGRATION.md` and `rtl/core/mx64_frontend_dispatch.sv`. Fetch/decode now structurally feeds dispatch/rename/ROB/issue control; operand values and branch execution remain explicit external interfaces.


## Phase 21 — Integer PRF operand path

See `docs/PHASE21_PRF_OPERAND_PATH.md`. The integration wrapper now instantiates a four-read/two-write integer PRF and uses renamed physical tags plus PRF valid bits to supply operand data/readiness to dispatch. Branch-link PRF writes and HDL verification remain pending.


## Phase 22 — Branch writeback and unified wakeup

See `docs/PHASE22_UNIFIED_WRITEBACK_WAKEUP.md`. Branch link results now have a third PRF write port and a third issue-queue wakeup source alongside the two integer ALU completion lanes.
\n\n## Phase 23 — Recovery-safe completion stage\n\nSee `docs/PHASE23_RECOVERY_SAFE_COMPLETION.md`. Pending younger integer results are now suppressed during selective branch recovery before reaching ROB completion or PRF writeback.\n

## Phase 24 — Physical register lifetime and free-list safety

See `docs/PHASE24_PHYSICAL_REGISTER_LIFETIME.md`. Free-list reclamation now rejects stale/duplicate frees, asserts duplicate free requests, and preserves the p0 reservation.


## Phase 25 — Global physical-register reference tracking

See `docs/PHASE25_GLOBAL_REFERENCE_TRACKING.md`. Added a multi-event reference-count tracker primitive with live bitmap and underflow/overflow/bounds assertions. Core-wide event wiring remains explicitly pending.


## Phase 26 — Reference tracker integration

See `docs/PHASE26_REFERENCE_TRACKER_INTEGRATION.md`. Reference acquire/release events are now wired for rename mappings, unresolved integer issue-queue operands, and ROB destination metadata, with debug counters exported through the frontend/dispatch wrapper.


## Phase 27 — Reference-aware physical-register reclamation

See `docs/PHASE27_REFERENCE_AWARE_RECLAMATION.md` for final-reference reclaim pulses, free-list gating, checkpoint snapshot propagation, and the remaining untracked consumer domains.


## Phase 28 — External consumer reference lifecycle interface

Added an eight-lane configurable external acquire/release event interface, routed from `mx64_frontend_dispatch` through the control/dispatch wrappers into the shared physical-register reference tracker. See `docs/PHASE28_EXTERNAL_CONSUMER_LIFECYCLE.md` for the mandatory consumer protocol and current integration boundary. This is event plumbing, not a claim that absent branch/LSU/FP consumers are already wired.


## Phase 29 — Branch execution reference lifecycle

See `docs/PHASE29_BRANCH_REFERENCE_LIFECYCLE.md`. Accepted branch/jump dispatches now retain both source physical tags until resolution; mispredict recovery releases younger branch records and trap flush releases all outstanding branch references. The branch execution datapath remains an external interface.

## Phase 30 — LSU reference lifecycle

Phase 30 adds a load/store queue reference-lifecycle manager and connects load address-base and store address/data physical-tag ownership events to the shared reference tracker. Queue slots release references on completion, replay discard, or precise trap flush. See `docs/PHASE30_LSU_REFERENCE_LIFECYCLE.md` for the producer contract and limitations. This is not a complete LSU datapath.

## Phase 31 — Memory ordering and store-to-load forwarding

Phase 31 adds a standalone conservative store-queue ordering primitive with unresolved address/data tracking, older-store load blocking, youngest-older-store per-byte forwarding, retirement, and flush behavior. It is not yet wired into the frontend wrapper or a complete LSU datapath. See `docs/PHASE31_MEMORY_ORDERING.md` for byte-lane and sequence-number contracts.


## Phase 32 — AGU and LSU pipeline integration slice

Phase 32 adds `mx64_address_generation_unit.sv` for byte effective-address generation, 1/2/4/8-byte masks, and natural-alignment fault detection. `mx64_lsu_pipeline.sv` composes the AGU, Phase 31 memory-ordering/store-forwarding unit, and Phase 30 LSU physical-tag lifecycle manager behind a single-request interface. Loads wait on older unresolved stores; stores require both lifecycle and ordering queue capacity. The module exports forwarding bytes and queue-slot identities. Cache/TLB/bus integration, load response assembly, speculative violation replay, fences/atomics, and top-level core wiring remain future work. See `docs/PHASE32_AGU_LSU_PIPELINE.md`.

## Phase 33 — Blocking L1D cache controller

Phase 33 replaces the empty `cache_hierarchy` placeholder with a blocking, direct-mapped, write-back/write-allocate L1D controller (64-byte lines, 16 sets by default). It supports request/response backpressure, dirty-victim writeback, line refill, store-miss byte merge, and memory-error propagation. The implementation uses behavioral flop arrays, not foundry SRAM macros. L1I/L2, coherence, TLB, LSU-to-cache end-to-end wiring, clean/invalidate sequencing, and cache simulation remain future work. See `docs/PHASE33_L1D_CACHE_CONTROLLER.md`; `verification/unit/tb_cache_hierarchy.sv` is an unexecuted testbench scaffold.

## Phase 34 — LSU to L1D cache bridge

Phase 34 adds `rtl/memory/mx64_lsu_cache_bridge.sv`, which instantiates the
Phase 33 L1D controller, forwards its full-line memory interface, latches
accepted request metadata, and formats aligned cache-word responses into
signed/unsigned byte, halfword, word, and doubleword load results. This is a
physical-address adapter boundary: translation, ordering, forwarding, replay,
and committed-store scheduling remain upstream responsibilities. The
Phase 32 LSU is not yet fully instantiated end-to-end with this bridge; see
`docs/PHASE34_LSU_L1D_INTEGRATION.md`. The new testbench is an unexecuted
scaffold, not a simulation result.

## Phase 35 — LSU/L1D cache subsystem integration

Phase 35 adds `rtl/memory/mx64_lsu_cache_subsystem.sv`, composing the LSU
request/ordering/reference slice with the L1D bridge. Loads are backpressured
until the single-outstanding cache port is ready. Speculative stores remain in
the LSU queues and are sent to L1D only through an explicit in-order
`store_commit_*` handshake. Committed stores receive cache-port priority, and
store-order retirement occurs only when the cache accepts the write request.
Response transaction class and lifecycle slot are retained across response
backpressure. LSU forwarding metadata remains available for the downstream
load-result merge path.

This remains an integration slice: physical translation and permissions,
load forwarding merge/bypass, response-driven lifecycle completion, replay,
flush draining, atomics, MMIO policy, non-blocking misses, coherence, L1I/L2,
and full core retirement wiring remain incomplete. See
`docs/PHASE35_LSU_CACHE_SUBSYSTEM.md`. The Phase 35 testbench is an unexecuted
scenario scaffold; no HDL compile/elaboration/simulation/formal/synthesis is
claimed.


## Phase 36.2 — committed-store error lifecycle
Phase 36.2 adds an explicit store-error acknowledgement channel at the
LSU/cache subsystem boundary. A failed committed store cannot be silently
consumed: the normal response consumer and platform error sink must both
acknowledge it. The platform sink and functional CPU top-level are still
not integrated. See `docs/PHASE36_2_STORE_ERROR_HANDSHAKE.md`.


## Phase 37.1 — Research-Guided Memory Scheduling and ROB Completion

- Loads/stores are routed to a dedicated, oldest-first memory issue queue rather than the integer ALU queue.
- Wakeup and physical-reference acquire/release are integrated for the new queue.
- Memory writeback reaches the PRF; a separate memory completion lane reaches the ROB.
- The LSU issue/response adapter, ISA size/sign mapping, branch execution unit, and full `mx64_top` remain open integration gates.
- Research and test instructions: `docs/PHASE37_1_RESEARCH_AND_ARCHITECTURE.md`, `docs/PHASE37_1_INTERFACE_MAP.md`, `verification/phase37_1/README.md`.

This increment is static-validated but not HDL-compiled or simulated in the current tool environment.


## Phase 37.1 — Research-Guided Memory Dispatch

Loads/stores are routed to a dedicated oldest-first memory issue queue rather
than the integer ALU issue queue. Its wakeup/reference lifecycle joins the
existing physical-register tracker. A dedicated memory completion lane returns
memory completion and fault metadata to the ROB; successful load writeback is
separate. See the Phase 37.1 research report and interface map.

The LSU response-to-ROB adapter, frozen load/store decode contract, branch
execution integration, functional CPU top, and HDL simulation remain open.


## Phase 37.2 — LSU-to-ROB Transaction Adapter

Added a standalone LSU/ROB transaction adapter that retains full ROB identity
across load responses and store commit. It includes load writeback/fault mapping,
store commit authorization, stale load response suppression after precise flush,
and an external retirement gate. It is not yet instantiated in a functional CPU
top. Branch-mispredict recovery propagation into LSU remains an explicit blocker.
See `docs/PHASE37_2_LSU_ROB_ADAPTER.md`.

## Phase 37.3 — LSU Selective Recovery

Sequence-based branch recovery now selectively prunes younger speculative stores, releases their retained source references, and marks younger in-flight loads killed while preserving their cache-response identity. See `docs/PHASE37_3_LSU_SELECTIVE_RECOVERY.md` and `PHASE37_3_EXECUTION_REPORT.md`. Static checks only; HDL compilation/simulation/formal verification has not been run.


## Phase 37.4 — research review and recovery hardening

Reviewed MIPS R10000, Alpha 21264, Berkeley BOOM, and the MICRO-36 LSQ paper. Connected branch recovery to the LSU physical-reference lifecycle, passed actual store sequence numbers into that lifecycle, and changed memory age comparisons to wrap-safe signed-difference comparisons. See `docs/PHASE37_4_RESEARCH_AND_RECOVERY_HARDENING.md` and `PHASE37_4_EXECUTION_REPORT.md`. Static/software checks pass; this does **not** complete or verify the functional CPU top. HDL compile/simulation/formal/synthesis remain unrun.

## Phase 37.5 — Core integration boundary

`rtl/core/mx64_top.sv` now instantiates the frontend/rename/ROB/integer backend composite and the LSU/ROB adapter, and connects the memory issue, load completion/writeback, store retirement gate, branch recovery, LSU physical-reference lifecycle, and external memory interfaces. This is an integration boundary, not yet a verified bootable CPU: branch execution remains external, address translation is identity-only, and CSR/MMU/interrupt/debug/SoC integration remains open. See `docs/PHASE37_5_CORE_INTEGRATION.md` and `PHASE37_5_EXECUTION_REPORT.md`. Static checks do not constitute HDL compilation or simulation.

## Phase 37.6 — Low-storage RTL verification

The project now includes `.github/workflows/rtl-verification.yml`, which installs
Verilator on a temporary GitHub-hosted Ubuntu runner and lints `mx64_top` without
requiring WSL, Docker, or a local HDL installation. See
`docs/LOW_STORAGE_VERIFICATION.md`. This workflow has been statically checked but
has not yet been executed on GitHub; RTL compilation and simulation remain unverified.
