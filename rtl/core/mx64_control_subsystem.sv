// MX64-H Phase 18: integrated dispatch/backend/branch-recovery/trap control slice.
// Frontend decode, operand read ports, and branch execution remain explicit
// interfaces; this module does not claim to be a complete standalone CPU.
module mx64_control_subsystem #(
  parameter int PHYS_REGS = 80,
  parameter int IQ_DEPTH = 16,
  parameter int ROB_DEPTH = 48,
  parameter int WIDTH = 2,
  parameter int EXTERNAL_REF_WIDTH = 8
) (
  input logic clk,
  input logic rst_n,

  // Frontend boundary: decoded uops and already-read architectural operands.
  input logic [WIDTH-1:0] decoded_valid,
  output logic [WIDTH-1:0] decoded_ready,
  input mx64_pkg::decoded_uop_t decoded_uop [0:WIDTH-1],
  input logic [WIDTH-1:0] src1_ready,
  input logic [WIDTH-1:0] src2_ready,
  input logic [WIDTH-1:0][63:0] src1_value,
  input logic [WIDTH-1:0][63:0] src2_value,
  output logic [WIDTH-1:0][$clog2(PHYS_REGS)-1:0] source1_phys_tag,
  output logic [WIDTH-1:0][$clog2(PHYS_REGS)-1:0] source2_phys_tag,
  output logic [WIDTH-1:0] int_wb_valid,
  output logic [WIDTH-1:0][$clog2(PHYS_REGS)-1:0] int_wb_tag,
  output logic [WIDTH-1:0][63:0] int_wb_data,
  input logic branch_wb_valid,
  input logic [$clog2(PHYS_REGS)-1:0] branch_wb_tag,
  input logic [63:0] branch_wb_data,
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_acquire_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] external_ref_acquire_tag,
  input logic [EXTERNAL_REF_WIDTH-1:0] external_ref_release_valid,
  input logic [EXTERNAL_REF_WIDTH-1:0][$clog2(PHYS_REGS)-1:0] external_ref_release_tag,

  // Dedicated branch execution boundary.
  input logic [WIDTH-1:0] branch_dispatch_ready,
  output logic [WIDTH-1:0] branch_dispatch_valid,
  output mx64_pkg::issue_uop_t branch_dispatch_uop [0:WIDTH-1],
  input logic [WIDTH-1:0] memory_dispatch_ready,
  output logic [WIDTH-1:0] memory_dispatch_valid,
  output mx64_pkg::issue_uop_t memory_dispatch_uop [0:WIDTH-1],
  input logic memory_complete_valid,
  input logic [mx64_pkg::ROB_TAG_W-1:0] memory_complete_tag,
  input logic [63:0] memory_complete_value,
  input logic memory_complete_exception,
  input logic [3:0] memory_complete_exception_code,
  input logic [63:0] memory_complete_exception_value,
  input logic branch_resolve_valid,
  input logic [mx64_pkg::ROB_TAG_W-1:0] branch_resolve_tag,
  input logic branch_mispredict,
  input logic [63:0] branch_actual_target,
  input logic [63:0] branch_result_value,
  output logic branch_resolve_ready,

  // Trap-vector/privilege inputs are supplied by the platform CSR boundary.
  input logic [1:0] current_privilege,
  input logic [63:0] trap_vector,
  output logic trap_valid,
  output logic [63:0] trap_pc,
  output logic [63:0] trap_cause,
  output logic [63:0] trap_value,
  output logic trap_redirect_valid,
  output logic [63:0] trap_redirect_pc,

  // External retirement gate (e.g. committed-store request acceptance).
  input logic [WIDTH-1:0] retire_gate_ready,

  // Retired architectural event stream.
  output logic [WIDTH-1:0] retire_valid,
  output logic [WIDTH-1:0][mx64_pkg::ROB_TAG_W-1:0] retire_tag,
  output logic [WIDTH-1:0][63:0] retire_pc,
  output logic [WIDTH-1:0][4:0] retire_rd,
  output logic [WIDTH-1:0][6:0] retire_kind,
  output logic [WIDTH-1:0][63:0] retire_value,
  output logic [WIDTH-1:0] retire_exception,
  output logic [WIDTH-1:0][3:0] retire_exception_code,
  output logic [WIDTH-1:0][63:0] retire_exception_value,
  output logic [1:0] retired_count,

  output logic rob_full,
  output logic rob_empty,
  output logic [$clog2(ROB_DEPTH+1)-1:0] rob_occupancy,
  output logic [$clog2(IQ_DEPTH+1)-1:0] issue_occupancy,
  output logic [PHYS_REGS-1:0] physical_ref_bitmap,
  output logic [PHYS_REGS-1:0] physical_reclaim_bitmap,
  output logic [PHYS_REGS-1:0][7:0] physical_ref_count,
  output logic [31:0] recovery_seq_debug,
  output logic [mx64_pkg::ROB_TAG_W-1:0] recovery_tag_debug
);
  import mx64_pkg::*;

  logic [31:0] recovery_seq;
  logic [ROB_TAG_W-1:0] recovery_tag;
  logic [63:0] recovery_pc;
  logic recovery_valid;
  logic branch_resolve_tag_found, recovery_rob_tag_found;
  logic [WIDTH-1:0] retire_ready;
  logic [31:0][$clog2(PHYS_REGS)-1:0] speculative_rat, committed_rat;
  logic [PHYS_REGS-1:0] speculative_free, committed_free;

  // Trap flush restores speculative rename/free-list state from committed maps.
  mx64_dispatch_controller #(
    .WIDTH(WIDTH), .ARCH_REGS(32), .PHYS_REGS(PHYS_REGS),
    .PHYS_W($clog2(PHYS_REGS)), .IQ_DEPTH(IQ_DEPTH), .ROB_DEPTH(ROB_DEPTH),
    .EXTERNAL_REF_WIDTH(EXTERNAL_REF_WIDTH)
  ) u_dispatch_backend (
    .clk, .rst_n, .flush(trap_valid),
    .restore_rat(committed_rat),
    .restore_free_bitmap(committed_free),
    .decoded_valid, .decoded_ready, .decoded_uop,
    .src1_ready, .src2_ready, .src1_value, .src2_value,
    .source1_phys_tag, .source2_phys_tag, .int_wb_valid, .int_wb_tag, .int_wb_data,
    .branch_wb_valid, .branch_wb_tag, .branch_wb_data,
    .external_ref_acquire_valid, .external_ref_acquire_tag,
    .external_ref_release_valid, .external_ref_release_tag,
    .branch_dispatch_ready, .branch_dispatch_valid, .branch_dispatch_uop,
    .memory_dispatch_ready, .memory_dispatch_valid, .memory_dispatch_uop,
    .memory_complete_valid, .memory_complete_tag, .memory_complete_value,
    .memory_complete_exception, .memory_complete_exception_code,
    .memory_complete_exception_value,
    .branch_resolve_valid, .branch_resolve_tag, .branch_mispredict,
    .branch_actual_target, .branch_result_value, .branch_resolve_ready,
    .recovery_valid, .recovery_branch_tag(recovery_tag),
    .recovery_seq, .recovery_pc,
    .branch_resolve_tag_found, .recovery_rob_tag_found,
    .retire_valid, .retire_ready,
    .retire_tag, .retire_pc, .retire_rd, .retire_kind, .retire_value,
    .retire_exception, .retire_exception_code, .retire_exception_value,
    .rob_full, .rob_empty, .rob_occupancy, .issue_occupancy,
    .rat_debug(speculative_rat), .committed_rat_debug(committed_rat),
    .free_debug(speculative_free), .committed_free_bitmap_debug(committed_free),
    .physical_ref_bitmap, .physical_reclaim_bitmap, .physical_ref_count
  );

  mx64_trap_controller #(.WIDTH(WIDTH)) u_trap_controller (
    .clk, .rst_n,
    .retire_valid, .retire_exception, .retire_pc,
    .retire_exception_code, .retire_exception_value,
    .normal_retire_ready(retire_gate_ready),
    .current_privilege, .trap_vector,
    .rob_retire_ready(retire_ready),
    .trap_valid, .trap_pc, .trap_cause, .trap_value,
    .trap_is_interrupt(), .flush_speculative(),
    .redirect_valid(trap_redirect_valid), .redirect_pc(trap_redirect_pc),
    .retired_count
  );

  assign recovery_seq_debug = recovery_seq;
  assign recovery_tag_debug = recovery_tag;
endmodule
