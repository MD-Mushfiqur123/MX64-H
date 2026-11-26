// MX64 M2.3+: atomic two-wide rename/ROB/IQ dispatch plus branch checkpoints.
// Branch resolution is supplied by the branch execution unit. A misprediction
// restores the exact per-lane rename/free-list snapshot and selectively removes
// younger ROB and issue-queue entries; older work remains live.
module mx64_dispatch_controller #(
  parameter int WIDTH = 2,
  parameter int ARCH_REGS = 32,
  parameter int PHYS_REGS = 80,
  parameter int PHYS_W = $clog2(PHYS_REGS),
  parameter int IQ_DEPTH = 16,
  parameter int ROB_DEPTH = 48,
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W,
  parameter int NUM_BRANCH_CHECKPOINTS = 16,
  parameter int EXTERNAL_REF_WIDTH = 8
) (
  input logic clk,
  input logic rst_n,
  input logic flush,

  input logic [ARCH_REGS-1:0][PHYS_W-1:0] restore_rat,
  input logic [PHYS_REGS-1:0] restore_free_bitmap,
  input logic [WIDTH-1:0] decoded_valid,
  output logic [WIDTH-1:0] decoded_ready,
  input mx64_pkg::decoded_uop_t decoded_uop [0:WIDTH-1],

  input logic [WIDTH-1:0] src1_ready,
  input logic [WIDTH-1:0] src2_ready,
  input logic [WIDTH-1:0][63:0] src1_value,
  input logic [WIDTH-1:0][63:0] src2_value,
  output logic [WIDTH-1:0][PHYS_W-1:0] source1_phys_tag,
  output logic [WIDTH-1:0][PHYS_W-1:0] source2_phys_tag,
  output logic [WIDTH-1:0] int_wb_valid,
  output logic [WIDTH-1:0][PHYS_W-1:0] int_wb_tag,
  output logic [WIDTH-1:0][63:0] int_wb_data,
  input logic branch_wb_valid,
  input logic [PHYS_W-1:0] branch_wb_tag,
  input logic [63:0] branch_wb_data,
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_acquire_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][PHYS_W-1:0] external_ref_acquire_tag,
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_release_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][PHYS_W-1:0] external_ref_release_tag,

  // Dedicated branch unit accepts control-transfer uops outside the integer IQ.
  input logic [WIDTH-1:0] branch_dispatch_ready,
  output logic [WIDTH-1:0] branch_dispatch_valid,
  output mx64_pkg::issue_uop_t branch_dispatch_uop [0:WIDTH-1],

  // Load/store uops are routed to a dedicated memory issue queue, never to
  // the integer-ALU issue queue.
  input logic [WIDTH-1:0] memory_dispatch_ready,
  output logic [WIDTH-1:0] memory_dispatch_valid,
  output mx64_pkg::issue_uop_t memory_dispatch_uop [0:WIDTH-1],
  // LSU completion returns to the ROB even when no PRF destination is written.
  input logic memory_complete_valid,
  input logic [ROB_TAG_W-1:0] memory_complete_tag,
  input logic [63:0] memory_complete_value,
  input logic memory_complete_exception,
  input logic [3:0] memory_complete_exception_code,
  input logic [63:0] memory_complete_exception_value,

  // Branch execution reports its full ROB tag and actual next PC.
  input logic branch_resolve_valid,
  input logic [ROB_TAG_W-1:0] branch_resolve_tag,
  input logic branch_mispredict,
  input logic [63:0] branch_actual_target,
  // Destination result is distinct from next PC (e.g. JAL writes PC+4).
  input logic [63:0] branch_result_value,
  output logic branch_resolve_ready,
  output logic recovery_valid,
  output logic [ROB_TAG_W-1:0] recovery_branch_tag,
  output logic [31:0] recovery_seq,
  output logic [63:0] recovery_pc,
  output logic branch_resolve_tag_found,
  output logic recovery_rob_tag_found,

  output logic [WIDTH-1:0] retire_valid,
  input logic [WIDTH-1:0] retire_ready,
  output logic [WIDTH-1:0][ROB_TAG_W-1:0] retire_tag,
  output logic [WIDTH-1:0][63:0] retire_pc,
  output logic [WIDTH-1:0][4:0] retire_rd,
  output logic [WIDTH-1:0][6:0] retire_kind,
  output logic [WIDTH-1:0][63:0] retire_value,
  output logic [WIDTH-1:0] retire_exception,
  output logic [WIDTH-1:0][3:0] retire_exception_code,
  output logic [WIDTH-1:0][63:0] retire_exception_value,

  output logic rob_full,
  output logic rob_empty,
  output logic [$clog2(ROB_DEPTH+1)-1:0] rob_occupancy,
  output logic [$clog2(IQ_DEPTH+1)-1:0] issue_occupancy,
  output logic [ARCH_REGS-1:0][PHYS_W-1:0] rat_debug,
  output logic [ARCH_REGS-1:0][PHYS_W-1:0] committed_rat_debug,
  output logic [PHYS_REGS-1:0] free_debug,
  output logic [PHYS_REGS-1:0] committed_free_bitmap_debug,
  output logic [PHYS_REGS-1:0] physical_ref_bitmap,
  output logic [PHYS_REGS-1:0] physical_reclaim_bitmap,
  output logic [PHYS_REGS-1:0][7:0] physical_ref_count
);
  import mx64_pkg::*;

