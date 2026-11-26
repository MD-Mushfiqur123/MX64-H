module physical_regfile #(
  parameter int DEPTH = 80,
  parameter int ARCH_REGS = 32,
  parameter int DATA_W = 64,
  parameter int TAG_W = $clog2(DEPTH),
  parameter int READ_PORTS = 4,
  parameter int WRITE_PORTS = 2
) (
  input  logic clk,
  input  logic rst_n,

  input  logic [READ_PORTS-1:0][TAG_W-1:0] raddr,
  output logic [READ_PORTS-1:0][DATA_W-1:0] rdata,
  output logic [READ_PORTS-1:0] rvalid,

  input  logic [WRITE_PORTS-1:0] wen,
  input  logic [WRITE_PORTS-1:0][TAG_W-1:0] waddr,
  input  logic [WRITE_PORTS-1:0][DATA_W-1:0] wdata
);
  logic [DEPTH-1:0][DATA_W-1:0] mem;
  logic [DEPTH-1:0] valid_q;
  integer i, p;

  // Combinational read ports. Same-cycle write-to-read forwarding is explicit.
  always_comb begin
    for (int r = 0; r < READ_PORTS; r++) begin
      rdata[r] = '0;
      rvalid[r] = 1'b0;
      if (raddr[r] < DEPTH) begin
        rdata[r] = mem[raddr[r]];
        rvalid[r] = valid_q[raddr[r]];
        // Match sequential write priority: port 0 wins a same-address
        // collision. Iterate downward so port 0 is assigned last.
        for (int w = WRITE_PORTS-1; w >= 0; w--) begin
          if (wen[w] && (waddr[w] == raddr[r])) begin
            rdata[r] = wdata[w];
            rvalid[r] = 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      for (i = 0; i < DEPTH; i++) begin
        mem[i] <= '0;
        if (i < ARCH_REGS) valid_q[i] <= 1'b1;
      end
    end else begin
      // Port 0 has priority if both write ports target the same entry.
      for (p = WRITE_PORTS-1; p >= 0; p--) begin
        if (wen[p] && (waddr[p] < DEPTH)) begin
          mem[waddr[p]] <= wdata[p];
          valid_q[waddr[p]] <= 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  // Simultaneous writes to one physical tag are a producer-side bug. The
  // defined port-0 priority keeps behavior deterministic while flagging it.
  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int a = 0; a < WRITE_PORTS; a++) begin
        for (int b = a + 1; b < WRITE_PORTS; b++) begin
          if (wen[a] && wen[b] && (waddr[a] == waddr[b]))
            $error("physical_regfile: simultaneous write-port destination collision");
        end
      end
    end
  end

  initial begin
    if (DEPTH < 2) $error("physical_regfile DEPTH must be >= 2");
    if (ARCH_REGS > DEPTH) $error("physical_regfile ARCH_REGS cannot exceed DEPTH");
    if (READ_PORTS < 1 || WRITE_PORTS < 1)
      $error("physical_regfile requires at least one read and write port");
  end
`endif
endmodule
