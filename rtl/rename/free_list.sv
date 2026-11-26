module free_list #(
  parameter int PHYS_REGS = 80,
  parameter int ARCH_REGS = 32,
  parameter int TAG_W = $clog2(PHYS_REGS),
  parameter int ALLOC_WIDTH = 2
) (
  input  logic clk,
  input  logic rst_n,
  input  logic flush,
  input  logic [PHYS_REGS-1:0] restore_free_bitmap,
  input  logic [PHYS_REGS-1:0] reclaim_bitmap,

  input  logic [ALLOC_WIDTH-1:0] alloc_req,
  output logic [ALLOC_WIDTH-1:0] alloc_valid,
  output logic [ALLOC_WIDTH-1:0][TAG_W-1:0] alloc_tag,
  input  logic [ALLOC_WIDTH-1:0] alloc_take,

  input  logic [ALLOC_WIDTH-1:0] free_valid,
  input  logic [ALLOC_WIDTH-1:0][TAG_W-1:0] free_tag,

  output logic [PHYS_REGS-1:0] free_bitmap,
  output logic [ALLOC_WIDTH-1:0][PHYS_REGS-1:0] free_bitmap_after_alloc
);
  logic [PHYS_REGS-1:0] free_q, free_d, alloc_work, snapshot_work;
  logic [ALLOC_WIDTH-1:0] free_accept;
  integer i, j;
  integer found_count;
  logic [TAG_W-1:0] selected [0:ALLOC_WIDTH-1];
  logic [PHYS_REGS-1:0] lane_snapshot [0:ALLOC_WIDTH-1];

  always_comb begin
    free_d = free_q;
    alloc_work = free_q;
    snapshot_work = free_q;
    alloc_valid = '0;
    alloc_tag = '0;
    found_count = 0;
    free_accept = '0;
    for (i = 0; i < ALLOC_WIDTH; i++) begin
      selected[i] = '0;
      lane_snapshot[i] = free_q;
      free_bitmap_after_alloc[i] = '0;
    end

    // Allocation is oldest-first. Initial architectural mappings are reserved
    // by the reset bitmap, but may be reclaimed after their replacement commits.
    // Physical register zero is the sole permanently reserved register.
    // Each lane sees the removals made by prior lanes.
    for (i = 0; i < ALLOC_WIDTH; i++) begin
      if (alloc_req[i]) begin
        for (j = 1; j < PHYS_REGS; j++) begin
          if (alloc_work[j] && !alloc_valid[i]) begin
            selected[i] = TAG_W'(j);
            alloc_work[j] = 1'b0;
            if (alloc_take[i])
              free_d[j] = 1'b0;
            alloc_valid[i] = 1'b1;
            alloc_tag[i] = TAG_W'(j);
            found_count = found_count + 1;
          end
        end
      end
      if (alloc_take[i] && alloc_valid[i])
        snapshot_work[selected[i]] = 1'b0;
      lane_snapshot[i] = snapshot_work;
    end

    // Accept a free only for a tag that was allocated before this cycle.
    // This prevents duplicate/stale frees and same-cycle allocate/free aliasing.
    // Accepted committed frees are visible in every branch snapshot.
    for (i = 0; i < ALLOC_WIDTH; i++) begin
      if (free_valid[i] && (free_tag[i] < PHYS_REGS) &&
          (free_tag[i] != '0) && !free_q[free_tag[i]]) begin
        free_accept[i] = 1'b1;
        for (j = 0; j < ALLOC_WIDTH; j++) begin
          if (alloc_take[j] && alloc_valid[j] &&
              (alloc_tag[j] == free_tag[i]))
            free_accept[i] = 1'b0;
        end
      end
      if (free_accept[i]) begin
        free_d[free_tag[i]] = 1'b1;
        for (j = 0; j < ALLOC_WIDTH; j++)
          lane_snapshot[j][free_tag[i]] = 1'b1;
      end
    end
    // Final-reference releases are reclaimed after allocation selection, so
    // a newly zero-reference tag is not reused until the following cycle.
    for (j = 1; j < PHYS_REGS; j++) begin
      if (reclaim_bitmap[j] && !free_q[j]) begin
        free_d[j] = 1'b1;
        for (i = 0; i < ALLOC_WIDTH; i++)
          lane_snapshot[i][j] = 1'b1;
      end
    end
    for (i = 0; i < ALLOC_WIDTH; i++)
      free_bitmap_after_alloc[i] = lane_snapshot[i];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      free_q <= {{ARCH_REGS{1'b0}}, {(PHYS_REGS-ARCH_REGS){1'b1}}};
    else if (flush)
      // p0 is permanently reserved. Other initial architectural mappings may
      // legitimately become free after their replacement commits.
      free_q <= (restore_free_bitmap | reclaim_bitmap) &
                {{(PHYS_REGS-1){1'b1}}, 1'b0};
    else
      free_q <= free_d;
  end

  assign free_bitmap = free_q;

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      for (int a = 0; a < ALLOC_WIDTH; a++) begin
        if (free_valid[a] && (free_tag[a] != '0) &&
            (free_tag[a] < PHYS_REGS))
          assert (!free_q[free_tag[a]])
            else $error("free_list: duplicate or stale physical-register free");
        for (int b = a + 1; b < ALLOC_WIDTH; b++) begin
          if (free_valid[a] && free_valid[b] &&
              (free_tag[a] == free_tag[b]))
            $error("free_list: duplicate free tag in one cycle");
        end
      end
    end
  end

  initial begin
    if (PHYS_REGS <= ARCH_REGS) $error("PHYS_REGS must exceed ARCH_REGS");
    if (ALLOC_WIDTH < 1) $error("ALLOC_WIDTH must be >= 1");
  end
`endif
endmodule
