module mx64_branch_predictor #(
  parameter int VA_W = 48,
  parameter int ENTRIES = 64,
  parameter int INDEX_W = $clog2(ENTRIES)
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic [VA_W-1:0]  fetch_pc,
  output logic             predict_valid,
  output logic             predict_taken,
  output logic [VA_W-1:0]  predict_target,
  input  logic             resolve_valid,
  input  logic [VA_W-1:0]  resolve_pc,
  input  logic             resolve_taken,
  input  logic [VA_W-1:0]  resolve_target,
  input  logic             flush
);
  localparam int TAG_W = VA_W - INDEX_W - 2;

  logic [1:0]              direction [0:ENTRIES-1];
  logic                    btb_valid [0:ENTRIES-1];
  logic [TAG_W-1:0]        btb_tag [0:ENTRIES-1];
  logic [VA_W-1:0]         btb_target [0:ENTRIES-1];

  logic [INDEX_W-1:0]      fetch_index;
  logic [INDEX_W-1:0]      resolve_index;
  logic [TAG_W-1:0]        fetch_tag;
  integer i;

  assign fetch_index = fetch_pc[INDEX_W+1:2];
  assign resolve_index = resolve_pc[INDEX_W+1:2];
  assign fetch_tag = fetch_pc[VA_W-1:INDEX_W+2];

  always_comb begin
    predict_valid  = btb_valid[fetch_index] &&
                     (btb_tag[fetch_index] == fetch_tag);
    predict_taken  = predict_valid && direction[fetch_index][1];
    predict_target = predict_valid ? btb_target[fetch_index] : '0;
  end

  // Two-bit saturating direction counters; BTB is direct-mapped and tagged.
  // Training occurs only when the resolving branch reaches this interface.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < ENTRIES; i = i + 1) begin
        direction[i]   <= 2'b01; // weakly not taken
        btb_valid[i]   <= 1'b0;
        btb_tag[i]     <= '0;
        btb_target[i]  <= '0;
      end
    end else if (flush) begin
      // A pipeline flush does not erase learned predictor state.
    end else if (resolve_valid) begin
      btb_valid[resolve_index]  <= 1'b1;
      btb_tag[resolve_index]    <= resolve_pc[VA_W-1:INDEX_W+2];
      btb_target[resolve_index] <= resolve_target;

      if (resolve_taken) begin
        if (direction[resolve_index] != 2'b11)
          direction[resolve_index] <= direction[resolve_index] + 2'b01;
      end else begin
        if (direction[resolve_index] != 2'b00)
          direction[resolve_index] <= direction[resolve_index] - 2'b01;
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (ENTRIES < 2 || (ENTRIES & (ENTRIES-1)) != 0)
      $error("mx64_branch_predictor ENTRIES must be a power of two >= 2");
    if (VA_W <= INDEX_W + 2)
      $error("mx64_branch_predictor VA_W is too small for the selected table");
  end
`endif
endmodule
