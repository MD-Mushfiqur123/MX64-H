// MX64-H Phase 25: event-driven physical-register reference counter bank.
// Consumers acquire a reference when they retain a physical tag and release
// it when that retention ends. Reclaim is asserted only on a nonzero-to-zero
// transition after all same-cycle acquire/release events have been netted.
module physical_register_reference_tracker #(
  parameter int PHYS_REGS = 80,
  parameter int TAG_W = $clog2(PHYS_REGS),
  parameter int COUNT_W = 8,
  parameter int INIT_ARCH_REGS = 32,
  parameter int ACQUIRE_WIDTH = 4,
  parameter int RELEASE_WIDTH = 4
) (
  input logic clk,
  input logic rst_n,
  input logic clear_all,
  input logic [ACQUIRE_WIDTH-1:0] acquire_valid,
  input logic [ACQUIRE_WIDTH-1:0][TAG_W-1:0] acquire_tag,
  input logic [RELEASE_WIDTH-1:0] release_valid,
  input logic [RELEASE_WIDTH-1:0][TAG_W-1:0] release_tag,
  output logic [PHYS_REGS-1:0] referenced_bitmap,
  output logic [PHYS_REGS-1:0] reclaim_bitmap,
  output logic [PHYS_REGS-1:0][COUNT_W-1:0] reference_count
);
  integer acquire_delta [0:PHYS_REGS-1];
  integer release_delta [0:PHYS_REGS-1];
  integer next_count [0:PHYS_REGS-1];

  always_comb begin
    for (int r = 0; r < PHYS_REGS; r++) begin
      acquire_delta[r] = 0;
      release_delta[r] = 0;
      next_count[r] = int'(reference_count[r]);
    end
    for (int a = 0; a < ACQUIRE_WIDTH; a++) begin
      if (acquire_valid[a] && (acquire_tag[a] < PHYS_REGS))
        acquire_delta[acquire_tag[a]]++;
    end
    for (int d = 0; d < RELEASE_WIDTH; d++) begin
      if (release_valid[d] && (release_tag[d] < PHYS_REGS))
        release_delta[release_tag[d]]++;
    end
    for (int r = 0; r < PHYS_REGS; r++)
      next_count[r] = int'(reference_count[r]) +
                      acquire_delta[r] - release_delta[r];
  end

  always_comb begin
    for (int r = 0; r < PHYS_REGS; r++) begin
      referenced_bitmap[r] = (reference_count[r] != '0);
      // Pulse when all same-cycle tracked references drain to zero.
      reclaim_bitmap[r] = !clear_all && (r != 0) &&
                          (reference_count[r] != '0) && (next_count[r] == 0);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reference_count <= '0;
      for (int r = 0; r < PHYS_REGS; r++) begin
        if (r < INIT_ARCH_REGS)
          reference_count[r] <= COUNT_W'(1);
      end
    end else if (clear_all) begin
      // clear_all is a global architectural reset operation: restore the
      // initial identity-map ownership references instead of making p1..p31
      // appear reclaimable. Callers must assert it only while RAT state is
      // reset to the architectural identity mapping.
      reference_count <= '0;
      for (int r = 0; r < PHYS_REGS; r++) begin
        if (r < INIT_ARCH_REGS)
          reference_count[r] <= COUNT_W'(1);
      end
    end else begin
      for (int r = 0; r < PHYS_REGS; r++) begin
        if ((next_count[r] >= 0) && (next_count[r] < (1 << COUNT_W)))
          reference_count[r] <= COUNT_W'(next_count[r]);
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && !clear_all) begin
      for (int r = 0; r < PHYS_REGS; r++) begin
        assert (next_count[r] >= 0)
          else $error("reference_tracker: reference-count underflow");
        assert (next_count[r] < (1 << COUNT_W))
          else $error("reference_tracker: reference-count overflow");
      end
      for (int a = 0; a < ACQUIRE_WIDTH; a++) begin
        if (acquire_valid[a])
          assert (acquire_tag[a] < PHYS_REGS)
            else $error("reference_tracker: acquire tag out of range");
      end
      for (int d = 0; d < RELEASE_WIDTH; d++) begin
        if (release_valid[d])
          assert (release_tag[d] < PHYS_REGS)
            else $error("reference_tracker: release tag out of range");
      end
    end
  end
  initial begin
    if (PHYS_REGS < 2) $error("PHYS_REGS must be at least 2");
    if (COUNT_W < 2) $error("COUNT_W must be at least 2");
  end
`endif
endmodule