`ifndef SYNTHESIS
  initial if (ROB_TAG_W != mx64_pkg::ROB_TAG_W || ROB_DEPTH != 48)
    $error("ROB tag type is currently fixed to the 48-entry profile");
`endif

  logic [WIDTH-1:0] rename_in_ready;
  logic [WIDTH-1:0][4:0] rename_rs1, rename_rs2, rename_rd;
  logic [WIDTH-1:0] rename_writes_rd;
  logic [WIDTH-1:0] rename_out_valid;
  logic [WIDTH-1:0] rename_out_ready;
  logic [WIDTH-1:0][PHYS_W-1:0] prs1, prs2, prd, old_prd;
  logic [WIDTH-1:0][ARCH_REGS-1:0][PHYS_W-1:0] rename_rat_snapshot;
  logic [WIDTH-1:0][PHYS_REGS-1:0] rename_free_snapshot;

  logic [WIDTH-1:0] backend_dispatch_valid;
  logic [WIDTH-1:0] backend_dispatch_ready;
  issue_uop_t backend_uop [0:WIDTH-1];

  logic [WIDTH-1:0] rob_alloc_valid;
  logic [WIDTH-1:0] rob_alloc_ready;
  logic [WIDTH-1:0][ROB_TAG_W-1:0] rob_alloc_tag;
  logic [WIDTH-1:0][63:0] rob_alloc_pc;
  logic [WIDTH-1:0][4:0] rob_alloc_rd;
  logic [WIDTH-1:0][6:0] rob_alloc_kind;
  logic [WIDTH-1:0][PHYS_W-1:0] rob_alloc_prd, rob_alloc_old_prd;
  logic [WIDTH-1:0][PHYS_W-1:0] retire_prd, retire_old_prd;
  logic [WIDTH-1:0] rob_alloc_exception;
  logic [WIDTH-1:0][3:0] rob_alloc_exception_code;
  logic [WIDTH-1:0][63:0] rob_alloc_exception_value;
  logic [WIDTH-1:0] commit_fire, commit_free_valid;
  logic [WIDTH-1:0][PHYS_W-1:0] commit_free_tag;
  logic [PHYS_REGS-1:0] tracker_reclaim_bitmap;
  assign physical_reclaim_bitmap = tracker_reclaim_bitmap;

  logic [WIDTH-1:0] dispatch_permit, dispatch_accept, branch_accept;
  logic [WIDTH-1:0] control_transfer, memory_operation;
  logic [WIDTH-1:0] dispatch_target_ready, dispatch_exception;
  logic [WIDTH-1:0][31:0] dispatch_seq_lane;
  logic [31:0] dispatch_seq_q;

  logic checkpoint_capture_ready;
  logic [$clog2(NUM_BRANCH_CHECKPOINTS)-1:0] checkpoint_capture_id;
  logic checkpoint_capture_valid;
  logic [ROB_TAG_W-1:0] checkpoint_capture_tag;
  logic [31:0] checkpoint_capture_seq;
  logic [ARCH_REGS-1:0][PHYS_W-1:0] checkpoint_capture_rat;
  logic [PHYS_REGS-1:0] checkpoint_capture_free;
  logic [ARCH_REGS-1:0][PHYS_W-1:0] checkpoint_restore_rat;
  logic [PHYS_REGS-1:0] checkpoint_restore_free;
  logic [ROB_TAG_W-1:0] checkpoint_recover_tag;
  logic [31:0] checkpoint_recover_seq;
  logic [$clog2(NUM_BRANCH_CHECKPOINTS+1)-1:0] checkpoint_count;
  logic branch_checkpoint_found;
  logic [ARCH_REGS-1:0][PHYS_W-1:0] rename_restore_rat;
  logic [PHYS_REGS-1:0] rename_restore_free;

  always_comb begin
    commit_fire = '0;
    for (int lane = 0; lane < WIDTH; lane++) begin
      commit_fire[lane] = retire_valid[lane] && retire_ready[lane] &&
                          !retire_exception[lane] && retire_kind[lane][2] &&
                          (retire_rd[lane] != '0);
    end
  end
  assign commit_free_valid = commit_fire;
  assign commit_free_tag = retire_old_prd;

  // A single checkpoint is captured per cycle. If both lanes contain branches,
  // lane 0 may dispatch and lane 1 is held for the next cycle. The snapshot is
  // taken after the branch's own lane, not after younger work in the same beat.
  always_comb begin
    control_transfer = '0;
    dispatch_exception = '0;
    dispatch_target_ready = backend_dispatch_ready;
    for (int lane = 0; lane < WIDTH; lane++) begin
      dispatch_exception[lane] = decoded_valid[lane] &&
                                  (decoded_uop[lane].exception != EXC_NONE);
      control_transfer[lane] = decoded_valid[lane] && !dispatch_exception[lane] &&
                               (decoded_uop[lane].is_branch || decoded_uop[lane].is_jump);
      memory_operation[lane] = decoded_valid[lane] && !dispatch_exception[lane] &&
                               (decoded_uop[lane].is_load || decoded_uop[lane].is_store);
      if (dispatch_exception[lane])
        dispatch_target_ready[lane] = 1'b1; // exception is recorded directly in the ROB
      else if (control_transfer[lane])
        dispatch_target_ready[lane] = branch_dispatch_ready[lane];
      else if (memory_operation[lane])
        dispatch_target_ready[lane] = memory_dispatch_ready[lane];
    end

    dispatch_permit = '0;
    dispatch_permit[0] = !flush && !recovery_valid &&
                         (!control_transfer[0] || checkpoint_capture_ready);
    if (WIDTH > 1) begin
      dispatch_permit[1] = !flush && !recovery_valid &&
        (!control_transfer[1] ||
         ((!decoded_valid[0] || !control_transfer[0]) && checkpoint_capture_ready));
    end

    rob_alloc_valid = rename_out_valid & dispatch_target_ready & dispatch_permit;
    backend_dispatch_valid = rename_out_valid & rob_alloc_ready & dispatch_permit &
                             ~control_transfer & ~memory_operation & ~dispatch_exception;
    branch_dispatch_valid = rename_out_valid & rob_alloc_ready & dispatch_permit &
                            control_transfer & ~dispatch_exception;
    memory_dispatch_valid = rename_out_valid & rob_alloc_ready & dispatch_permit &
                            memory_operation & ~dispatch_exception;
    rename_out_ready = dispatch_target_ready & rob_alloc_ready & dispatch_permit;
    decoded_ready = rename_in_ready;
    dispatch_accept = decoded_valid & decoded_ready;
    branch_accept = dispatch_accept & control_transfer & ~dispatch_exception;

    for (int lane = 0; lane < WIDTH; lane++) begin
      rob_alloc_exception[lane] = dispatch_exception[lane];
      rob_alloc_exception_code[lane] = decoded_uop[lane].exception;
      rob_alloc_exception_value[lane] = decoded_uop[lane].exception_value;
    end

    dispatch_seq_lane[0] = dispatch_seq_q;
    dispatch_seq_lane[1] = dispatch_seq_q + (dispatch_accept[0] ? 32'd1 : 32'd0);

    checkpoint_capture_valid = 1'b0;
    checkpoint_capture_tag = '0;
    checkpoint_capture_seq = '0;
    checkpoint_capture_rat = '0;
    checkpoint_capture_free = '0;
    if (branch_accept[0]) begin
      checkpoint_capture_valid = 1'b1;
      checkpoint_capture_tag = rob_alloc_tag[0];
      checkpoint_capture_seq = dispatch_seq_lane[0];
      checkpoint_capture_rat = rename_rat_snapshot[0];
      checkpoint_capture_free = rename_free_snapshot[0];
    end else if (branch_accept[1]) begin
      checkpoint_capture_valid = 1'b1;
      checkpoint_capture_tag = rob_alloc_tag[1];
      checkpoint_capture_seq = dispatch_seq_lane[1];
      checkpoint_capture_rat = rename_rat_snapshot[1];
      checkpoint_capture_free = rename_free_snapshot[1];
    end
  end

  assign rename_restore_rat = recovery_valid ? checkpoint_restore_rat : restore_rat;
  assign rename_restore_free = recovery_valid ? checkpoint_restore_free : restore_free_bitmap;
  assign branch_resolve_ready = branch_resolve_tag_found && branch_checkpoint_found;
  assign recovery_branch_tag = checkpoint_recover_tag;
  assign recovery_seq = checkpoint_recover_seq;
  assign recovery_pc = branch_actual_target;

  assign source1_phys_tag = prs1;
  assign source2_phys_tag = prs2;

  for (genvar rlane = 0; rlane < WIDTH; rlane++) begin : g_rename_inputs
    assign rename_rs1[rlane] = decoded_uop[rlane].rs1;
    assign rename_rs2[rlane] = decoded_uop[rlane].rs2;
    assign rename_rd[rlane] = decoded_uop[rlane].rd;
    assign rename_writes_rd[rlane] = decoded_uop[rlane].writes_rd;
  end

  for (genvar lane = 0; lane < WIDTH; lane++) begin : g_uop_pack
    always_comb begin
      backend_uop[lane] = '0;
      backend_uop[lane].valid = rename_out_valid[lane];
      backend_uop[lane].pc = decoded_uop[lane].pc;
      backend_uop[lane].instruction = decoded_uop[lane].instruction;
      backend_uop[lane].immediate = decoded_uop[lane].immediate;
      backend_uop[lane].alu_op = decoded_uop[lane].alu_op;
      backend_uop[lane].rob_tag = rob_alloc_tag[lane];
      backend_uop[lane].seq_num = dispatch_seq_lane[lane];
      backend_uop[lane].dst_tag = prd[lane];
      backend_uop[lane].writes_dst = decoded_uop[lane].writes_rd &&
                                     (decoded_uop[lane].rd != '0);
      backend_uop[lane].src1_tag = prs1[lane];
      backend_uop[lane].src2_tag = prs2[lane];
      backend_uop[lane].src1_ready = (decoded_uop[lane].rs1 == '0) || src1_ready[lane];
      backend_uop[lane].src2_ready = (decoded_uop[lane].rs2 == '0) || src2_ready[lane];
      backend_uop[lane].src1_value = (decoded_uop[lane].rs1 == '0) ? 64'd0 : src1_value[lane];
      backend_uop[lane].src2_value = (decoded_uop[lane].rs2 == '0) ?
                                      decoded_uop[lane].immediate : src2_value[lane];
      backend_uop[lane].is_load = decoded_uop[lane].is_load;
      backend_uop[lane].is_store = decoded_uop[lane].is_store;
      backend_uop[lane].is_branch = decoded_uop[lane].is_branch;
      backend_uop[lane].is_jump = decoded_uop[lane].is_jump;
      branch_dispatch_uop[lane] = backend_uop[lane];
      memory_dispatch_uop[lane] = backend_uop[lane];
    end
    assign rob_alloc_pc[lane] = decoded_uop[lane].pc;
    assign rob_alloc_rd[lane] = decoded_uop[lane].rd;
    assign rob_alloc_prd[lane] = prd[lane];
    assign rob_alloc_old_prd[lane] = old_prd[lane];
    assign rob_alloc_kind[lane] = {decoded_uop[lane].is_branch,
                                   decoded_uop[lane].is_store,
                                   decoded_uop[lane].is_load,
                                   decoded_uop[lane].is_jump,
                                   decoded_uop[lane].writes_rd,
                                   2'b00};
  end

  rename_unit #(
    .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS),
    .WIDTH(WIDTH)
  ) u_rename (
    .clk(clk),
    .rst_n(rst_n),
    .flush(flush),
    .recover(recovery_valid),
    .restore_rat(rename_restore_rat),
    .restore_free_bitmap(rename_restore_free),
    .reclaim_bitmap(tracker_reclaim_bitmap),
    .in_valid(decoded_valid),
    .in_ready(rename_in_ready),
    .in_rs1(rename_rs1),
    .in_rs2(rename_rs2),
    .in_rd(rename_rd),
    .in_writes_rd(rename_writes_rd),
    .out_valid(rename_out_valid),
    .out_ready(rename_out_ready),
    .out_prs1(prs1),
    .out_prs2(prs2),
    .out_prd(prd),
    .out_old_prd(old_prd),
    .out_rat_snapshot(rename_rat_snapshot),
    .out_free_snapshot(rename_free_snapshot),
    .commit_free_valid(commit_free_valid),
    .commit_free_tag(commit_free_tag),
    .commit_map_valid(commit_fire),
    .commit_map_arch_rd(retire_rd),
    .commit_map_new_prd(retire_prd),
    .rat_debug(rat_debug),
    .committed_rat_debug(committed_rat_debug),
    .free_debug(free_debug),
    .committed_free_bitmap_debug(committed_free_bitmap_debug)
  );

  branch_checkpoint_manager #(
    .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS),
    .PHYS_W(PHYS_W),
    .ROB_TAG_W(ROB_TAG_W),
    .NUM_CHECKPOINTS(NUM_BRANCH_CHECKPOINTS)
  ) u_branch_checkpoints (
    .clk(clk),
    .rst_n(rst_n),
    .flush_all(flush),
    .capture_valid(checkpoint_capture_valid),
    .capture_ready(checkpoint_capture_ready),
    .capture_id(checkpoint_capture_id),
    .capture_rob_tag(checkpoint_capture_tag),
    .capture_seq(checkpoint_capture_seq),
    .capture_rat(checkpoint_capture_rat),
    .capture_free_bitmap(checkpoint_capture_free),
    .commit_free_valid(commit_free_valid),
    .commit_free_tag(commit_free_tag),
    .reclaim_bitmap(tracker_reclaim_bitmap),
    .resolve_valid(branch_resolve_valid),
    .resolve_rob_tag(branch_resolve_tag),
    .resolve_mispredict(branch_mispredict),
    .resolve_tag_live(branch_resolve_tag_found),
    .resolve_found(branch_checkpoint_found),
    .recover_valid(recovery_valid),
    .recover_rob_tag(checkpoint_recover_tag),
    .recover_seq(checkpoint_recover_seq),
    .restore_rat(checkpoint_restore_rat),
    .restore_free_bitmap(checkpoint_restore_free),
    .checkpoint_count(checkpoint_count)
  );

  // Recover sequence is fed to the issue queue so older queued work survives.
  mx64_integer_backend #(
    .WIDTH(WIDTH),
    .IQ_DEPTH(IQ_DEPTH),
    .ROB_DEPTH(ROB_DEPTH),
    .ROB_TAG_W(ROB_TAG_W),
    .PHYS_W(PHYS_W),
    .PHYS_REGS(PHYS_REGS)
  ) u_backend (
    .clk(clk),
    .rst_n(rst_n),
    .flush(flush),
    .tag_query_valid(branch_resolve_valid),
    .tag_query_tag(branch_resolve_tag),
    .tag_query_found(branch_resolve_tag_found),
    .recover_valid(recovery_valid),
    .recover_tag(checkpoint_recover_tag),
    .recover_seq(checkpoint_recover_seq),
    .recover_found(recovery_rob_tag_found),
    .branch_complete_valid(branch_resolve_valid && branch_resolve_ready),
    .branch_complete_tag(branch_resolve_tag),
    .branch_complete_value(branch_result_value),
    .branch_complete_exception(1'b0),
    .branch_complete_exception_code(4'd0),
    .branch_complete_exception_value(64'd0),
    .memory_complete_valid, .memory_complete_tag, .memory_complete_value,
    .memory_complete_exception, .memory_complete_exception_code,
    .memory_complete_exception_value,
    .branch_wb_valid, .branch_wb_tag, .branch_wb_data,
    .map_release_valid(commit_free_valid), .map_release_tag(commit_free_tag),
    .external_ref_acquire_valid, .external_ref_acquire_tag,
    .external_ref_release_valid, .external_ref_release_tag,
    .physical_ref_bitmap, .physical_reclaim_bitmap(tracker_reclaim_bitmap),
    .physical_ref_count,
    .rob_alloc_valid(rob_alloc_valid),
    .rob_alloc_ready(rob_alloc_ready),
    .rob_alloc_tag(rob_alloc_tag),
    .rob_alloc_pc(rob_alloc_pc),
    .rob_alloc_rd(rob_alloc_rd),
    .rob_alloc_kind(rob_alloc_kind),
    .rob_alloc_prd(rob_alloc_prd),
    .rob_alloc_old_prd(rob_alloc_old_prd),
    .rob_alloc_exception(rob_alloc_exception),
    .rob_alloc_exception_code(rob_alloc_exception_code),
    .rob_alloc_exception_value(rob_alloc_exception_value),
    .dispatch_valid(backend_dispatch_valid),
    .dispatch_ready(backend_dispatch_ready),
    .dispatch_uop(backend_uop),
    .int_wb_valid(int_wb_valid), .int_wb_tag(int_wb_tag), .int_wb_data(int_wb_data),
    .retire_valid(retire_valid),
    .retire_ready(retire_ready),
    .retire_tag(retire_tag),
    .retire_pc(retire_pc),
    .retire_rd(retire_rd),
    .retire_kind(retire_kind),
    .retire_prd(retire_prd),
    .retire_old_prd(retire_old_prd),
    .retire_value(retire_value),
    .retire_exception(retire_exception),
    .retire_exception_code(retire_exception_code),
    .retire_exception_value(retire_exception_value),
    .rob_full(rob_full),
    .rob_empty(rob_empty),
    .rob_occupancy(rob_occupancy),
    .issue_occupancy(issue_occupancy)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      dispatch_seq_q <= '0;
    else if (recovery_valid)
      dispatch_seq_q <= checkpoint_recover_seq + 32'd1;
    else if (!flush)
      dispatch_seq_q <= dispatch_seq_q + 32'(dispatch_accept[0]) + 32'(dispatch_accept[1]);
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (decoded_valid[lane] && decoded_ready[lane]) begin
          assert (rename_out_valid[lane] && rename_out_ready[lane] &&
                  rob_alloc_valid[lane] && rob_alloc_ready[lane] &&
                  ((dispatch_exception[lane]) ||
                   (control_transfer[lane] && branch_dispatch_valid[lane] && branch_dispatch_ready[lane]) ||
                   (memory_operation[lane] && memory_dispatch_valid[lane] && memory_dispatch_ready[lane]) ||
                   (!control_transfer[lane] && !memory_operation[lane] && !dispatch_exception[lane] &&
                    backend_dispatch_valid[lane] && backend_dispatch_ready[lane])))
            else $error("MX64 atomic dispatch handshake violated");
        end
      end
      if (branch_resolve_valid && branch_resolve_ready)
        assert (branch_resolve_tag_found && branch_checkpoint_found)
          else $error("Accepted branch resolution lacked a live ROB/checkpoint tag");
      if (recovery_valid)
        assert (recovery_rob_tag_found)
          else $error("Branch checkpoint/ROB recovery tag mismatch");
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (memory_dispatch_valid[lane] && memory_dispatch_ready[lane])
          assert ((memory_dispatch_uop[lane].is_load || memory_dispatch_uop[lane].is_store) &&
                  !backend_dispatch_valid[lane])
            else $error("Memory uop leaked into integer backend or lost memory classification");
      end
    end
  end
`endif
endmodule
