// MX64-H Phase 29: retains branch source physical tags from accepted dispatch
// until resolution, and releases younger retained tags on mispredict recovery.
module branch_reference_lifecycle #(
  parameter int WIDTH = 2,
  parameter int ROB_DEPTH = 48,
  parameter int PHYS_W = 7,
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W
) (
  input logic clk,
  input logic rst_n,
  input logic flush_all,
  input logic [WIDTH-1:0] dispatch_valid,
  input logic [WIDTH-1:0] dispatch_ready,
  input mx64_pkg::issue_uop_t dispatch_uop [0:WIDTH-1],
  input logic resolve_valid,
  input logic [ROB_TAG_W-1:0] resolve_tag,
  input logic mispredict,
  output logic [2*WIDTH-1:0] acquire_valid,
  output logic [2*WIDTH-1:0][PHYS_W-1:0] acquire_tag,
  output logic [2*ROB_DEPTH-1:0] release_valid,
  output logic [2*ROB_DEPTH-1:0][PHYS_W-1:0] release_tag,
  output logic [$clog2(ROB_DEPTH+1)-1:0] retained_count
);
  logic [ROB_DEPTH-1:0] valid_q, valid_d;
  logic [ROB_TAG_W-1:0] rob_tag_q [0:ROB_DEPTH-1], rob_tag_d [0:ROB_DEPTH-1];
  logic [31:0] seq_q [0:ROB_DEPTH-1], seq_d [0:ROB_DEPTH-1];
  logic [PHYS_W-1:0] src1_q [0:ROB_DEPTH-1], src1_d [0:ROB_DEPTH-1];
  logic [PHYS_W-1:0] src2_q [0:ROB_DEPTH-1], src2_d [0:ROB_DEPTH-1];
  logic resolve_found;
  logic [31:0] resolve_seq;

  always_comb begin
    acquire_valid = '0;
    acquire_tag = '0;
    for (int lane = 0; lane < WIDTH; lane++) begin
      if (!flush_all && dispatch_valid[lane] && dispatch_ready[lane] && (dispatch_uop[lane].is_branch || dispatch_uop[lane].is_jump)) begin
        acquire_valid[2*lane] = 1'b1;
        acquire_valid[2*lane+1] = 1'b1;
        acquire_tag[2*lane] = PHYS_W'(dispatch_uop[lane].src1_tag);
        acquire_tag[2*lane+1] = PHYS_W'(dispatch_uop[lane].src2_tag);
      end
    end

    resolve_found = 1'b0;
    resolve_seq = '0;
    for (int i = 0; i < ROB_DEPTH; i++) begin
      if (valid_q[i] && rob_tag_q[i] == resolve_tag) begin
        resolve_found = 1'b1;
        resolve_seq = seq_q[i];
      end
    end

    release_valid = '0;
    release_tag = '0;
    for (int i = 0; i < ROB_DEPTH; i++) begin
      if (valid_q[i] && (flush_all ||
          (resolve_valid && (rob_tag_q[i] == resolve_tag)) ||
          (resolve_valid && mispredict && resolve_found &&
           ($signed(seq_q[i] - resolve_seq) > 0)))) begin
        release_valid[2*i] = 1'b1;
        release_valid[2*i+1] = 1'b1;
        release_tag[2*i] = src1_q[i];
        release_tag[2*i+1] = src2_q[i];
      end
    end
  end

  always_comb begin
    bit slot_found;
    valid_d = valid_q;
    for (int i = 0; i < ROB_DEPTH; i++) begin
      rob_tag_d[i] = rob_tag_q[i];
      seq_d[i] = seq_q[i];
      src1_d[i] = src1_q[i];
      src2_d[i] = src2_q[i];
      if (release_valid[2*i]) valid_d[i] = 1'b0;
    end
    // Reuse slots freed by resolution/recovery in this same cycle.
    for (int lane = 0; lane < WIDTH; lane++) begin
      slot_found = 1'b0;
      if (!flush_all && dispatch_valid[lane] && dispatch_ready[lane] && (dispatch_uop[lane].is_branch || dispatch_uop[lane].is_jump)) begin
        for (int i = 0; i < ROB_DEPTH; i++) begin
          if (!valid_d[i] && !slot_found) begin
            valid_d[i] = 1'b1;
            rob_tag_d[i] = dispatch_uop[lane].rob_tag;
            seq_d[i] = dispatch_uop[lane].seq_num;
            src1_d[i] = PHYS_W'(dispatch_uop[lane].src1_tag);
            src2_d[i] = PHYS_W'(dispatch_uop[lane].src2_tag);
            slot_found = 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      for (int i = 0; i < ROB_DEPTH; i++) begin
        rob_tag_q[i] <= '0; seq_q[i] <= '0; src1_q[i] <= '0; src2_q[i] <= '0;
      end
    end else begin
      valid_q <= valid_d;
      for (int i = 0; i < ROB_DEPTH; i++) begin
        rob_tag_q[i] <= rob_tag_d[i]; seq_q[i] <= seq_d[i];
        src1_q[i] <= src1_d[i]; src2_q[i] <= src2_d[i];
      end
    end
  end

  always_comb begin
    retained_count = '0;
    for (int i = 0; i < ROB_DEPTH; i++) retained_count += valid_q[i];
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      assert (retained_count <= ROB_DEPTH) else $error("branch reference table overflow");
      if (resolve_valid) assert (resolve_found) else $error("branch resolve has no retained reference entry");
    end
  end
`endif
endmodule
