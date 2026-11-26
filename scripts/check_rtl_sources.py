#!/usr/bin/env python3
"""Conservative RTL source checks; not a SystemVerilog parser or compiler."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
module_defs = {}
for path in sorted(RTL.rglob("*.sv")):
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", text, re.MULTILINE):
        module_defs.setdefault(match.group(1), []).append(path.relative_to(ROOT).as_posix())
duplicates = {name: files for name, files in module_defs.items() if len(files) > 1}
if duplicates:
    details = "; ".join(f"{name}: {', '.join(files)}" for name, files in duplicates.items())
    raise SystemExit(f"FAIL: duplicate SystemVerilog module declarations: {details}")

pkg = (RTL / "common/mx64_pkg.sv").read_text(encoding="utf-8")
rob = (RTL / "scheduler/reorder_buffer.sv").read_text(encoding="utf-8")
backend = (RTL / "core/mx64_integer_backend.sv").read_text(encoding="utf-8")
iq = (RTL / "scheduler/issue_queue.sv").read_text(encoding="utf-8")
prf = (RTL / "rename/physical_regfile.sv").read_text(encoding="utf-8")
rename = (RTL / "rename/rename_unit.sv").read_text(encoding="utf-8")
dispatch = (RTL / "core/mx64_dispatch_controller.sv").read_text(encoding="utf-8")
checkpoint = (RTL / "rename/branch_checkpoint_manager.sv").read_text(encoding="utf-8")
trap = (RTL / "core/mx64_trap_controller.sv").read_text(encoding="utf-8")
csr = (RTL / "csr/mx64_csr_file.sv").read_text(encoding="utf-8")
checks = {
    "package defines 6-bit ROB index": "ROB_INDEX_W = 6" in pkg,
    "package defines 16-bit ROB epoch": "ROB_EPOCH_W = 16" in pkg,
    "ROB tag is package-width": "logic [ROB_TAG_W-1:0] rob_tag;" in pkg,
    "issue uop carries global dispatch sequence": "logic [31:0] seq_num;" in pkg,
    "ROB uses parameterized epoch vector": "logic [DEPTH-1:0][GEN_W-1:0] generation_q;" in rob,
    "ROB compares full completion epoch": "complete_tag[c][FULL_TAG_W-1:TAG_W] == generation_q[s]" in rob,
    "ROB has full-tag branch query": "tag_query_found = 1'b1;" in rob and "query_slot = bump(query_slot);" in rob,
    "ROB has selective recovery lookup": "recover_found = 1'b1;" in rob and "recover_position = age;" in rob,
    "ROB preserves branch and older instructions": "recover_keep_count = (TAG_W+1)'(age + 1);" in rob,
    "ROB kills only entries younger than the branch": "age > recover_position" in rob,
    "ROB recovery redirects tail after branch": "tail_q <= bump(recover_slot);" in rob,
    "ROB suppresses allocate and retire during recovery": "if (!recover_valid && alloc_valid[lane]" in rob and "if (!recover_valid && count_q != 0" in rob,
    "ROB occupancy uses counted alloc/retire delta": "count_next = count_q + (TAG_W+1)'(alloc_count) - (TAG_W+1)'(retire_count);" in rob,
    "ROB explicitly constrains dual-wide implementation": 'if (WIDTH != 2) $error("Initial ROB implementation requires WIDTH=2")' in rob,
    "free-list restore permanently reserves only p0": "(restore_free_bitmap | reclaim_bitmap) &\n                {{(PHYS_REGS-1){1'b1}}, 1'b0}" in (RTL / "rename/free_list.sv").read_text(encoding="utf-8"),
    "free-list exports per-lane post-allocation snapshots": "free_bitmap_after_alloc" in (RTL / "rename/free_list.sv").read_text(encoding="utf-8"),
    "free-list can reclaim displaced initial mappings": "for (j = 1; j < PHYS_REGS; j++) begin" in (RTL / "rename/free_list.sv").read_text(encoding="utf-8"),
    "rename snapshots RAT after each accepted lane": "out_rat_snapshot[lane] = rat_d;" in rename,
    "rename routes recovery restore to RAT and free list": "flush || recover" in rename,
    "rename exports exact lane free-list snapshots": "out_free_snapshot = free_bitmap_after_alloc;" in rename,
    "rename restore forces x0 mapping": "rat_q[0] <= '0;" in rename,
    "issue queue explicitly constrains dual-wide implementation": 'if (WIDTH != 2) $error("Initial issue_queue implementation requires WIDTH=2")' in iq,
    "issue queue kills by global dispatch sequence": "is_younger(seq_t'(entry_q[e].seq_num), seq_t'(recover_seq))" in iq,
    "issue queue freezes selection and enqueue during recovery": "!recover_valid && valid_q[e]" in iq and "!recover_valid && free_slots > 0" in iq,
    "issue queue immediately blocks selection and enqueue on flush": "!flush && !recover_valid && valid_q[e]" in iq and "!flush && !recover_valid && free_slots > 0" in iq,
    "backend forwards recovery sequence into issue queue": ".recover_seq(recover_seq)" in backend,
    "backend derives epoch width from tag contract": ".GEN_W(ROB_TAG_W - $clog2(ROB_DEPTH))" in backend,
    "PRF bypass iterates high-to-low so port 0 wins collisions": "for (int w = WRITE_PORTS-1; w >= 0; w--)" in prf,
    "PRF sequential write priority documents port 0 winner": "Port 0 has priority if both write ports target the same entry." in prf,
    "ROB stores new physical destination": "prd_q[alloc_idx[a]] <= alloc_prd[a];" in rob,
    "ROB stores previous physical destination": "old_prd_q[alloc_idx[a]] <= alloc_old_prd[a];" in rob,
    "ROB returns physical destination at retirement": "retire_prd[0] = prd_q[head_q];" in rob,
    "ROB returns previous physical destination at retirement": "retire_old_prd[0] = old_prd_q[head_q];" in rob,
    "rename unit maintains committed RAT": "logic [ARCH_REGS-1:0][PHYS_W-1:0] committed_rat_q;" in rename,
    "committed RAT updates from commit metadata": "committed_rat_q[commit_map_arch_rd[lane]] <= commit_map_new_prd[lane];" in rename,
    "dispatch commits only accepted non-exception destination writes": "!retire_exception[lane] && retire_kind[lane][2]" in dispatch and "(retire_rd[lane] != '0)" in dispatch,
    "dispatch passes retired physical destination to rename commit map": ".commit_map_new_prd(retire_prd)" in dispatch,
    "dispatch connects ROB physical destination metadata": ".rob_alloc_prd(rob_alloc_prd)" in dispatch,
    "dispatch exposes dedicated branch-unit path": "output logic [WIDTH-1:0] branch_dispatch_valid" in dispatch,
    "dispatch excludes branch, memory and exception uops from integer issue queue":
        "~control_transfer & ~memory_operation & ~dispatch_exception" in dispatch and
        "memory_dispatch_valid = rename_out_valid" in dispatch,
    "dispatch captures branch ROB tag and seq": "checkpoint_capture_tag = rob_alloc_tag[0];" in dispatch and "checkpoint_capture_seq = dispatch_seq_lane[0];" in dispatch,
    "dispatch captures per-lane RAT and free state": "checkpoint_capture_rat = rename_rat_snapshot[0];" in dispatch and "checkpoint_capture_free = rename_free_snapshot[0];" in dispatch,
    "dispatch connects branch resolve tag query": ".tag_query_valid(branch_resolve_valid)" in dispatch,
    "dispatch restores rename state on misprediction": ".recover(recovery_valid)" in dispatch,
    "dispatch exports frontend redirect PC": "assign recovery_pc = branch_actual_target;" in dispatch,
    "ROB suppresses younger retirement when head faults": "!exception_q[head_q]" in rob,
    "ROB retains second-lane retirement only after accepted head": "retire_fire[0]" in rob,
    "checkpoint manager stores ROB tag": "rob_tag_q[free_slot] <= capture_rob_tag;" in checkpoint,
    "checkpoint manager stores dispatch sequence": "seq_q[free_slot] <= capture_seq;" in checkpoint,
    "checkpoint manager stores speculative RAT snapshots": "rat_q[free_slot] <= capture_rat;" in checkpoint,
    "checkpoint manager stores free-list snapshots": "free_q[free_slot] <= capture_free_bitmap;" in checkpoint,
    "checkpoint recovery restores selected RAT": "restore_rat = rat_q[order_q[resolve_pos]];" in checkpoint,
    "checkpoint recovery restores selected free bitmap": "restore_free_bitmap = free_q[order_q[resolve_pos]];" in checkpoint,
    "checkpoint recovery discards target and younger checkpoints": "if (i >= resolve_pos && i < count_q)" in checkpoint,
    "checkpoint manager preserves older checkpoints": "count_q <= COUNT_W'(resolve_pos);" in checkpoint,
    "correct branch resolution releases only its checkpoint": "valid_q[order_q[resolve_pos]] <= 1'b0;" in checkpoint and "order_q[i] <= order_q[i+1];" in checkpoint,
    "checkpoint resolution requires explicit valid handshake": "resolve_fire = resolve_valid && resolve_found && resolve_tag_live" in checkpoint,
    "checkpoint manager merges final-reference reclaim into every active snapshot": "if (reclaim_bitmap[r]) free_q[cp][r] <= 1'b1;" in checkpoint,
    "backend uses extra ROB completion port for branch unit": "rob_complete_valid[WIDTH] = branch_complete_valid;" in backend,
    "controller exposes branch-resolution backpressure": "assign branch_resolve_ready = branch_resolve_tag_found && branch_checkpoint_found;" in dispatch,
    "controller exports recovery sequence": "assign recovery_seq = checkpoint_recover_seq;" in dispatch,
    "branch next PC and destination result are separate": "input logic [63:0] branch_result_value" in dispatch and ".branch_complete_value(branch_result_value)" in dispatch,
    "package expands synchronous exception classes": "EXC_STORE_PAGE_FAULT = 4'd12" in pkg,
    "package maps exception enums to architectural causes": "function automatic logic [63:0] mx64_exception_cause" in pkg and "privilege == 2'b11" in pkg and "privilege == 2'b00" in pkg,
    "decoded uop carries mtval metadata": "logic [63:0] exception_value" in pkg,
    "ROB stores allocation-time exception status": "done_q[alloc_idx[a]] <= alloc_exception[a];" in rob,
    "ROB stores allocation-time exception code and value": "exception_code_q[alloc_idx[a]] <= alloc_exception[a]" in rob and "exception_value_q[alloc_idx[a]] <= alloc_exception[a]" in rob,
    "ROB propagates completion-time exception metadata": "complete_exception_code[c]" in rob and "complete_exception_value[c]" in rob,
    "ROB returns exception code and mtval at retirement": "retire_exception_code[0] = exception_code_q[head_q];" in rob and "retire_exception_value[0] = exception_value_q[head_q];" in rob,
    "dispatch sends valid decode exceptions directly to ROB": "dispatch_exception[lane] = decoded_valid[lane]" in dispatch and "decoded_uop[lane].exception != EXC_NONE" in dispatch and "~dispatch_exception" in dispatch,
    "dispatch bypasses execution units for exception uops": "backend_dispatch_valid = rename_out_valid" in dispatch and "branch_dispatch_valid = rename_out_valid" in dispatch and "dispatch_exception" in dispatch,
    "dispatch exposes exception metadata to trap boundary": "output logic [WIDTH-1:0][3:0] retire_exception_code" in dispatch and "output logic [WIDTH-1:0][63:0] retire_exception_value" in dispatch,
    "rename reconstructs committed free bitmap": "committed_free_bitmap = ~committed_used_bitmap;" in rename and "committed_free_bitmap[0] = 1'b0" in rename,
    "dispatch exports committed free bitmap for trap restore": "committed_free_bitmap_debug" in dispatch,
    "trap controller blocks a lane-1 exception": "retire_valid[1] && retire_exception[1]" in trap and "rob_retire_ready[1] = 1'b0;" in trap,
    "trap controller takes only a faulting ROB head": "head_exception = retire_valid[0] && retire_exception[0];" in trap and "trap_valid = head_exception" in trap,
    "trap controller stalls unknown exception enums": "rob_retire_ready[0] = (mapped_cause != 64'hffff_ffff_ffff_ffff);" in trap,
    "trap controller maps cause and mtval": "mx64_exception_cause" in trap and "trap_value = retire_exception_value[0];" in trap,
    "trap controller flushes and redirects": "flush_speculative = trap_valid;" in trap and "redirect_pc = trap_vector;" in trap,
    "trap controller counts only normal retired instructions": "!retire_exception[lane]" in trap and "retired_count = retired_count + 2'd1;" in trap,
    "CSR instret accepts two-wide retirement count": "input  logic [1:0]        retired_count" in csr and "XLEN'(retired_count)" in csr,
    "CSR mcause uses exactly XLEN bits": "mcause <= {trap_is_interrupt, trap_cause[XLEN-2:0]};" in csr,
    "CSR mepc enforces four-byte instruction alignment": "mepc <= {trap_pc[XLEN-1:2], 2'b00};" in csr,
}


checks.update({
    "frontend has fetch request/response interface": "mem_req_valid" in (RTL / "frontend/mx64_fetch_unit.sv").read_text(encoding="utf-8") and "mem_resp_valid" in (RTL / "frontend/mx64_fetch_unit.sv").read_text(encoding="utf-8"),
    "fetch unit holds response under backpressure": "buffer_valid_q" in (RTL / "frontend/mx64_fetch_unit.sv").read_text(encoding="utf-8") and "if (out_fire)" in (RTL / "frontend/mx64_fetch_unit.sv").read_text(encoding="utf-8"),
    "fetch redirect drains stale outstanding response": "discard_response_q" in (RTL / "frontend/mx64_fetch_unit.sv").read_text(encoding="utf-8"),
    "fetch reset vector is explicit": "reset_pc" in (RTL / "frontend/mx64_fetch_unit.sv").read_text(encoding="utf-8"),
    "decoder emits illegal instruction exception": "uop_o.exception = EXC_ILLEGAL;" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8"),
    "decoder implements base ALU and memory classes": "6'h01" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8") and "6'h06" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8") and "6'h07" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8"),
    "decoder extracts branch/store rs2 from format field": "uop_o.rs2 = instruction[25:21];" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8"),
    "decoder sign-extends B and J displacement to 64 bits": "{{50{instruction[11]}" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8") and "{{36{instruction[25]}" in (RTL / "frontend/mx64_instruction_decoder.sv").read_text(encoding="utf-8"),
    "frontend instantiates branch predictor and decoder": "mx64_branch_predictor" in (RTL / "frontend/mx64_frontend.sv").read_text(encoding="utf-8") and "mx64_instruction_decoder" in (RTL / "frontend/mx64_frontend.sv").read_text(encoding="utf-8"),
    "frontend converts fetch access faults to decode exceptions": "EXC_INST_ACCESS_FAULT" in (RTL / "frontend/mx64_frontend.sv").read_text(encoding="utf-8"),
})


integrated = (RTL / "core/mx64_frontend_dispatch.sv").read_text(encoding="utf-8")
checks.update({
    "frontend dispatch wrapper instantiates frontend and control subsystem": "mx64_frontend #(" in integrated and "mx64_control_subsystem #(" in integrated,
    "frontend dispatch wrapper routes decoded uop into lane zero": "decoded_uop_lanes[0] = decoded_uop;" in integrated and "decoded_valid_lanes[0] = decoded_valid;" in integrated,
    "frontend dispatch wrapper keeps lane one inactive for single-wide frontend": "decoded_valid_lanes = '0;" in integrated and "decoded_valid_lanes[1]" not in integrated,
    "frontend dispatch wrapper routes operand readiness and values": ".src1_ready(operand1_ready)" in integrated and ".src2_value(operand2_value)" in integrated,
    "frontend dispatch wrapper routes branch execution interface": ".branch_dispatch_uop(branch_unit_uop)" in integrated and ".branch_resolve_tag" in integrated,
    "frontend redirect waits for accepted branch resolution": "branch_resolve_valid && branch_resolve_ready && branch_mispredict" in integrated,
    "trap redirect has priority over branch redirect": "trap_redirect_valid ? trap_redirect_pc : branch_actual_next_pc" in integrated,
    "branch predictor training uses resolved PC and actual direction": ".branch_resolve_pc(branch_resolve_pc)" in integrated and ".branch_resolve_taken(branch_resolve_taken)" in integrated,
})


prf = (RTL / "rename/physical_regfile.sv").read_text(encoding="utf-8")
dispatch = (RTL / "core/mx64_dispatch_controller.sv").read_text(encoding="utf-8")
backend = (RTL / "core/mx64_integer_backend.sv").read_text(encoding="utf-8")
wrapper = (RTL / "core/mx64_frontend_dispatch.sv").read_text(encoding="utf-8")
checks.update({
    "PRF marks architectural register bank initialized after reset": "if (i < ARCH_REGS) valid_q[i] <= 1'b1;" in prf,
    "dispatch exports renamed physical source tags": "output logic [WIDTH-1:0][PHYS_W-1:0] source1_phys_tag" in dispatch and "assign source1_phys_tag = prs1;" in dispatch,
    "integer backend exports destination writeback buses": "output logic [WIDTH-1:0] int_wb_valid" in backend and "assign int_wb_valid = completion_valid & completion_writes_dst;" in backend,
    "frontend dispatch instantiates integer PRF": "physical_regfile #(" in wrapper and "u_integer_prf" in wrapper,
    "frontend dispatch uses four PRF read ports for two source operands per lane": ".READ_PORTS(4)" in wrapper and "prf_raddr[2*lane+1] = source2_phys_tag[lane];" in wrapper,
    "frontend dispatch writes both integer completion lanes to PRF": "prf_wen[1:0] = int_wb_valid;" in wrapper and "prf_waddr[1:0] = int_wb_tag;" in wrapper,
    "PRF valid bits provide operand readiness": "operand1_ready[lane] = prf_rvalid[2*lane];" in wrapper and "operand2_ready[lane] = prf_rvalid[2*lane+1];" in wrapper,
})


iq = (RTL / "scheduler/issue_queue.sv").read_text(encoding="utf-8")
cluster = (RTL / "execution/integer_execution_cluster.sv").read_text(encoding="utf-8")
backend = (RTL / "core/mx64_integer_backend.sv").read_text(encoding="utf-8")
dispatch = (RTL / "core/mx64_dispatch_controller.sv").read_text(encoding="utf-8")
control = (RTL / "core/mx64_control_subsystem.sv").read_text(encoding="utf-8")
wrapper = (RTL / "core/mx64_frontend_dispatch.sv").read_text(encoding="utf-8")
checks.update({
    "issue queue supports independent wakeup width": "parameter int WAKEUP_WIDTH = WIDTH" in iq and "input  logic [WAKEUP_WIDTH-1:0] wakeup_valid" in iq,
    "issue queue compares all wakeup sources": "w < WAKEUP_WIDTH" in iq,
    "integer execution cluster accepts external wakeup": "external_wakeup_valid" in cluster and "external_wakeup_tag" in cluster and "external_wakeup_data" in cluster,
    "integer execution cluster merges integer and branch wakeups": "wakeup_valid[WIDTH] = external_wakeup_valid;" in cluster,
    "integer execution cluster configures extra wakeup lane": ".WAKEUP_WIDTH(WIDTH+1)" in cluster,
    "integer backend forwards branch wakeup": ".external_wakeup_valid(branch_wb_valid)" in backend and ".external_wakeup_data(branch_wb_data)" in backend,
    "dispatch controller routes branch writeback": ".branch_wb_valid, .branch_wb_tag, .branch_wb_data" in dispatch,
    "control subsystem exposes branch writeback": "input logic branch_wb_valid" in control and ".branch_wb_valid, .branch_wb_tag, .branch_wb_data" in control,
    "frontend PRF provides branch and memory-result write ports":
        ".WRITE_PORTS(4)" in wrapper and
        "prf_wen[2] = branch_link_wb_valid;" in wrapper and
        "prf_wen[3] = memory_wb_valid;" in wrapper,
    "branch link writeback reaches PRF with physical destination tag": "prf_waddr[2] = branch_link_wb_tag;" in wrapper and "prf_wdata[2] = branch_link_result;" in wrapper,
})


exec_cluster = (RTL / "execution/integer_execution_cluster.sv").read_text(encoding="utf-8")
checks.update({
    "completion stage records dispatch sequence": "completion_seq_q[lane] <= issued_uop[lane].seq_num;" in exec_cluster,
    "recovery cycle suppresses younger pending completion": "completion_killed[lane] = 1'b1;" in exec_cluster and "completion_valid_q & ~completion_killed" in exec_cluster,
    "recovery prevents stale PRF writeback": "completion_writes_dst_q & ~completion_killed" in exec_cluster,
    "recovery clears completion stage after consuming surviving older results": "end else if (recover_valid) begin\n      // Current-cycle outputs are selectively filtered below." in exec_cluster,
})


free_list = (RTL / "rename/free_list.sv").read_text(encoding="utf-8")
checks.update({
    "free list validates allocated-before-free state": "!free_q[free_tag[i]]" in free_list and "free_accept[i]" in free_list,
    "free list ignores invalid duplicate/stale frees": "if (free_accept[i]) begin" in free_list,
    "free list asserts duplicate free tags": "duplicate free tag in one cycle" in free_list,
    "free list asserts stale free attempts": "duplicate or stale physical-register free" in free_list,
    "free list preserves p0 reservation on restore": "(restore_free_bitmap | reclaim_bitmap) &\n                {{(PHYS_REGS-1){1'b1}}, 1'b0}" in free_list,
    "free list delays reuse until after final-reference release": "if (reclaim_bitmap[j] && !free_q[j])" in free_list and "after allocation selection" in free_list,
})


ref_tracker = (RTL / "rename/physical_register_reference_tracker.sv").read_text(encoding="utf-8")
checks.update({
    "reference tracker supports multi-source acquire and release": "ACQUIRE_WIDTH = 4" in ref_tracker and "RELEASE_WIDTH = 4" in ref_tracker,
    "reference tracker counts acquire and release deltas per tag": "acquire_delta[acquire_tag[a]]++" in ref_tracker and "release_delta[release_tag[d]]++" in ref_tracker,
    "reference tracker exports live-reference bitmap": "referenced_bitmap[r] = (reference_count[r] != '0)" in ref_tracker,
    "reference tracker emits final-reference reclaim pulse": "next_count[r] == 0" in ref_tracker and "reclaim_bitmap[r]" in ref_tracker,
    "reference tracker detects underflow": "reference-count underflow" in ref_tracker,
    "reference tracker detects overflow": "reference-count overflow" in ref_tracker,
    "reference tracker validates event tag bounds": "acquire tag out of range" in ref_tracker and "release tag out of range" in ref_tracker,
    "reference tracker supports coordinated clear": "else if (clear_all)" in ref_tracker,
})


ref_tracker = (RTL / "rename/physical_register_reference_tracker.sv").read_text(encoding="utf-8")
cluster = (RTL / "execution/integer_execution_cluster.sv").read_text(encoding="utf-8")
backend = (RTL / "core/mx64_integer_backend.sv").read_text(encoding="utf-8")
dispatch = (RTL / "core/mx64_dispatch_controller.sv").read_text(encoding="utf-8")
iq = (RTL / "scheduler/issue_queue.sv").read_text(encoding="utf-8")
checks.update({
    "issue queue acquires unresolved source references on enqueue": "ref_acquire_valid[2*p] = 1'b1;" in iq and "ref_acquire_valid[2*p+1] = 1'b1;" in iq,
    "issue queue releases unresolved references on wakeup": "ref_release_valid[2*e] = 1'b1;" in iq and "ref_release_valid[2*e+1] = 1'b1;" in iq,
    "issue queue releases retained references on flush": "if (flush || (recover_valid && recover_kill_mask[e]))" in iq,
    "issue queue preserves wakeups for older entries during recovery": "entry_q[e] <= effective_entry[e];" in iq and "else if (valid_q[e]) begin" in iq,
    "integer cluster exports IQ reference lifecycle events": ".ref_acquire_valid, .ref_acquire_tag" in cluster and ".ref_release_valid, .ref_release_tag" in cluster,
    "backend combines IQ, ROB and RAT mapping reference domains": "REF_ACQUIRE_WIDTH = 2*WIDTH + WIDTH + WIDTH" in backend and "REF_RELEASE_WIDTH = 2*IQ_DEPTH + WIDTH + WIDTH" in backend,
    "backend acquires ROB destination reference on allocation": "ref_acquire_valid[2*WIDTH + lane] = 1'b1;" in backend,
    "backend acquires architectural mapping reference on allocation": "ref_acquire_valid[3*WIDTH + lane] = 1'b1;" in backend,
    "backend releases ROB destination reference on retirement": "ref_release_valid[2*IQ_DEPTH + lane] = 1'b1;" in backend,
    "backend releases displaced mapping reference on commit": "ref_release_valid[2*IQ_DEPTH + WIDTH + lane] = 1'b1;" in backend,
    "backend instantiates integrated physical reference tracker": "u_physical_reference_tracker" in backend and ".acquire_valid(ref_acquire_valid)" in backend and ".release_valid(ref_release_valid)" in backend,
    "tracker seeds initial architectural mappings": "INIT_ARCH_REGS(32)" in backend and "if (r < INIT_ARCH_REGS)" in ref_tracker,
    "dispatch connects commit frees to mapping reference releases": ".map_release_valid(commit_free_valid)" in dispatch,
})


external_backend = (RTL / "core/mx64_integer_backend.sv").read_text(encoding="utf-8")
external_dispatch = (RTL / "core/mx64_dispatch_controller.sv").read_text(encoding="utf-8")
external_control = (RTL / "core/mx64_control_subsystem.sv").read_text(encoding="utf-8")
external_wrapper = (RTL / "core/mx64_frontend_dispatch.sv").read_text(encoding="utf-8")
checks.update({
    "backend exposes configurable external consumer acquire/release lanes": "parameter int EXTERNAL_REF_WIDTH = 8" in external_backend and "external_ref_acquire_valid" in external_backend and "external_ref_release_valid" in external_backend,
    "backend nets external acquire events into shared tracker": "ref_acquire_valid[4*WIDTH +: EXTERNAL_REF_WIDTH] = external_ref_acquire_valid;" in external_backend,
    "backend nets external release events into shared tracker": "ref_release_valid[2*IQ_DEPTH + 2*WIDTH +: EXTERNAL_REF_WIDTH] = external_ref_release_valid;" in external_backend,
    "dispatch controller forwards external lifecycle events": ".external_ref_acquire_valid, .external_ref_acquire_tag" in external_dispatch and ".external_ref_release_valid, .external_ref_release_tag" in external_dispatch,
    "control subsystem forwards external lifecycle events": ".external_ref_acquire_valid, .external_ref_acquire_tag" in external_control and ".external_ref_release_valid, .external_ref_release_tag" in external_control,
    "frontend wrapper exposes external lifecycle boundary": "input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_acquire_valid" in external_wrapper and "input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_release_valid" in external_wrapper,
    "frontend wrapper forwards merged lifecycle events to control subsystem": ".external_ref_acquire_valid(tracker_acquire_valid)" in external_wrapper and ".external_ref_release_valid(tracker_release_valid)" in external_wrapper,
})

branch_lifecycle = (RTL / "execution/branch_reference_lifecycle.sv").read_text(encoding="utf-8")
checks.update({
    "branch lifecycle acquires both source tags only on accepted control-transfer dispatch": "dispatch_valid[lane] && dispatch_ready[lane]" in branch_lifecycle and "dispatch_uop[lane].is_branch || dispatch_uop[lane].is_jump" in branch_lifecycle,
    "branch lifecycle retains ROB identity and sequence for each consumer": "rob_tag_d[i] = dispatch_uop[lane].rob_tag;" in branch_lifecycle and "seq_d[i] = dispatch_uop[lane].seq_num;" in branch_lifecycle,
    "branch resolution releases matching retained source tags": "rob_tag_q[i] == resolve_tag" in branch_lifecycle and "release_tag[2*i] = src1_q[i];" in branch_lifecycle,
    "mispredict releases younger branch consumers": "mispredict && resolve_found" in branch_lifecycle and "$signed(seq_q[i] - resolve_seq) > 0" in branch_lifecycle,
    "trap flush releases all retained branch operands": "flush_all ||" in branch_lifecycle,
    "frontend wrapper merges branch lifecycle events into shared tracker": "u_branch_reference_lifecycle" in external_wrapper and "tracker_release_valid[EXTERNAL_REF_WIDTH +: 2*ROB_DEPTH] = branch_ref_release_valid;" in external_wrapper,
    "frontend wrapper sizes tracker event buses for all retained branch operands": "TRACKER_REF_WIDTH = EXTERNAL_REF_WIDTH + 2*ROB_DEPTH" in external_wrapper,
})

lsu_lifecycle = (RTL / "memory/lsu_reference_lifecycle.sv").read_text(encoding="utf-8")
frontend_wrapper = (RTL / "core/mx64_frontend_dispatch.sv").read_text(encoding="utf-8")
checks.update({
    "LSU lifecycle tracks load and store queue slots": "load_valid_q" in lsu_lifecycle and "store_valid_q" in lsu_lifecycle,
    "LSU load retains address-base physical tag": "acquire_tag[0] = load_base_tag" in lsu_lifecycle,
    "LSU store retains address and data physical tags": "acquire_tag[2] = store_base_tag" in lsu_lifecycle and "acquire_tag[3] = store_data_tag" in lsu_lifecycle,
    "LSU releases references on completion": "load_done_fire" in lsu_lifecycle and "store_done_fire" in lsu_lifecycle,
    "LSU releases references on replay": "load_replay_fire" in lsu_lifecycle and "store_replay_fire" in lsu_lifecycle,
    "LSU releases all retained references on trap flush": "flush_all || (load_done_fire" in lsu_lifecycle and "flush_all || (recover_valid && seq_younger(store_seq_q[i], recover_seq))" in lsu_lifecycle and "flush_all || (load_done_fire" in lsu_lifecycle,
    "LSU rejects completion for inactive queue slots": "LSU load completion references an inactive slot" in lsu_lifecycle and "LSU store completion references an inactive slot" in lsu_lifecycle,
    "frontend wrapper instantiates LSU lifecycle manager": "u_lsu_reference_lifecycle" in frontend_wrapper,
    "frontend wrapper merges LSU acquire events": "tracker_acquire_valid[EXTERNAL_REF_WIDTH + 2*WIDTH +: 4] = lsu_ref_acquire_valid;" in frontend_wrapper,
    "frontend wrapper merges LSU release events": "tracker_release_valid[EXTERNAL_REF_WIDTH + 2*ROB_DEPTH +: 4*LSU_QUEUE_DEPTH] = lsu_ref_release_valid;" in frontend_wrapper,
    "LSU queue depth contributes to tracker event capacity": "EXTERNAL_REF_WIDTH + 2*ROB_DEPTH + 4*LSU_QUEUE_DEPTH" in frontend_wrapper,
})



memory_ordering = (RTL / "memory/memory_ordering_unit.sv").read_text(encoding="utf-8")
checks.update({
    "memory ordering unit has parameterized store queue": "parameter int DEPTH = 16" in memory_ordering and "logic [DEPTH-1:0] valid_q" in memory_ordering,
    "memory ordering unit supports unresolved store address and resolution": "store_addr_resolve_valid" in memory_ordering and "addr_valid_q[store_addr_resolve_slot] <= 1'b1" in memory_ordering,
    "memory ordering unit supports unresolved store data and resolution": "store_data_resolve_valid" in memory_ordering and "data_valid_q[store_data_resolve_slot] <= 1'b1" in memory_ordering,
    "memory ordering unit blocks on older unresolved store address": "if (!addr_valid_q[s])" in memory_ordering and "older_store_unresolved = 1'b1;" in memory_ordering,
    "memory ordering unit blocks on overlapping older unresolved store data": "if (!data_valid_q[s])" in memory_ordering,
    "memory ordering unit selects youngest older matching store per byte": "seq_younger(seq_q[s], best_seq)" in memory_ordering and "load_query_addr + ADDR_W'(b)" in memory_ordering,
    "memory ordering unit exports byte forwarding mask and data": "output logic [BYTE_LANES-1:0] forward_mask" in memory_ordering and "output logic [DATA_W-1:0] forward_data" in memory_ordering,
    "memory ordering unit distinguishes complete forwarding from load issue": "forward_complete = load_query_valid" in memory_ordering and "load_can_issue = load_query_valid && !older_store_unresolved" in memory_ordering,
    "memory ordering unit removes retired stores and flushes queue": "if (flush_all) valid_d = '0;" in memory_ordering and "if (retire_fire) valid_d[store_retire_slot] = 1'b0;" in memory_ordering,
    "memory ordering unit asserts invalid retire and resolve slots": "Memory ordering unit retires an inactive store slot" in memory_ordering and "Store address resolution references an inactive slot" in memory_ordering,
})

agu = (RTL / "memory/mx64_address_generation_unit.sv").read_text(encoding="utf-8")
lsu_pipe = (RTL / "memory/mx64_lsu_pipeline.sv").read_text(encoding="utf-8")
checks.update({
    "AGU computes byte effective address": "effective_addr = base_value + immediate;" in agu,
    "AGU supports 1/2/4/8-byte accesses": "size_log2 <= 3" in agu and "byte_mask[b] = (b < size_bytes);" in agu,
    "AGU detects natural alignment faults": "misaligned = !size_valid || ((effective_addr & (size_bytes - ADDR_W'(1))) != '0);" in agu,
    "LSU pipeline instantiates AGU": "u_agu" in lsu_pipe and "mx64_address_generation_unit" in lsu_pipe,
    "LSU pipeline instantiates memory ordering": "u_memory_ordering" in lsu_pipe and "memory_ordering_unit" in lsu_pipe,
    "LSU pipeline instantiates reference lifecycle": "u_lsu_refs" in lsu_pipe and "lsu_reference_lifecycle" in lsu_pipe,
    "LSU blocks loads behind older unresolved stores": "req_ready = load_alloc_ready && load_can_issue;" in lsu_pipe,
    "Stores require both queue slots": "req_ready = store_lifecycle_ready && store_order_ready;" in lsu_pipe,
    "LSU exports byte forwarding result": "load_forward_mask = forward_mask;" in lsu_pipe and "load_forward_data = forward_data;" in lsu_pipe,
    "LSU reports misalignment before acceptance": "req_fault_valid = req_valid && !flush_all && (!agu_size_valid || agu_misaligned);" in lsu_pipe,
    "LSU lifecycle ready defaults low without a free slot": "load_alloc_ready = 1'b0; store_alloc_ready = 1'b0;" in lsu_lifecycle,
    "Store-ordering ready defaults low without a free slot": "store_alloc_ready = 1'b0;" in memory_ordering,
})

cache = (RTL / "memory/cache_hierarchy.sv").read_text(encoding="utf-8")
cache_tb = (ROOT / "verification/unit/tb_cache_hierarchy.sv").read_text(encoding="utf-8")
checks.update({
    "cache hierarchy implements blocking direct-mapped L1D controller": "module cache_hierarchy #(" in cache and "typedef enum logic [2:0]" in cache,
    "cache tracks valid and dirty lines with tags": "logic [SETS-1:0] valid_q, dirty_q;" in cache and "tag_q [0:SETS-1]" in cache,
    "cache supports writeback and refill transactions": "S_WB_REQ" in cache and "S_WB_WAIT" in cache and "S_REFILL_REQ" in cache and "S_REFILL_WAIT" in cache,
    "cache writes back full dirty victim line": "mem_req_wdata = victim_line_q;" in cache and "mem_req_wstrb = '1;" in cache,
    "cache performs write allocate and merges store bytes on refill": "refill_line[(req_addr_q[OFFSET_W-1:3]*DATA_W)+(req_addr_q[2:0]+b)*8 +: 8]" in cache and "req_write_q ? refill_line : mem_rsp_rdata" in cache,
    "cache holds response until accepted": "S_RESP: if (rsp_valid && rsp_ready) state_q <= S_IDLE;" in cache and "$stable(rsp_rdata)" in cache,
    "cache propagates backing memory errors": "response_error_q <= 1'b1;" in cache and "output logic rsp_error" in cache,
    "cache exposes explicit maintenance invalidation": "input logic invalidate_all" in cache and "invalidate_pending_q" in cache and "(state_q == S_IDLE) && (invalidate_all || invalidate_pending_q)" in cache,
    "cache has directed testbench scaffold": "module tb_cache_hierarchy;" in cache_tb and "scenarios pending" in cache_tb,
})



lsu_cache_bridge = (RTL / "memory/mx64_lsu_cache_bridge.sv").read_text(encoding="utf-8")
lsu_cache_tb = (ROOT / "verification/unit/tb_lsu_cache_bridge.sv").read_text(encoding="utf-8")
checks.update({
    "LSU cache bridge instantiates the L1D cache controller": "cache_hierarchy #(" in lsu_cache_bridge and "u_l1d" in lsu_cache_bridge,
    "LSU cache bridge forwards physical request address and byte enables": ".req_addr(req_paddr)" in lsu_cache_bridge and ".req_byte_enable" in lsu_cache_bridge,
    "LSU cache bridge latches request metadata on accepted handshake": "else if (req_valid && req_ready)" in lsu_cache_bridge and "req_size_q <= req_size;" in lsu_cache_bridge and "req_offset_q <= req_paddr[2:0];" in lsu_cache_bridge,
    "LSU cache bridge extracts load data using latched byte offset": "assign shifted_load = cache_rsp_rdata >> byte_shift;" in lsu_cache_bridge and "byte_shift = {req_offset_q, 3'b000}" in lsu_cache_bridge,
    "LSU cache bridge supports signed and unsigned extension": "if (req_signed_q)" in lsu_cache_bridge and "{{(DATA_W-32){shifted_load[31]}}" in lsu_cache_bridge and "{{(DATA_W-32){1'b0}}" in lsu_cache_bridge,
    "LSU cache bridge propagates response backpressure and errors": "assign cache_rsp_ready = rsp_ready;" in lsu_cache_bridge and "assign rsp_error = cache_rsp_error;" in lsu_cache_bridge,
    "LSU cache bridge documents translation and ordering boundary": "upstream LSU must already" in (ROOT / "docs/PHASE34_LSU_L1D_INTEGRATION.md").read_text(encoding="utf-8"),
    "LSU cache bridge has directed testbench scaffold": "module tb_lsu_cache_bridge;" in lsu_cache_tb and "Metadata stability" in lsu_cache_tb,
})

lsu_subsystem = (RTL / "memory/mx64_lsu_cache_subsystem.sv").read_text(encoding="utf-8")
checks.update({
    "LSU cache subsystem instantiates the LSU pipeline and L1D bridge": "mx64_lsu_pipeline #(" in lsu_subsystem and "mx64_lsu_cache_bridge #(" in lsu_subsystem,
    "LSU cache subsystem backpressures loads while cache port is busy": "cache_req_ready && !store_commit_valid" in lsu_subsystem,
    "LSU cache subsystem gives committed stores cache-port priority": "if (store_commit_valid && !flush_all) begin" in lsu_subsystem and "cache_req_write = 1'b1;" in lsu_subsystem,
    "LSU cache subsystem sends accepted loads to L1D": "req_valid && !req_is_store && pipe_req_ready && !req_fault_valid" in lsu_subsystem,
    "LSU cache subsystem retires store-order entry only on accepted cache commit": ".store_retire_valid(store_commit_valid && store_commit_ready)" in lsu_subsystem,
    "LSU cache subsystem retains response transaction identity": "response_is_store_q <= cache_req_write;" in lsu_subsystem and "response_slot_q <= cache_req_write ? store_commit_lifecycle_slot : accepted_load_slot;" in lsu_subsystem,
    "LSU cache subsystem gates committed-store errors on sink acknowledgement": "assign store_error_valid = bridge_rsp_valid && response_is_store_q && bridge_rsp_error;" in lsu_subsystem and "(!store_error_valid || store_error_ready)" in lsu_subsystem and "store_error_lifecycle_slot = response_slot_q" in lsu_subsystem,
    "LSU cache subsystem exposes load forwarding metadata": "output logic [7:0] load_forward_mask" in lsu_subsystem and ".load_forward_data," in lsu_subsystem,
    "LSU cache subsystem exports physical reference events": "output logic [4*LSU_DEPTH-1:0] ref_release_valid" in lsu_subsystem and ".ref_acquire_valid, .ref_acquire_tag" in lsu_subsystem,
    "LSU cache subsystem asserts load and store cache handshakes": "Load accepted without an L1D read request" in lsu_subsystem and "Store commit accepted without an L1D write request" in lsu_subsystem,
})

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: RTL source contract: " + ", ".join(failed))
print(f"PASS: {len(module_defs)} unique RTL module declarations; {len(checks)} RTL source-contract checks")
print("NOTE: static text checks only; not SystemVerilog elaboration or verification")
