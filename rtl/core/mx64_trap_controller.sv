// MX64-H synchronous precise-exception controller.
// A fault is taken only when it reaches ROB lane 0. A fault in lane 1 is
// deliberately held while the older lane 0 instruction retires first.
// Interrupt arbitration and MRET privilege-state restoration are separate
// integration decisions and are not implemented in this block.
module mx64_trap_controller #(
  parameter int WIDTH = 2
) (
  input logic clk,
  input logic rst_n,

  input logic [WIDTH-1:0] retire_valid,
  input logic [WIDTH-1:0] retire_exception,
  input logic [WIDTH-1:0][63:0] retire_pc,
  input logic [WIDTH-1:0][3:0] retire_exception_code,
  input logic [WIDTH-1:0][63:0] retire_exception_value,
  input logic [WIDTH-1:0] normal_retire_ready,

  input logic [1:0] current_privilege,
  input logic [63:0] trap_vector,

  output logic [WIDTH-1:0] rob_retire_ready,
  output logic trap_valid,
  output logic [63:0] trap_pc,
  output logic [63:0] trap_cause,
  output logic [63:0] trap_value,
  output logic trap_is_interrupt,
  output logic flush_speculative,
  output logic redirect_valid,
  output logic [63:0] redirect_pc,
  output logic [1:0] retired_count
);
  import mx64_pkg::*;

  logic head_exception;
  logic [63:0] mapped_cause;

  always_comb begin
    rob_retire_ready = normal_retire_ready;
    head_exception = retire_valid[0] && retire_exception[0];
    mapped_cause = mx64_exception_cause(exception_t'(retire_exception_code[0]),
                                        current_privilege);

    // The ROB already serializes retirement behind lane 0. This controller
    // additionally prevents a lane-1 fault from being consumed beside an
    // older normal lane-0 instruction.
    if (head_exception) begin
      // Unknown exception encodings stall at the ROB head; never silently
      // consume a fault for which this profile has no architectural cause.
      rob_retire_ready[0] = (mapped_cause != 64'hffff_ffff_ffff_ffff);
      if (WIDTH > 1)
        rob_retire_ready[1] = 1'b0;
    end else if (WIDTH > 1 && retire_valid[1] && retire_exception[1]) begin
      rob_retire_ready[1] = 1'b0;
    end

    trap_valid = head_exception && (mapped_cause != 64'hffff_ffff_ffff_ffff);
    trap_pc = retire_pc[0];
    trap_cause = mapped_cause;
    trap_value = retire_exception_value[0];
    trap_is_interrupt = 1'b0;
    flush_speculative = trap_valid;
    redirect_valid = trap_valid;
    redirect_pc = trap_vector;

    retired_count = '0;
    for (int lane = 0; lane < WIDTH; lane++) begin
      if (retire_valid[lane] && rob_retire_ready[lane] && !retire_exception[lane])
        retired_count = retired_count + 2'd1;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (WIDTH != 2)
      $error("MX64 trap controller currently supports the two-wide retirement profile");
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (trap_valid) begin
        assert (retire_valid[0] && retire_exception[0] && rob_retire_ready[0])
          else $error("Trap must be accepted only for the faulting ROB head");
        if (WIDTH > 1)
          assert (!rob_retire_ready[1])
            else $error("Younger instruction may not retire with a head trap");
      end
      if (WIDTH > 1 && retire_valid[1] && retire_exception[1] && !head_exception)
        assert (!rob_retire_ready[1])
          else $error("Lane-1 exception must wait until it becomes the ROB head");
    end
  end
`endif
endmodule
