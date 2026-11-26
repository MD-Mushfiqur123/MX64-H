// MX64 M2.2: integer execution-to-ROB completion/retirement integration.
// The frontend/rename/dispatch controller owns atomic ROB allocation + IQ
// enqueue. It must place the ROB alloc_tag into each accepted issue_uop.rob_tag.
module mx64_integer_backend #(
  parameter int WIDTH = 2,
  parameter int IQ_DEPTH = 16,
  parameter int ROB_DEPTH = 48,
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W,
  parameter int PHYS_W = 7,
  parameter int PHYS_REGS = 80,
  parameter int EXTERNAL_REF_WIDTH = 8
) (
  input logic clk,
  input logic rst_n,
  input logic flush,
  input logic tag_query_valid,
  input logic [ROB_TAG_W-1:0] tag_query_tag,
  output logic tag_query_found,
  input logic recover_valid,
  input logic [ROB_TAG_W-1:0] recover_tag,
  input logic [31:0] recover_seq,
  output logic recover_found,
  input logic branch_complete_valid,
  input logic [ROB_TAG_W-1:0] branch_complete_tag,
  input logic [63:0] branch_complete_value,
  input logic branch_complete_exception,
  input logic [3:0] branch_complete_exception_code,
  input logic [63:0] branch_complete_exception_value,
  // Memory execution completion is independent of PRF writeback: stores
  // complete without a destination write, while successful loads write PRF.
  input logic memory_complete_valid,
  input logic [ROB_TAG_W-1:0] memory_complete_tag,
  input logic [63:0] memory_complete_value,
  input logic memory_complete_exception,
  input logic [3:0] memory_complete_exception_code,
  input logic [63:0] memory_complete_exception_value,
  input logic branch_wb_valid,
  input logic [PHYS_W-1:0] branch_wb_tag,
  input logic [63:0] branch_wb_data,
  input logic [WIDTH-1:0] map_release_valid,
  input logic [WIDTH-1:0][PHYS_W-1:0] map_release_tag,
  // Lifetime events from external consumers (branch unit, LSU, FP/SIMD, etc.).
  // Acquire on accepted retention; release exactly once when the tag is no longer held.
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_acquire_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][PHYS_W-1:0] external_ref_acquire_tag,
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_release_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][PHYS_W-1:0] external_ref_release_tag,
  output logic [PHYS_REGS-1:0] physical_ref_bitmap,
  output logic [PHYS_REGS-1:0] physical_reclaim_bitmap,
  output logic [PHYS_REGS-1:0][7:0] physical_ref_count,

  // ROB allocation interface. Allocation metadata is architectural metadata;
  // alloc_rd must be the architectural destination register, not phys dst.
  input logic [WIDTH-1:0] rob_alloc_valid,
  output logic [WIDTH-1:0] rob_alloc_ready,
  output logic [WIDTH-1:0][ROB_TAG_W-1:0] rob_alloc_tag,
  input logic [WIDTH-1:0][63:0] rob_alloc_pc,
  input logic [WIDTH-1:0][4:0] rob_alloc_rd,
  input logic [WIDTH-1:0][6:0] rob_alloc_kind,
  input logic [WIDTH-1:0][PHYS_W-1:0] rob_alloc_prd,
  input logic [WIDTH-1:0][PHYS_W-1:0] rob_alloc_old_prd,
  input logic [WIDTH-1:0] rob_alloc_exception,
  input logic [WIDTH-1:0][3:0] rob_alloc_exception_code,
  input logic [WIDTH-1:0][63:0] rob_alloc_exception_value,

  // Integer uops must only be dispatched after matching ROB allocation.
  input logic [WIDTH-1:0] dispatch_valid,
  output logic [WIDTH-1:0] dispatch_ready,
  input mx64_pkg::issue_uop_t dispatch_uop [0:WIDTH-1],
  output logic [WIDTH-1:0] int_wb_valid,
  output logic [WIDTH-1:0][PHYS_W-1:0] int_wb_tag,
  output logic [WIDTH-1:0][63:0] int_wb_data,

  // In-order retirement interface to architectural state/commit map.
  output logic [WIDTH-1:0] retire_valid,
  input logic [WIDTH-1:0] retire_ready,
  output logic [WIDTH-1:0][ROB_TAG_W-1:0] retire_tag,
  output logic [WIDTH-1:0][63:0] retire_pc,
  output logic [WIDTH-1:0][4:0] retire_rd,
  output logic [WIDTH-1:0][6:0] retire_kind,
  output logic [WIDTH-1:0][PHYS_W-1:0] retire_prd,
  output logic [WIDTH-1:0][PHYS_W-1:0] retire_old_prd,
  output logic [WIDTH-1:0][63:0] retire_value,
  output logic [WIDTH-1:0] retire_exception,
  output logic [WIDTH-1:0][3:0] retire_exception_code,
  output logic [WIDTH-1:0][63:0] retire_exception_value,

  output logic rob_full,
  output logic rob_empty,
  output logic [$clog2(ROB_DEPTH+1)-1:0] rob_occupancy,
  output logic [$clog2(IQ_DEPTH+1)-1:0] issue_occupancy
);
  logic [WIDTH-1:0] completion_valid;
  logic [WIDTH-1:0][ROB_TAG_W-1:0] completion_rob_tag;
  logic [WIDTH-1:0][PHYS_W-1:0] completion_dst_tag;
  logic [WIDTH-1:0] completion_writes_dst;
  logic [WIDTH-1:0][63:0] completion_data;
  logic [WIDTH-1:0] completion_exception;
  logic [WIDTH+1:0] rob_complete_valid;
  logic [WIDTH+1:0][ROB_TAG_W-1:0] rob_complete_tag;
  logic [WIDTH+1:0][63:0] rob_complete_value;
  logic [WIDTH+1:0] rob_complete_exception;
  logic [WIDTH+1:0][3:0] rob_complete_exception_code;
  logic [WIDTH+1:0][63:0] rob_complete_exception_value;
  logic [WIDTH-1:0][3:0] completion_exception_code;
  logic [WIDTH-1:0][63:0] completion_exception_value;
  logic [2*WIDTH-1:0] iq_ref_acquire_valid;
  logic [2*WIDTH-1:0][PHYS_W-1:0] iq_ref_acquire_tag;
  logic [2*IQ_DEPTH-1:0] iq_ref_release_valid;
  logic [2*IQ_DEPTH-1:0][PHYS_W-1:0] iq_ref_release_tag;
  localparam int REF_ACQUIRE_WIDTH = 2*WIDTH + WIDTH + WIDTH + EXTERNAL_REF_WIDTH;
  localparam int REF_RELEASE_WIDTH = 2*IQ_DEPTH + WIDTH + WIDTH + EXTERNAL_REF_WIDTH;
  logic [REF_ACQUIRE_WIDTH-1:0] ref_acquire_valid;
  logic [REF_ACQUIRE_WIDTH-1:0][PHYS_W-1:0] ref_acquire_tag;
  logic [REF_RELEASE_WIDTH-1:0] ref_release_valid;
  logic [REF_RELEASE_WIDTH-1:0][PHYS_W-1:0] ref_release_tag;

  assign int_wb_valid = completion_valid & completion_writes_dst;
  assign int_wb_tag = completion_dst_tag;
  assign int_wb_data = completion_data;

  assign completion_exception = '0;
  assign completion_exception_code = '0;
  assign completion_exception_value = '0;
  always_comb begin
    rob_complete_valid = '0;
    rob_complete_tag = '0;
    rob_complete_value = '0;
    rob_complete_exception = '0;
    rob_complete_exception_code = '0;
    rob_complete_exception_value = '0;
    for (int c = 0; c < WIDTH; c++) begin
      rob_complete_valid[c] = completion_valid[c];
      rob_complete_tag[c] = completion_rob_tag[c];
      rob_complete_value[c] = completion_data[c];
      rob_complete_exception[c] = completion_exception[c];
      rob_complete_exception_code[c] = completion_exception_code[c];
      rob_complete_exception_value[c] = completion_exception_value[c];
    end
    rob_complete_valid[WIDTH] = branch_complete_valid;
    rob_complete_tag[WIDTH] = branch_complete_tag;
    rob_complete_value[WIDTH] = branch_complete_value;
    rob_complete_exception[WIDTH] = branch_complete_exception;
    rob_complete_exception_code[WIDTH] = branch_complete_exception_code;
    rob_complete_exception_value[WIDTH] = branch_complete_exception_value;
    rob_complete_valid[WIDTH+1] = memory_complete_valid;
    rob_complete_tag[WIDTH+1] = memory_complete_tag;
    rob_complete_value[WIDTH+1] = memory_complete_value;
    rob_complete_exception[WIDTH+1] = memory_complete_exception;
    rob_complete_exception_code[WIDTH+1] = memory_complete_exception_code;
    rob_complete_exception_value[WIDTH+1] = memory_complete_exception_value;
  end

