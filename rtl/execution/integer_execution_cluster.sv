// MX64 M2.1: two-lane integer execution cluster.
// Contract: the connected issue queue must receive integer-ALU uops only.
// Loads, stores and branches require their own execution/LSU units.
module integer_execution_cluster #(
  parameter int WIDTH = 2,
  parameter int XLEN = 64,
  parameter int PHYS_W = 7,
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W,
  parameter int IQ_DEPTH = 16
) (
  input  logic clk,
  input  logic rst_n,
  input  logic flush,
  input  logic recover_valid,
  input  logic [31:0] recover_seq,
  input logic external_wakeup_valid,
  input logic [PHYS_W-1:0] external_wakeup_tag,
  input logic [XLEN-1:0] external_wakeup_data,

  input  logic [WIDTH-1:0] dispatch_valid,
  output logic [WIDTH-1:0] dispatch_ready,
  input  mx64_pkg::issue_uop_t dispatch_uop [0:WIDTH-1],

  output logic [WIDTH-1:0] completion_valid,
  output logic [WIDTH-1:0][ROB_TAG_W-1:0] completion_rob_tag,
  output logic [WIDTH-1:0][PHYS_W-1:0] completion_dst_tag,
  output logic [WIDTH-1:0] completion_writes_dst,
  output logic [WIDTH-1:0][XLEN-1:0] completion_data,

  output logic [2*WIDTH-1:0] ref_acquire_valid,
  output logic [2*WIDTH-1:0][PHYS_W-1:0] ref_acquire_tag,
  output logic [2*IQ_DEPTH-1:0] ref_release_valid,
  output logic [2*IQ_DEPTH-1:0][PHYS_W-1:0] ref_release_tag,
  output logic [$clog2(IQ_DEPTH+1)-1:0] issue_occupancy
);
  import mx64_pkg::*;

  issue_uop_t issued_uop [0:WIDTH-1];
  logic [WIDTH-1:0] issue_valid;
  logic [WIDTH-1:0] issue_ready;
  logic [WIDTH:0] wakeup_valid;
  logic [WIDTH:0][PHYS_W-1:0] wakeup_tag;
  logic [WIDTH:0][XLEN-1:0] wakeup_data;
  logic [WIDTH-1:0][XLEN-1:0] alu_result;
  logic [WIDTH-1:0] alu_zero;
  logic [WIDTH-1:0] alu_signed_lt;
  logic [WIDTH-1:0] alu_unsigned_lt;

  logic [WIDTH-1:0] completion_valid_q;
  logic [WIDTH-1:0][ROB_TAG_W-1:0] completion_rob_tag_q;
  logic [WIDTH-1:0][PHYS_W-1:0] completion_dst_tag_q;
  logic [WIDTH-1:0] completion_writes_dst_q;
  logic [WIDTH-1:0][XLEN-1:0] completion_data_q;
  logic [WIDTH-1:0][31:0] completion_seq_q;
  logic [WIDTH-1:0] completion_killed;

  logic iq_full;
  logic iq_empty;

  // This first execution slice has no downstream backpressure: results are
  // captured every cycle. A future multi-cycle unit must add reservation/
  // ready handling rather than silently dropping issued operations.
  assign issue_ready = {WIDTH{1'b1}};

  // Only completed destination-producing operations broadcast wakeups.
  always_comb begin
    wakeup_valid = '0;
    wakeup_tag = '0;
    wakeup_data = '0;
    for (int lane = 0; lane < WIDTH; lane++) begin
      wakeup_valid[lane] = completion_valid_q[lane] & completion_writes_dst_q[lane];
      wakeup_tag[lane] = completion_dst_tag_q[lane];
      wakeup_data[lane] = completion_data_q[lane];
    end
    wakeup_valid[WIDTH] = external_wakeup_valid;
    wakeup_tag[WIDTH] = external_wakeup_tag;
    wakeup_data[WIDTH] = external_wakeup_data;
  end

  issue_queue #(
    .DEPTH(IQ_DEPTH),
    .WIDTH(WIDTH),
    .WAKEUP_WIDTH(WIDTH+1),
    .XLEN(XLEN),
    .PHYS_W(PHYS_W),
    .ROB_TAG_W(ROB_TAG_W)
  ) u_integer_issue_queue (
    .clk(clk),
    .rst_n(rst_n),
    .flush(flush),
    .recover_valid(recover_valid),
    .recover_seq(recover_seq),
    .enq_valid(dispatch_valid),
    .enq_ready(dispatch_ready),
    .enq_uop(dispatch_uop),
    .wakeup_valid(wakeup_valid),
    .wakeup_tag(wakeup_tag),
    .wakeup_data(wakeup_data),
    .issue_valid(issue_valid),
    .issue_ready(issue_ready),
    .issue_uop(issued_uop),
    .ref_acquire_valid, .ref_acquire_tag,
    .ref_release_valid, .ref_release_tag,
    .occupancy(issue_occupancy),
    .full(iq_full),
    .empty(iq_empty)
  );

  for (genvar lane = 0; lane < WIDTH; lane++) begin : g_alu
    integer_alu u_alu (
      .a(issued_uop[lane].src1_value),
      .b(issued_uop[lane].src2_value),
      .op(issued_uop[lane].alu_op),
      .result(alu_result[lane]),
      .zero(alu_zero[lane]),
      .signed_lt(alu_signed_lt[lane]),
      .unsigned_lt(alu_unsigned_lt[lane])
    );
  end

  always_ff @(posedge clk or negedge rst_n) begin : p_completion
    if (!rst_n) begin
      completion_valid_q      <= '0;
      completion_rob_tag_q    <= '0;
      completion_dst_tag_q    <= '0;
      completion_writes_dst_q <= '0;
      completion_data_q       <= '0;
      completion_seq_q        <= '0;
    end else if (flush) begin
      // A global flush invalidates all queued and not-yet-published results.
      completion_valid_q <= '0;
      completion_writes_dst_q <= '0;
    end else if (recover_valid) begin
      // Current-cycle outputs are selectively filtered below. Clear the
      // completion stage after this edge to prevent replaying older results.
      completion_valid_q <= '0;
      completion_writes_dst_q <= '0;
    end else begin
      completion_valid_q <= issue_valid;
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (issue_valid[lane]) begin
          completion_rob_tag_q[lane] <= ROB_TAG_W'(issued_uop[lane].rob_tag);
          completion_dst_tag_q[lane] <= PHYS_W'(issued_uop[lane].dst_tag);
          completion_writes_dst_q[lane] <= issued_uop[lane].writes_dst;
          completion_data_q[lane] <= alu_result[lane];
          completion_seq_q[lane] <= issued_uop[lane].seq_num;
        end else begin
          completion_writes_dst_q[lane] <= 1'b0;
        end
      end
    end
  end

  // Suppress a younger result combinationally in the recovery cycle. This
  // prevents stale PRF writes and stale ROB completion before state is cleared.
  always_comb begin
    completion_killed = '0;
    for (int lane = 0; lane < WIDTH; lane++) begin
      if (recover_valid &&
          ($signed(completion_seq_q[lane] - recover_seq) > 0))
        completion_killed[lane] = 1'b1;
    end
  end

  assign completion_valid      = completion_valid_q & ~completion_killed;
  assign completion_rob_tag    = completion_rob_tag_q;
  assign completion_dst_tag    = completion_dst_tag_q;
  assign completion_writes_dst = completion_writes_dst_q & ~completion_killed;
  assign completion_data       = completion_data_q;

`ifndef SYNTHESIS
  // Integration guard: this module is intentionally integer-ALU-only.
  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (dispatch_valid[lane] && dispatch_ready[lane]) begin
          assert (!dispatch_uop[lane].is_load &&
                  !dispatch_uop[lane].is_store &&
                  !dispatch_uop[lane].is_branch)
            else $error("Non-integer uop dispatched to integer_execution_cluster");
        end
      end
    end
  end
`endif
endmodule
