// MX64-H Phase 20: fetch/decode to rename/dispatch/ROB/IQ control integration.
// Operand values/readiness and branch execution are explicit external ports;
// this wrapper does not claim to be a complete CPU top.
module mx64_frontend_dispatch #(
  parameter int VA_W = 48,
  parameter int PHYS_REGS = 80,
  parameter int IQ_DEPTH = 16,
  parameter int ROB_DEPTH = 48,
  parameter int WIDTH = 2,
  parameter int BTB_ENTRIES = 64,
  parameter int EXTERNAL_REF_WIDTH = 8,
  parameter int LSU_QUEUE_DEPTH = 16,
  parameter int MEM_IQ_DEPTH = 16
) (
  input logic clk,
  input logic rst_n,
  input logic [VA_W-1:0] reset_pc,

  // Instruction memory request/response boundary.
  output logic imem_req_valid,
  input logic imem_req_ready,
  output logic [VA_W-1:0] imem_req_addr,
  input logic imem_resp_valid,
  input logic [31:0] imem_resp_data,
  input logic imem_resp_fault,
  input logic [VA_W-1:0] imem_resp_fault_addr,

  // Branch execution unit boundary.
  input logic [WIDTH-1:0] branch_unit_ready,
  output logic [WIDTH-1:0] branch_unit_valid,
  output mx64_pkg::issue_uop_t branch_unit_uop [0:WIDTH-1],
  input logic branch_resolve_valid,
  input logic [mx64_pkg::ROB_TAG_W-1:0] branch_resolve_tag,
  input logic branch_mispredict,
  input logic [VA_W-1:0] branch_resolve_pc,
  input logic branch_resolve_taken,
  input logic [63:0] branch_actual_next_pc,
  input logic [63:0] branch_link_result,
  input logic branch_link_wb_valid,
  input logic [$clog2(PHYS_REGS)-1:0] branch_link_wb_tag,
  // External memory-result writeback (e.g. a completed load) updates the PRF
  // and wakes dependent memory operations.
  input logic memory_wb_valid,
  input logic [$clog2(PHYS_REGS)-1:0] memory_wb_tag,
  input logic [63:0] memory_wb_data,
  // LSU completion channel carries the ROB identity separately from the
  // physical destination used by the PRF writeback port.
  input logic memory_complete_valid,
  input logic [mx64_pkg::ROB_TAG_W-1:0] memory_complete_rob_tag,
  input logic [63:0] memory_complete_value,
  input logic memory_complete_exception,
  input logic [3:0] memory_complete_exception_code,
  input logic [63:0] memory_complete_exception_value,
  // Dedicated memory issue output. The consumer must accept only on valid/ready.
  output logic memory_issue_valid,
  input logic memory_issue_ready,
  output mx64_pkg::issue_uop_t memory_issue_uop,
  output logic [$clog2(MEM_IQ_DEPTH+1)-1:0] memory_issue_occupancy,
  // External tag-retention events from branch/LSU/FP/SIMD consumers.
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_acquire_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] external_ref_acquire_tag,
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_release_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] external_ref_release_tag,
  // LSU queue lifecycle boundary: accepted queue entries retain their tags.
  input logic lsu_load_alloc_valid,
  output logic lsu_load_alloc_ready,
  input logic [$clog2(PHYS_REGS)-1:0] lsu_load_base_tag,
  output logic [$clog2(LSU_QUEUE_DEPTH)-1:0] lsu_load_alloc_slot,
  input logic lsu_store_alloc_valid,
  output logic lsu_store_alloc_ready,
  input logic [$clog2(PHYS_REGS)-1:0] lsu_store_base_tag,
  input logic [$clog2(PHYS_REGS)-1:0] lsu_store_data_tag,
  input logic [31:0] lsu_store_alloc_seq,
  output logic [$clog2(LSU_QUEUE_DEPTH)-1:0] lsu_store_alloc_slot,
  input logic lsu_load_done_valid,
  input logic [$clog2(LSU_QUEUE_DEPTH)-1:0] lsu_load_done_slot,
  input logic lsu_load_replay_valid,
  input logic [$clog2(LSU_QUEUE_DEPTH)-1:0] lsu_load_replay_slot,
  input logic lsu_store_done_valid,
  input logic [$clog2(LSU_QUEUE_DEPTH)-1:0] lsu_store_done_slot,
  input logic lsu_store_replay_valid,
  input logic [$clog2(LSU_QUEUE_DEPTH)-1:0] lsu_store_replay_slot,
  output logic [$clog2(2*LSU_QUEUE_DEPTH+1)-1:0] lsu_outstanding_count,
  output logic branch_resolve_ready,

  // Privileged trap-vector boundary.
  input logic [1:0] current_privilege,
  input logic [63:0] trap_vector,
  output logic trap_valid,
  output logic [63:0] trap_pc,
  output logic [63:0] trap_cause,
  output logic [63:0] trap_value,

  // Retirement gate supplied by the memory/store-commit integration.
  input logic [WIDTH-1:0] retire_gate_ready,

  // Retirement and status.
  output logic [WIDTH-1:0] retire_valid,
  output logic [WIDTH-1:0][mx64_pkg::ROB_TAG_W-1:0] retire_tag,
  output logic [WIDTH-1:0][63:0] retire_pc,
  output logic [WIDTH-1:0][4:0] retire_rd,
  output logic [WIDTH-1:0][6:0] retire_kind,
  output logic [WIDTH-1:0][63:0] retire_value,
  output logic [WIDTH-1:0] retire_exception,
  output logic [WIDTH-1:0][3:0] retire_exception_code,
  output logic [WIDTH-1:0][63:0] retire_exception_value,
  output logic [1:0] retired_count,
  output logic rob_full,
  output logic rob_empty,
  output logic [$clog2(ROB_DEPTH+1)-1:0] rob_occupancy,
  output logic [$clog2(IQ_DEPTH+1)-1:0] issue_occupancy,
  output logic [PHYS_REGS-1:0] physical_ref_bitmap,
  output logic [PHYS_REGS-1:0] physical_reclaim_bitmap,
  output logic [PHYS_REGS-1:0][7:0] physical_ref_count,
  output logic [31:0] recovery_seq_debug,
  output logic [mx64_pkg::ROB_TAG_W-1:0] recovery_tag_debug
);
  logic decoded_valid, decoded_ready;
  logic [VA_W-1:0] frontend_redirect_pc;
  logic frontend_redirect_valid;
  mx64_pkg::decoded_uop_t decoded_uop;
  localparam int PHYS_W = $clog2(PHYS_REGS);
  logic [WIDTH-1:0][PHYS_W-1:0] source1_phys_tag, source2_phys_tag;
  logic [WIDTH-1:0] int_wb_valid;
  logic [WIDTH-1:0][PHYS_W-1:0] int_wb_tag;
  logic [WIDTH-1:0][63:0] int_wb_data;
  logic [3:0][PHYS_W-1:0] prf_raddr;
  logic [3:0][63:0] prf_rdata;
  logic [3:0] prf_rvalid;
  logic [3:0] prf_wen;
  logic [3:0][PHYS_W-1:0] prf_waddr;
  logic [3:0][63:0] prf_wdata;
  logic [WIDTH-1:0] operand1_ready, operand2_ready;
  logic [WIDTH-1:0][63:0] operand1_value, operand2_value;
  logic [WIDTH-1:0] decoded_valid_lanes, decoded_ready_lanes;
  mx64_pkg::decoded_uop_t decoded_uop_lanes [0:WIDTH-1];
  logic [63:0] trap_redirect_pc;
  logic trap_redirect_valid;
  localparam int TRACKER_REF_WIDTH = EXTERNAL_REF_WIDTH + 2*ROB_DEPTH + 4*LSU_QUEUE_DEPTH + 2*MEM_IQ_DEPTH;
  logic [TRACKER_REF_WIDTH-1:0] tracker_acquire_valid, tracker_release_valid;
  logic [TRACKER_REF_WIDTH-1:0][PHYS_W-1:0] tracker_acquire_tag, tracker_release_tag;
  logic [2*WIDTH-1:0] branch_ref_acquire_valid;
  logic [2*WIDTH-1:0][PHYS_W-1:0] branch_ref_acquire_tag;
  logic [2*ROB_DEPTH-1:0] branch_ref_release_valid;
  logic [2*ROB_DEPTH-1:0][PHYS_W-1:0] branch_ref_release_tag;
  logic [$clog2(ROB_DEPTH+1)-1:0] branch_refs_retained;
  logic [3:0] lsu_ref_acquire_valid;
  logic [3:0][PHYS_W-1:0] lsu_ref_acquire_tag;
  logic [4*LSU_QUEUE_DEPTH-1:0] lsu_ref_release_valid;
  logic [4*LSU_QUEUE_DEPTH-1:0][PHYS_W-1:0] lsu_ref_release_tag;
  logic [WIDTH-1:0] memory_dispatch_valid, memory_dispatch_ready;
  mx64_pkg::issue_uop_t memory_dispatch_uop [0:WIDTH-1];
  logic [2*WIDTH-1:0] memory_ref_acquire_valid;
  logic [2*WIDTH-1:0][PHYS_W-1:0] memory_ref_acquire_tag;
  logic [2*MEM_IQ_DEPTH-1:0] memory_ref_release_valid;
  logic [2*MEM_IQ_DEPTH-1:0][PHYS_W-1:0] memory_ref_release_tag;
  logic [WIDTH+1:0] memory_wakeup_valid;
  logic [WIDTH+1:0][PHYS_W-1:0] memory_wakeup_tag;
  logic [WIDTH+1:0][63:0] memory_wakeup_data;
  logic lsu_recover_valid;

  // Two-wide integer backend: two source reads and up to two writebacks.
  always_comb begin
    for (int lane = 0; lane < WIDTH; lane++) begin
      prf_raddr[2*lane] = source1_phys_tag[lane];
      prf_raddr[2*lane+1] = source2_phys_tag[lane];
      operand1_ready[lane] = prf_rvalid[2*lane];
      operand2_ready[lane] = prf_rvalid[2*lane+1];
      operand1_value[lane] = prf_rdata[2*lane];
      operand2_value[lane] = prf_rdata[2*lane+1];
    end
    prf_wen = '0;
    prf_waddr = '0;
    prf_wdata = '0;
    prf_wen[1:0] = int_wb_valid;
    prf_waddr[1:0] = int_wb_tag;
    prf_wdata[1:0] = int_wb_data;
    prf_wen[2] = branch_link_wb_valid;
    prf_waddr[2] = branch_link_wb_tag;
    prf_wdata[2] = branch_link_result;
    prf_wen[3] = memory_wb_valid;
    prf_waddr[3] = memory_wb_tag;
    prf_wdata[3] = memory_wb_data;
  end

  physical_regfile #(
    .DEPTH(PHYS_REGS), .ARCH_REGS(32), .DATA_W(64),
    .TAG_W(PHYS_W), .READ_PORTS(4), .WRITE_PORTS(4)
  ) u_integer_prf (
    .clk, .rst_n, .raddr(prf_raddr), .rdata(prf_rdata),
    .rvalid(prf_rvalid), .wen(prf_wen), .waddr(prf_waddr),
    .wdata(prf_wdata)
  );

  mx64_frontend #(.VA_W(VA_W), .BTB_ENTRIES(BTB_ENTRIES)) u_frontend (
    .clk, .rst_n, .reset_pc,
    .mem_req_valid(imem_req_valid), .mem_req_ready(imem_req_ready),
    .mem_req_addr(imem_req_addr),
    .mem_resp_valid(imem_resp_valid), .mem_resp_data(imem_resp_data),
    .mem_resp_fault(imem_resp_fault), .mem_resp_fault_addr(imem_resp_fault_addr),
    .decoded_valid, .decoded_ready, .decoded_uop,
    .redirect_valid(frontend_redirect_valid), .redirect_pc(frontend_redirect_pc),
    .branch_resolve_valid,
    .branch_resolve_pc(branch_resolve_pc),
    .branch_resolve_taken(branch_resolve_taken),
    .branch_resolve_target(branch_actual_next_pc)
  );

  // The current fetch/decode block is single-wide. Lane 1 is intentionally
  // idle until a multi-instruction fetch buffer and dual decoder are implemented.
  always_comb begin
    decoded_valid_lanes = '0;
    decoded_ready = decoded_ready_lanes[0];
    decoded_uop_lanes[0] = decoded_uop;
    decoded_uop_lanes[1] = '0;
    decoded_valid_lanes[0] = decoded_valid;
    frontend_redirect_valid = trap_redirect_valid | (branch_resolve_valid && branch_resolve_ready && branch_mispredict);
    frontend_redirect_pc = trap_redirect_valid ? trap_redirect_pc : branch_actual_next_pc;
  end


  // Branch source tags remain live from accepted branch dispatch through
  // resolution. A mispredict releases the resolving branch and all younger
  // retained branch operands; a precise trap flush releases every entry.
  branch_reference_lifecycle #(
    .WIDTH(WIDTH), .ROB_DEPTH(ROB_DEPTH), .PHYS_W(PHYS_W)
  ) u_branch_reference_lifecycle (
    .clk, .rst_n, .flush_all(trap_valid),
    .dispatch_valid(branch_unit_valid), .dispatch_ready(branch_unit_ready),
    .dispatch_uop(branch_unit_uop),
    .resolve_valid(branch_resolve_valid && branch_resolve_ready),
    .resolve_tag(branch_resolve_tag), .mispredict(branch_mispredict),
    .acquire_valid(branch_ref_acquire_valid), .acquire_tag(branch_ref_acquire_tag),
    .release_valid(branch_ref_release_valid), .release_tag(branch_ref_release_tag),
    .retained_count(branch_refs_retained)
  );

  assign lsu_recover_valid = branch_resolve_valid && branch_resolve_ready && branch_mispredict;

  // Load/store queue entries retain their source tags until completion,
  // replay discard, or precise trap flush.
  lsu_reference_lifecycle #(.DEPTH(LSU_QUEUE_DEPTH), .PHYS_W(PHYS_W)) u_lsu_reference_lifecycle (
    .clk, .rst_n, .flush_all(trap_valid), .recover_valid(lsu_recover_valid), .recover_seq(recovery_seq_debug),
    .load_alloc_valid(lsu_load_alloc_valid), .load_alloc_ready(lsu_load_alloc_ready),
    .load_base_tag(lsu_load_base_tag), .load_alloc_slot(lsu_load_alloc_slot),
    .store_alloc_valid(lsu_store_alloc_valid), .store_alloc_ready(lsu_store_alloc_ready),
    .store_base_tag(lsu_store_base_tag), .store_data_tag(lsu_store_data_tag), .store_alloc_seq(lsu_store_alloc_seq),
    .store_alloc_slot(lsu_store_alloc_slot),
    .load_done_valid(lsu_load_done_valid), .load_done_slot(lsu_load_done_slot),
    .load_replay_valid(lsu_load_replay_valid), .load_replay_slot(lsu_load_replay_slot),
    .store_done_valid(lsu_store_done_valid), .store_done_slot(lsu_store_done_slot),
    .store_replay_valid(lsu_store_replay_valid), .store_replay_slot(lsu_store_replay_slot),
    .acquire_valid(lsu_ref_acquire_valid), .acquire_tag(lsu_ref_acquire_tag),
    .release_valid(lsu_ref_release_valid), .release_tag(lsu_ref_release_tag),
    .outstanding_count(lsu_outstanding_count)
  );

  always_comb begin
    memory_wakeup_valid = '0;
    memory_wakeup_tag = '0;
    memory_wakeup_data = '0;
    memory_wakeup_valid[0 +: WIDTH] = int_wb_valid;
    memory_wakeup_tag[0 +: WIDTH] = int_wb_tag;
    memory_wakeup_data[0 +: WIDTH] = int_wb_data;
    memory_wakeup_valid[WIDTH] = branch_link_wb_valid;
    memory_wakeup_tag[WIDTH] = branch_link_wb_tag;
    memory_wakeup_data[WIDTH] = branch_link_result;
    memory_wakeup_valid[WIDTH+1] = memory_wb_valid;
    memory_wakeup_tag[WIDTH+1] = memory_wb_tag;
    memory_wakeup_data[WIDTH+1] = memory_wb_data;
  end

  mx64_memory_issue_queue #(
    .DEPTH(MEM_IQ_DEPTH), .WIDTH(WIDTH), .WAKEUP_WIDTH(WIDTH+2),
    .XLEN(64), .PHYS_W(PHYS_W), .ROB_TAG_W(mx64_pkg::ROB_TAG_W)
  ) u_memory_issue_queue (
    .clk, .rst_n, .flush(trap_valid),
    .recover_valid(branch_resolve_valid && branch_resolve_ready && branch_mispredict),
    .recover_seq(recovery_seq_debug),
    .enq_valid(memory_dispatch_valid), .enq_ready(memory_dispatch_ready),
    .enq_uop(memory_dispatch_uop),
    .wakeup_valid(memory_wakeup_valid), .wakeup_tag(memory_wakeup_tag),
    .wakeup_data(memory_wakeup_data),
    .issue_valid(memory_issue_valid), .issue_ready(memory_issue_ready),
    .issue_uop(memory_issue_uop),
    .ref_acquire_valid(memory_ref_acquire_valid), .ref_acquire_tag(memory_ref_acquire_tag),
    .ref_release_valid(memory_ref_release_valid), .ref_release_tag(memory_ref_release_tag),
    .occupancy(memory_issue_occupancy)
  );

  always_comb begin
    tracker_acquire_valid = '0;
    tracker_acquire_tag = '0;
    tracker_release_valid = '0;
    tracker_release_tag = '0;
    tracker_acquire_valid[0 +: EXTERNAL_REF_WIDTH] = external_ref_acquire_valid;
    tracker_acquire_tag[0 +: EXTERNAL_REF_WIDTH] = external_ref_acquire_tag;
    tracker_acquire_valid[EXTERNAL_REF_WIDTH +: 2*WIDTH] = branch_ref_acquire_valid;
    tracker_acquire_tag[EXTERNAL_REF_WIDTH +: 2*WIDTH] = branch_ref_acquire_tag;
    tracker_acquire_valid[EXTERNAL_REF_WIDTH + 2*WIDTH +: 4] = lsu_ref_acquire_valid;
    tracker_acquire_tag[EXTERNAL_REF_WIDTH + 2*WIDTH +: 4] = lsu_ref_acquire_tag;
    tracker_acquire_valid[EXTERNAL_REF_WIDTH + 2*WIDTH + 4 +: 2*WIDTH] = memory_ref_acquire_valid;
    tracker_acquire_tag[EXTERNAL_REF_WIDTH + 2*WIDTH + 4 +: 2*WIDTH] = memory_ref_acquire_tag;
    tracker_release_valid[0 +: EXTERNAL_REF_WIDTH] = external_ref_release_valid;
    tracker_release_tag[0 +: EXTERNAL_REF_WIDTH] = external_ref_release_tag;
    tracker_release_valid[EXTERNAL_REF_WIDTH +: 2*ROB_DEPTH] = branch_ref_release_valid;
    tracker_release_tag[EXTERNAL_REF_WIDTH +: 2*ROB_DEPTH] = branch_ref_release_tag;
    tracker_release_valid[EXTERNAL_REF_WIDTH + 2*ROB_DEPTH +: 4*LSU_QUEUE_DEPTH] = lsu_ref_release_valid;
    tracker_release_tag[EXTERNAL_REF_WIDTH + 2*ROB_DEPTH +: 4*LSU_QUEUE_DEPTH] = lsu_ref_release_tag;
    tracker_release_valid[EXTERNAL_REF_WIDTH + 2*ROB_DEPTH + 4*LSU_QUEUE_DEPTH +: 2*MEM_IQ_DEPTH] = memory_ref_release_valid;
    tracker_release_tag[EXTERNAL_REF_WIDTH + 2*ROB_DEPTH + 4*LSU_QUEUE_DEPTH +: 2*MEM_IQ_DEPTH] = memory_ref_release_tag;
  end

  mx64_control_subsystem #(
    .PHYS_REGS(PHYS_REGS), .IQ_DEPTH(IQ_DEPTH),
    .ROB_DEPTH(ROB_DEPTH), .WIDTH(WIDTH),
    .EXTERNAL_REF_WIDTH(TRACKER_REF_WIDTH)
  ) u_control (
    .clk, .rst_n,
    .decoded_valid(decoded_valid_lanes), .decoded_ready(decoded_ready_lanes),
    .decoded_uop(decoded_uop_lanes),
    .src1_ready(operand1_ready), .src2_ready(operand2_ready),
    .src1_value(operand1_value), .src2_value(operand2_value),
    .branch_wb_valid(branch_link_wb_valid), .branch_wb_tag(branch_link_wb_tag),
    .branch_wb_data(branch_link_result),
    .external_ref_acquire_valid(tracker_acquire_valid), .external_ref_acquire_tag(tracker_acquire_tag),
    .external_ref_release_valid(tracker_release_valid), .external_ref_release_tag(tracker_release_tag),
    .source1_phys_tag, .source2_phys_tag, .int_wb_valid, .int_wb_tag, .int_wb_data,
    .branch_dispatch_ready(branch_unit_ready),
    .branch_dispatch_valid(branch_unit_valid),
    .branch_dispatch_uop(branch_unit_uop),
    .memory_dispatch_ready, .memory_dispatch_valid, .memory_dispatch_uop,
    .memory_complete_valid, .memory_complete_tag(memory_complete_rob_tag),
    .memory_complete_value, .memory_complete_exception,
    .memory_complete_exception_code, .memory_complete_exception_value,
    .retire_gate_ready,
    .branch_resolve_valid, .branch_resolve_tag, .branch_mispredict,
    .branch_actual_target(branch_actual_next_pc),
    .branch_result_value(branch_link_result), .branch_resolve_ready,
    .current_privilege, .trap_vector,
    .trap_valid, .trap_pc, .trap_cause, .trap_value,
    .trap_redirect_valid(trap_redirect_valid), .trap_redirect_pc,
    .retire_valid, .retire_tag, .retire_pc, .retire_rd, .retire_kind,
    .retire_value, .retire_exception, .retire_exception_code,
    .retire_exception_value, .retired_count,
    .rob_full, .rob_empty, .rob_occupancy, .issue_occupancy,
    .physical_ref_bitmap, .physical_reclaim_bitmap, .physical_ref_count,
    .recovery_seq_debug, .recovery_tag_debug
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && branch_link_wb_valid) begin
      assert (branch_resolve_valid && branch_resolve_ready)
        else $error("branch link writeback must accompany accepted branch resolution");
    end
    if (rst_n && memory_wb_valid) begin
      assert (memory_complete_valid && !memory_complete_exception)
        else $error("memory PRF writeback must accompany successful ROB completion");
      assert (memory_wb_data == memory_complete_value)
        else $error("memory PRF and ROB completion values disagree");
    end
    if (rst_n && memory_complete_valid && memory_complete_exception)
      assert (!memory_wb_valid)
        else $error("faulting memory completion must not write PRF");
  end
`endif
endmodule
