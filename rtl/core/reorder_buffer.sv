// Retired legacy placeholder. The implementation lives in
// rtl/scheduler/reorder_buffer.sv. This module has a distinct name so
// glob-based source lists cannot accidentally define reorder_buffer twice.
module mx64_rob_placeholder #(
  parameter int DEPTH = 48,
  parameter int TAG_W = $clog2(DEPTH)
) (
  input logic clk,
  input logic rst_n,
  input logic flush
);
  // Intentionally empty compatibility placeholder. Do not instantiate.
endmodule
