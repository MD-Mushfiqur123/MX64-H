// MX64-H branch speculation snapshots keyed by the full ROB allocation tag.
// Capture occurs only for an accepted branch dispatch. A correct resolution
// releases exactly that checkpoint; a misprediction restores it and discards
// that checkpoint plus every younger checkpoint.
module branch_checkpoint_manager #(
  parameter int ARCH_REGS = 32,
  parameter int PHYS_REGS = 80,
  parameter int PHYS_W = $clog2(PHYS_REGS),
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W,
  parameter int SEQ_W = 32,
  parameter int WIDTH = 2,
  parameter int NUM_CHECKPOINTS = 16,
  parameter int ID_W = (NUM_CHECKPOINTS <= 2) ? 1 : $clog2(NUM_CHECKPOINTS),
  parameter int COUNT_W = $clog2(NUM_CHECKPOINTS + 1)
) (
  input logic clk,
  input logic rst_n,
  input logic flush_all,

  input logic capture_valid,
  output logic capture_ready,
  output logic [ID_W-1:0] capture_id,
  input logic [ROB_TAG_W-1:0] capture_rob_tag,
  input logic [SEQ_W-1:0] capture_seq,
  input logic [ARCH_REGS-1:0][PHYS_W-1:0] capture_rat,
  input logic [PHYS_REGS-1:0] capture_free_bitmap,
  input logic [WIDTH-1:0] commit_free_valid,
  input logic [WIDTH-1:0][PHYS_W-1:0] commit_free_tag,
  input logic [PHYS_REGS-1:0] reclaim_bitmap,

  input logic resolve_valid,
  input logic [ROB_TAG_W-1:0] resolve_rob_tag,
  input logic resolve_mispredict,
  input logic resolve_tag_live,
  output logic resolve_found,
  output logic recover_valid,
  output logic [ROB_TAG_W-1:0] recover_rob_tag,
  output logic [SEQ_W-1:0] recover_seq,
  output logic [ARCH_REGS-1:0][PHYS_W-1:0] restore_rat,
  output logic [PHYS_REGS-1:0] restore_free_bitmap,

  output logic [COUNT_W-1:0] checkpoint_count
);
  logic [NUM_CHECKPOINTS-1:0] valid_q;
  logic [NUM_CHECKPOINTS-1:0][ARCH_REGS-1:0][PHYS_W-1:0] rat_q;
  logic [NUM_CHECKPOINTS-1:0][PHYS_REGS-1:0] free_q;
  logic [NUM_CHECKPOINTS-1:0][ROB_TAG_W-1:0] rob_tag_q;
  logic [NUM_CHECKPOINTS-1:0][SEQ_W-1:0] seq_q;
  logic [NUM_CHECKPOINTS-1:0][ID_W-1:0] order_q;
  logic [COUNT_W-1:0] count_q;
  integer free_slot;
  integer resolve_pos;
  logic resolve_fire;

  always_comb begin
    free_slot = -1;
    resolve_pos = -1;
    for (int i = 0; i < NUM_CHECKPOINTS; i++) begin
      if (!valid_q[i] && free_slot < 0)
        free_slot = i;
      if (i < count_q && rob_tag_q[order_q[i]] == resolve_rob_tag)
        resolve_pos = i;
    end

    resolve_found = (resolve_pos >= 0); // combinational tag-match, used for ready
    resolve_fire = resolve_valid && resolve_found && resolve_tag_live && !flush_all;
    capture_ready = (free_slot >= 0) && (count_q < NUM_CHECKPOINTS) &&
                    !resolve_valid && !flush_all;
    capture_id = (free_slot >= 0) ? ID_W'(free_slot) : '0;

    recover_valid = resolve_fire && resolve_mispredict;
    recover_rob_tag = resolve_rob_tag;
    recover_seq = '0;
    restore_rat = '0;
    restore_free_bitmap = '0;
    if (resolve_fire && resolve_mispredict) begin
      recover_seq = seq_q[order_q[resolve_pos]];
      restore_rat = rat_q[order_q[resolve_pos]];
      restore_free_bitmap = free_q[order_q[resolve_pos]];
    end
    checkpoint_count = count_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      count_q <= '0;
      for (int i = 0; i < NUM_CHECKPOINTS; i++) begin
        rat_q[i] <= '0;
        free_q[i] <= '0;
        rob_tag_q[i] <= '0;
        seq_q[i] <= '0;
        order_q[i] <= '0;
      end
    end else if (flush_all) begin
      valid_q <= '0;
      count_q <= '0;
    end else begin
      // Retirement frees can happen after a branch checkpoint was captured.
      // They are architecturally older than every live checkpoint and must be
      // merged into each snapshot so recovery cannot resurrect allocated tags.
      for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
        if (valid_q[cp]) begin
          // Delayed zero-reference releases must be merged into all live
          // snapshots, preventing recovery from resurrecting reclaimed tags.
          for (int r = 1; r < PHYS_REGS; r++) begin
            if (reclaim_bitmap[r]) free_q[cp][r] <= 1'b1;
          end
        end
      end

      if (resolve_fire && resolve_mispredict) begin
      // Keep all older unresolved branches; discard the resolved branch and
      // every branch dispatched after it.
      for (int i = 0; i < NUM_CHECKPOINTS; i++) begin
        if (i >= resolve_pos && i < count_q)
          valid_q[order_q[i]] <= 1'b0;
      end
      count_q <= COUNT_W'(resolve_pos);
      end else if (resolve_fire) begin
      // Correct prediction: remove only this checkpoint and compact the order
      // list so younger unresolved branches remain recoverable.
      valid_q[order_q[resolve_pos]] <= 1'b0;
      for (int i = 0; i < NUM_CHECKPOINTS-1; i++) begin
        if (i >= resolve_pos && i < (count_q - 1))
          order_q[i] <= order_q[i+1];
      end
      count_q <= count_q - 1'b1;
      end else if (capture_valid && capture_ready) begin
      valid_q[free_slot] <= 1'b1;
      rat_q[free_slot] <= capture_rat;
      free_q[free_slot] <= capture_free_bitmap;
      rob_tag_q[free_slot] <= capture_rob_tag;
      seq_q[free_slot] <= capture_seq;
      order_q[count_q] <= ID_W'(free_slot);
      count_q <= count_q + 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (NUM_CHECKPOINTS < 2) $error("At least two branch checkpoints are required");
    if (NUM_CHECKPOINTS > (1 << ID_W)) $error("Checkpoint ID width is too small");
  end
`endif
endmodule