`ifndef SYNTHESIS
  initial if (ROB_TAG_W != mx64_pkg::ROB_TAG_W || ROB_DEPTH != 48)
    $error("ROB tag type is currently fixed to the 48-entry profile");
`endif

  // Reference domains: unresolved IQ operands, live ROB destination
  // metadata, and speculative/committed architectural mapping ownership.
  always_comb begin
    ref_acquire_valid = '0;
    ref_acquire_tag = '0;
    ref_release_valid = '0;
    ref_release_tag = '0;
    ref_acquire_valid[0 +: 2*WIDTH] = iq_ref_acquire_valid;
    ref_acquire_tag[0 +: 2*WIDTH] = iq_ref_acquire_tag;
    ref_release_valid[0 +: 2*IQ_DEPTH] = iq_ref_release_valid;
    ref_release_tag[0 +: 2*IQ_DEPTH] = iq_ref_release_tag;
    ref_acquire_valid[4*WIDTH +: EXTERNAL_REF_WIDTH] = external_ref_acquire_valid;
    ref_acquire_tag[4*WIDTH +: EXTERNAL_REF_WIDTH] = external_ref_acquire_tag;
    ref_release_valid[2*IQ_DEPTH + 2*WIDTH +: EXTERNAL_REF_WIDTH] = external_ref_release_valid;
    ref_release_tag[2*IQ_DEPTH + 2*WIDTH +: EXTERNAL_REF_WIDTH] = external_ref_release_tag;
    for (int lane = 0; lane < WIDTH; lane++) begin
      // A successfully allocated ROB destination is retained until retirement.
      if (rob_alloc_valid[lane] && rob_alloc_ready[lane] &&
          (rob_alloc_rd[lane] != '0) && rob_alloc_kind[lane][2]) begin
        ref_acquire_valid[2*WIDTH + lane] = 1'b1;
        ref_acquire_tag[2*WIDTH + lane] = rob_alloc_prd[lane];
        // The speculative/committed RAT mapping owns a separate reference.
        ref_acquire_valid[3*WIDTH + lane] = 1'b1;
        ref_acquire_tag[3*WIDTH + lane] = rob_alloc_prd[lane];
      end
      if (retire_valid[lane] && retire_ready[lane] &&
          (retire_rd[lane] != '0) && retire_kind[lane][2] && !retire_exception[lane]) begin
        ref_release_valid[2*IQ_DEPTH + lane] = 1'b1;
        ref_release_tag[2*IQ_DEPTH + lane] = retire_prd[lane];
      end
      if (map_release_valid[lane]) begin
        ref_release_valid[2*IQ_DEPTH + WIDTH + lane] = 1'b1;
        ref_release_tag[2*IQ_DEPTH + WIDTH + lane] = map_release_tag[lane];
      end
    end
  end

  physical_register_reference_tracker #(
    .PHYS_REGS(PHYS_REGS), .TAG_W(PHYS_W), .COUNT_W(8),
    .INIT_ARCH_REGS(32), .ACQUIRE_WIDTH(REF_ACQUIRE_WIDTH),
    .RELEASE_WIDTH(REF_RELEASE_WIDTH)
  ) u_physical_reference_tracker (
    .clk, .rst_n, .clear_all(1'b0),
    .acquire_valid(ref_acquire_valid), .acquire_tag(ref_acquire_tag),
    .release_valid(ref_release_valid), .release_tag(ref_release_tag),
    .referenced_bitmap(physical_ref_bitmap),
    .reclaim_bitmap(physical_reclaim_bitmap),
    .reference_count(physical_ref_count)
  );

  integer_execution_cluster #(
    .WIDTH(WIDTH),
    .XLEN(64),
    .PHYS_W(PHYS_W),
    .ROB_TAG_W(ROB_TAG_W),
    .IQ_DEPTH(IQ_DEPTH)
  ) u_integer_execution (
    .clk(clk),
    .rst_n(rst_n),
    .flush(flush),
    .recover_valid(recover_valid),
    .recover_seq(recover_seq),
    .external_wakeup_valid(branch_wb_valid),
    .external_wakeup_tag(branch_wb_tag),
    .external_wakeup_data(branch_wb_data),
    .ref_acquire_valid(iq_ref_acquire_valid),
    .ref_acquire_tag(iq_ref_acquire_tag),
    .ref_release_valid(iq_ref_release_valid),
    .ref_release_tag(iq_ref_release_tag),
    .dispatch_valid(dispatch_valid),
    .dispatch_ready(dispatch_ready),
    .dispatch_uop(dispatch_uop),
    .completion_valid(completion_valid),
    .completion_rob_tag(completion_rob_tag),
    .completion_dst_tag(completion_dst_tag),
    .completion_writes_dst(completion_writes_dst),
    .completion_data(completion_data),
    .issue_occupancy(issue_occupancy)
  );

  reorder_buffer #(
    .DEPTH(ROB_DEPTH),
    .WIDTH(WIDTH),
    .COMPLETE_WIDTH(WIDTH+2),
    .TAG_W($clog2(ROB_DEPTH)),
    .GEN_W(ROB_TAG_W - $clog2(ROB_DEPTH)),
    .FULL_TAG_W(ROB_TAG_W)
  ) u_reorder_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .flush(flush),
    .tag_query_valid(tag_query_valid),
    .tag_query_tag(tag_query_tag),
    .tag_query_found(tag_query_found),
    .recover_valid(recover_valid),
    .recover_tag(recover_tag),
    .recover_found(recover_found),
    .alloc_valid(rob_alloc_valid),
    .alloc_ready(rob_alloc_ready),
    .alloc_tag(rob_alloc_tag),
    .alloc_pc(rob_alloc_pc),
    .alloc_rd(rob_alloc_rd),
    .alloc_kind(rob_alloc_kind),
    .alloc_prd(rob_alloc_prd),
    .alloc_old_prd(rob_alloc_old_prd),
    .alloc_exception(rob_alloc_exception),
    .alloc_exception_code(rob_alloc_exception_code),
    .alloc_exception_value(rob_alloc_exception_value),
    .complete_valid(rob_complete_valid),
    .complete_tag(rob_complete_tag),
    .complete_value(rob_complete_value),
    .complete_exception(rob_complete_exception),
    .complete_exception_code(rob_complete_exception_code),
    .complete_exception_value(rob_complete_exception_value),
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
    .full(rob_full),
    .empty(rob_empty),
    .occupancy(rob_occupancy)
  );

`ifndef SYNTHESIS
  // Catch the most common integration error: a dispatched uop without a
  // corresponding live ROB entry/tag allocation.
  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (dispatch_valid[lane] && dispatch_ready[lane] &&
            !(rob_alloc_valid[lane] && rob_alloc_ready[lane]))
          $error("MX64 backend: dispatched integer uop without same-lane ROB allocation");
      end
    end
  end
`endif
endmodule
