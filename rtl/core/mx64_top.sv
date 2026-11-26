// MX64-H Phase 37.5 integration top.
// This is an integrated execution-core boundary, not a complete SoC:
// - branch execution remains an explicit external functional-unit interface;
// - instruction and data memory are external ready/valid interfaces;
// - address translation is identity-mapped in this phase (no TLB/MMU RTL);
// - privilege/trap-vector state is supplied by the platform boundary.
module mx64_top #(
  parameter int VA_W = 48,
  parameter int PADDR_W = 40,
  parameter int ROB_DEPTH = 48,
  parameter int PHYS_REGS = 80,
  parameter int IQ_DEPTH = 16,
  parameter int LSU_DEPTH = 16,
  parameter int MEM_IQ_DEPTH = 16,
  parameter int LINE_BYTES = 64,
  parameter int BTB_ENTRIES = 64
) (
  input logic clk,
  input logic rst_n,
  input logic [VA_W-1:0] reset_pc,

  // Instruction-memory request/response.
  output logic imem_req_valid,
  input logic imem_req_ready,
  output logic [VA_W-1:0] imem_req_addr,
  input logic imem_resp_valid,
  input logic [31:0] imem_resp_data,
  input logic imem_resp_fault,
  input logic [VA_W-1:0] imem_resp_fault_addr,

  // Branch execution unit: consumes dispatched branch UOPs and returns
  // resolution plus optional link-register writeback.
  input logic [1:0] branch_unit_ready,
  output logic [1:0] branch_unit_valid,
  output mx64_pkg::issue_uop_t branch_unit_uop [0:1],
  input logic branch_resolve_valid,
  input logic [mx64_pkg::ROB_TAG_W-1:0] branch_resolve_tag,
  input logic branch_mispredict,
  input logic [VA_W-1:0] branch_resolve_pc,
  input logic branch_resolve_taken,
  input logic [63:0] branch_actual_next_pc,
  input logic [63:0] branch_link_result,
  input logic branch_link_wb_valid,
  input logic [$clog2(PHYS_REGS)-1:0] branch_link_wb_tag,
  output logic branch_resolve_ready,

  // External data-memory line interface.
  output logic mem_req_valid,
  input logic mem_req_ready,
  output logic mem_req_write,
  output logic [PADDR_W-1:0] mem_req_addr,
  output logic [LINE_BYTES*8-1:0] mem_req_wdata,
  output logic [LINE_BYTES-1:0] mem_req_wstrb,
  input logic mem_rsp_valid,
  output logic mem_rsp_ready,
  input logic [LINE_BYTES*8-1:0] mem_rsp_rdata,
  input logic mem_rsp_error,
  input logic invalidate_all,
  output logic committed_store_error_valid,
  output logic [mx64_pkg::ROB_TAG_W-1:0] committed_store_error_tag,
  output logic [PADDR_W-1:0] committed_store_error_paddr,

  // Platform trap/privilege boundary.
  input logic [1:0] current_privilege,
  input logic [63:0] trap_vector,
  output logic trap_valid,
  output logic [63:0] trap_pc,
  output logic [63:0] trap_cause,
  output logic [63:0] trap_value,

  // Architectural retirement event stream and observability.
  output logic [1:0] retire_valid,
  output logic [1:0][mx64_pkg::ROB_TAG_W-1:0] retire_tag,
  output logic [1:0][63:0] retire_pc,
  output logic [1:0][4:0] retire_rd,
  output logic [1:0][6:0] retire_kind,
  output logic [1:0][63:0] retire_value,
  output logic [1:0] retire_exception,
  output logic [1:0][3:0] retire_exception_code,
  output logic [1:0][63:0] retire_exception_value,
  output logic [1:0] retired_count,
  output logic rob_full,
  output logic rob_empty,
  output logic [$clog2(ROB_DEPTH+1)-1:0] rob_occupancy,
  output logic [$clog2(IQ_DEPTH+1)-1:0] issue_occupancy,
  output logic [$clog2(MEM_IQ_DEPTH+1)-1:0] memory_issue_occupancy,
  output logic [PHYS_REGS-1:0] physical_ref_bitmap,
  output logic [PHYS_REGS-1:0] physical_reclaim_bitmap,
  output logic [PHYS_REGS-1:0][7:0] physical_ref_count
);
  import mx64_pkg::*;
  localparam int PHYS_W = $clog2(PHYS_REGS);
  localparam int LSU_SLOT_W = $clog2(LSU_DEPTH);

  logic memory_issue_valid, memory_issue_ready;
  issue_uop_t memory_issue_uop;
  logic [1:0] retire_store_ready;
  logic memory_complete_valid, memory_complete_exception;
  logic [ROB_TAG_W-1:0] memory_complete_tag;
  logic [63:0] memory_complete_value, memory_complete_exception_value;
  logic [3:0] memory_complete_exception_code;
  logic memory_wb_valid;
  logic [PHYS_W-1:0] memory_wb_tag;
  logic [63:0] memory_wb_data;
  logic [31:0] recovery_seq_debug;
  logic [ROB_TAG_W-1:0] recovery_tag_debug;

  // Mirror LSU lifetime events into the core-wide physical-register tracker.
  logic ref_load_alloc_valid, ref_load_done_valid;
  logic [PHYS_W-1:0] ref_load_base_tag;
  logic [LSU_SLOT_W-1:0] ref_load_done_slot;
  logic ref_store_alloc_valid, ref_store_done_valid;
  logic [PHYS_W-1:0] ref_store_base_tag, ref_store_data_tag;
  logic [31:0] ref_store_alloc_seq;
  logic [LSU_SLOT_W-1:0] ref_store_done_slot;
  logic unused_load_alloc_ready, unused_store_alloc_ready;
  logic [LSU_SLOT_W-1:0] unused_load_alloc_slot, unused_store_alloc_slot;
  logic [$clog2(2*LSU_DEPTH+1)-1:0] unused_lsu_outstanding_count;

  logic [PADDR_W-1:0] translated_paddr;
  // Phase 37.5 has no MMU/TLB. Identity translation is explicit and guarded.
  assign translated_paddr = PADDR_W'(memory_issue_uop.src1_value + memory_issue_uop.immediate);

  mx64_frontend_dispatch #(
    .VA_W(VA_W), .PHYS_REGS(PHYS_REGS), .IQ_DEPTH(IQ_DEPTH),
    .ROB_DEPTH(ROB_DEPTH), .WIDTH(2), .BTB_ENTRIES(BTB_ENTRIES),
    .LSU_QUEUE_DEPTH(LSU_DEPTH), .MEM_IQ_DEPTH(MEM_IQ_DEPTH)
  ) u_frontend_dispatch (
    .clk, .rst_n, .reset_pc,
    .imem_req_valid, .imem_req_ready, .imem_req_addr,
    .imem_resp_valid, .imem_resp_data, .imem_resp_fault, .imem_resp_fault_addr,
    .branch_unit_ready, .branch_unit_valid, .branch_unit_uop,
    .branch_resolve_valid, .branch_resolve_tag, .branch_mispredict,
    .branch_resolve_pc, .branch_resolve_taken, .branch_actual_next_pc,
    .branch_link_result, .branch_link_wb_valid, .branch_link_wb_tag,
    .memory_wb_valid, .memory_wb_tag, .memory_wb_data,
    .memory_complete_valid, .memory_complete_rob_tag(memory_complete_tag),
    .memory_complete_value, .memory_complete_exception,
    .memory_complete_exception_code, .memory_complete_exception_value,
    .memory_issue_valid, .memory_issue_ready, .memory_issue_uop,
    .memory_issue_occupancy,
    .external_ref_acquire_valid('0), .external_ref_acquire_tag('0),
    .external_ref_release_valid('0), .external_ref_release_tag('0),
    .lsu_load_alloc_valid(ref_load_alloc_valid),
    .lsu_load_alloc_ready(unused_load_alloc_ready),
    .lsu_load_base_tag(ref_load_base_tag), .lsu_load_alloc_slot(unused_load_alloc_slot),
    .lsu_store_alloc_valid(ref_store_alloc_valid),
    .lsu_store_alloc_ready(unused_store_alloc_ready),
    .lsu_store_base_tag(ref_store_base_tag), .lsu_store_data_tag(ref_store_data_tag),
    .lsu_store_alloc_seq(ref_store_alloc_seq), .lsu_store_alloc_slot(unused_store_alloc_slot),
    .lsu_load_done_valid(ref_load_done_valid), .lsu_load_done_slot(ref_load_done_slot),
    .lsu_load_replay_valid(1'b0), .lsu_load_replay_slot('0),
    .lsu_store_done_valid(ref_store_done_valid), .lsu_store_done_slot(ref_store_done_slot),
    .lsu_store_replay_valid(1'b0), .lsu_store_replay_slot('0),
    .lsu_outstanding_count(unused_lsu_outstanding_count),
    .branch_resolve_ready,
    .current_privilege, .trap_vector, .trap_valid, .trap_pc, .trap_cause, .trap_value,
    .retire_gate_ready(retire_store_ready),
    .retire_valid, .retire_tag, .retire_pc, .retire_rd, .retire_kind,
    .retire_value, .retire_exception, .retire_exception_code,
    .retire_exception_value, .retired_count, .rob_full, .rob_empty,
    .rob_occupancy, .issue_occupancy, .physical_ref_bitmap,
    .physical_reclaim_bitmap, .physical_ref_count,
    .recovery_seq_debug, .recovery_tag_debug
  );

  mx64_lsu_rob_adapter #(
    .LSU_DEPTH(LSU_DEPTH), .PADDR_W(PADDR_W), .PHYS_W(PHYS_W),
    .SLOT_W(LSU_SLOT_W), .LINE_BYTES(LINE_BYTES)
  ) u_lsu_rob_adapter (
    .clk, .rst_n, .flush_all(trap_valid),
    .recover_valid(branch_resolve_valid && branch_resolve_ready && branch_mispredict),
    .recover_seq(recovery_seq_debug),
    .issue_valid(memory_issue_valid), .issue_ready(memory_issue_ready),
    .issue_uop(memory_issue_uop), .issue_paddr(translated_paddr),
    .retire_valid, .retire_tag, .retire_kind, .retire_store_ready,
    .memory_complete_valid, .memory_complete_tag, .memory_complete_value,
    .memory_complete_exception, .memory_complete_exception_code,
    .memory_complete_exception_value,
    .memory_wb_valid, .memory_wb_tag, .memory_wb_data,
    .committed_store_error_valid, .committed_store_error_tag, .committed_store_error_paddr,
    .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
    .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid, .mem_rsp_ready,
    .mem_rsp_rdata, .mem_rsp_error, .invalidate_all,
    .live_loads(), .live_stores(),
    .ref_load_alloc_valid, .ref_load_base_tag, .ref_load_done_valid, .ref_load_done_slot,
    .ref_store_alloc_valid, .ref_store_base_tag, .ref_store_data_tag,
    .ref_store_alloc_seq, .ref_store_done_valid, .ref_store_done_slot
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && memory_issue_valid && memory_issue_ready) begin
      assert ((memory_issue_uop.src1_value + memory_issue_uop.immediate) < (64'h1 << PADDR_W))
        else $error("Phase 37.5 identity translation cannot represent address in PADDR_W");
    end
    if (rst_n && branch_resolve_valid && branch_mispredict)
      assert (branch_resolve_ready)
        else $error("Branch recovery must only be consumed when ROB accepts resolution");
  end
`endif
endmodule
