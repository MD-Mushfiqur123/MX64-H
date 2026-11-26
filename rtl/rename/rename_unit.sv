module rename_unit #(
  parameter int ARCH_REGS = 32,
  parameter int PHYS_REGS = 80,
  parameter int WIDTH = 2,
  parameter int ARCH_W = $clog2(ARCH_REGS),
  parameter int PHYS_W = $clog2(PHYS_REGS)
) (
  input  logic clk,
  input  logic rst_n,
  input  logic flush,
  input  logic recover,

  // Restore snapshot captured at a branch checkpoint. Snapshot must be
  // associated with the surviving speculation point by the dispatch/ROB logic.
  input  logic [ARCH_REGS-1:0][PHYS_W-1:0] restore_rat,
  input  logic [PHYS_REGS-1:0] restore_free_bitmap,
  input  logic [PHYS_REGS-1:0] reclaim_bitmap,

  input  logic [WIDTH-1:0] in_valid,
  output logic [WIDTH-1:0] in_ready,
  input  logic [WIDTH-1:0][ARCH_W-1:0] in_rs1,
  input  logic [WIDTH-1:0][ARCH_W-1:0] in_rs2,
  input  logic [WIDTH-1:0][ARCH_W-1:0] in_rd,
  input  logic [WIDTH-1:0] in_writes_rd,

  output logic [WIDTH-1:0] out_valid,
  input  logic [WIDTH-1:0] out_ready,
  output logic [WIDTH-1:0][PHYS_W-1:0] out_prs1,
  output logic [WIDTH-1:0][PHYS_W-1:0] out_prs2,
  output logic [WIDTH-1:0][PHYS_W-1:0] out_prd,
  output logic [WIDTH-1:0][PHYS_W-1:0] out_old_prd,
  output logic [WIDTH-1:0][ARCH_REGS-1:0][PHYS_W-1:0] out_rat_snapshot,
  output logic [WIDTH-1:0][PHYS_REGS-1:0] out_free_snapshot,

  // Commit frees the previous physical mapping after the instruction retires.
  input  logic [WIDTH-1:0] commit_free_valid,
  input  logic [WIDTH-1:0][PHYS_W-1:0] commit_free_tag,
  input  logic [WIDTH-1:0] commit_map_valid,
  input  logic [WIDTH-1:0][ARCH_W-1:0] commit_map_arch_rd,
  input  logic [WIDTH-1:0][PHYS_W-1:0] commit_map_new_prd,

  output logic [ARCH_REGS-1:0][PHYS_W-1:0] rat_debug,
  output logic [ARCH_REGS-1:0][PHYS_W-1:0] committed_rat_debug,
  output logic [PHYS_REGS-1:0] free_debug,
  output logic [PHYS_REGS-1:0] committed_free_bitmap_debug
);
  logic [ARCH_REGS-1:0][PHYS_W-1:0] rat_q, rat_d;
  logic [ARCH_REGS-1:0][PHYS_W-1:0] committed_rat_q;
  logic [WIDTH-1:0] alloc_req, alloc_valid, alloc_take;
  logic [WIDTH-1:0][PHYS_W-1:0] alloc_tag;
  logic [PHYS_REGS-1:0] free_bitmap;
  logic [PHYS_REGS-1:0] committed_used_bitmap, committed_free_bitmap;
  logic [WIDTH-1:0][PHYS_REGS-1:0] free_bitmap_after_alloc;
  logic [WIDTH-1:0] lane_accept;

  // Corrected signal aliases are declared separately to keep the public
  // interface names explicit and stable.
  logic [WIDTH-1:0][PHYS_W-1:0] src1_tag, src2_tag;

  free_list #(
    .PHYS_REGS(PHYS_REGS), .ARCH_REGS(ARCH_REGS),
    .TAG_W(PHYS_W), .ALLOC_WIDTH(WIDTH)
  ) u_free_list (
    .clk, .rst_n, .flush(flush || recover), .restore_free_bitmap, .reclaim_bitmap,
    .alloc_req, .alloc_valid, .alloc_tag, .alloc_take,
    .free_valid('0), .free_tag('0),
    .free_bitmap,
    .free_bitmap_after_alloc
  );


  always_comb begin
    rat_d = rat_q;
    alloc_req = '0;
    out_valid = '0;
    in_ready = '0;
    lane_accept = '0;
    alloc_take = '0;
    src1_tag = '0;
    src2_tag = '0;
    out_prs1 = '0;
    out_prs2 = '0;
    out_prd = '0;
    out_old_prd = '0;
    out_rat_snapshot = '0;
    out_free_snapshot = free_bitmap_after_alloc;

    // In-order dual-lane rename: a younger lane is considered only if every
    // older valid lane has completed its rename handshake.
    for (int lane = 0; lane < WIDTH; lane++) begin
      if (in_valid[lane] && ((lane == 0) || !in_valid[0] || lane_accept[0])) begin
        src1_tag[lane] = (in_rs1[lane] == '0) ? '0 : rat_d[in_rs1[lane]];
        src2_tag[lane] = (in_rs2[lane] == '0) ? '0 : rat_d[in_rs2[lane]];
        out_prs1[lane] = src1_tag[lane];
        out_prs2[lane] = src2_tag[lane];

        if (in_writes_rd[lane] && (in_rd[lane] != '0)) begin
          alloc_req[lane] = 1'b1;
          if (alloc_valid[lane]) begin
            out_valid[lane] = 1'b1;
            out_prd[lane] = alloc_tag[lane];
            out_old_prd[lane] = rat_d[in_rd[lane]];
            in_ready[lane] = out_ready[lane];
            lane_accept[lane] = out_valid[lane] && out_ready[lane];
            alloc_take[lane] = lane_accept[lane];
            if (lane_accept[lane])
              rat_d[in_rd[lane]] = alloc_tag[lane];
          end
        end else begin
          out_valid[lane] = 1'b1;
          in_ready[lane] = out_ready[lane];
          lane_accept[lane] = out_valid[lane] && out_ready[lane];
        end
      end
      out_rat_snapshot[lane] = rat_d;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < ARCH_REGS; r++) begin
        rat_q[r] <= PHYS_W'(r);
      end
    end else if (flush || recover) begin
      rat_q <= restore_rat;
      rat_q[0] <= '0;
    end else begin
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (lane_accept[lane] && in_writes_rd[lane] && (in_rd[lane] != '0))
          rat_q[in_rd[lane]] <= alloc_tag[lane];
      end
      rat_q[0] <= '0;
    end
  end

  // Commit map advances only on accepted, non-exception retirement handshakes.
  // Ascending lane order makes lane 1 win if both retirements target the same rd.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < ARCH_REGS; r++)
        committed_rat_q[r] <= PHYS_W'(r);
    end else begin
      for (int lane = 0; lane < WIDTH; lane++) begin
        if (commit_map_valid[lane] && (commit_map_arch_rd[lane] != '0))
          committed_rat_q[commit_map_arch_rd[lane]] <= commit_map_new_prd[lane];
      end
      committed_rat_q[0] <= '0;
    end
  end

  always_comb begin
    committed_used_bitmap = '0;
    for (int r = 0; r < ARCH_REGS; r++) begin
      if (int'(committed_rat_q[r]) < PHYS_REGS)
        committed_used_bitmap[committed_rat_q[r]] = 1'b1;
    end
    committed_free_bitmap = ~committed_used_bitmap;
    committed_free_bitmap[0] = 1'b0; // p0 is permanently reserved
  end

  assign rat_debug = rat_q;
  assign committed_rat_debug = committed_rat_q;
  assign free_debug = free_bitmap;
  assign committed_free_bitmap_debug = committed_free_bitmap;

`ifndef SYNTHESIS
  initial begin
    if (ARCH_REGS != 32) $warning("MXISA-64 specification currently defines 32 architectural GPRs");
    if (WIDTH != 2) $warning("Initial microarchitecture target is dual-wide");
  end
`endif
endmodule
