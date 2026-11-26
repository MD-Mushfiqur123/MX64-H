module mx64_frontend #(
  parameter int VA_W = 48,
  parameter int BTB_ENTRIES = 64
) (
  input logic clk,
  input logic rst_n,
  input logic [VA_W-1:0] reset_pc,
  output logic mem_req_valid,
  input logic mem_req_ready,
  output logic [VA_W-1:0] mem_req_addr,
  input logic mem_resp_valid,
  input logic [31:0] mem_resp_data,
  input logic mem_resp_fault,
  input logic [VA_W-1:0] mem_resp_fault_addr,
  output logic decoded_valid,
  input logic decoded_ready,
  output mx64_pkg::decoded_uop_t decoded_uop,
  input logic redirect_valid,
  input logic [VA_W-1:0] redirect_pc,
  input logic branch_resolve_valid,
  input logic [VA_W-1:0] branch_resolve_pc,
  input logic branch_resolve_taken,
  input logic [VA_W-1:0] branch_resolve_target
);
  logic fetch_valid, fetch_ready;
  logic [VA_W-1:0] fetch_pc, fetch_fault_addr;
  logic [31:0] fetch_instruction;
  logic fetch_access_fault;
  logic pred_valid, pred_taken;
  logic [VA_W-1:0] pred_target;
  logic [VA_W-1:0] predictor_pc;
  mx64_pkg::decoded_uop_t decoded_raw;

  assign predictor_pc = mem_req_addr;
  mx64_fetch_unit #(.VA_W(VA_W)) u_fetch (
    .clk, .rst_n, .reset_pc, .mem_req_valid, .mem_req_ready, .mem_req_addr,
    .mem_resp_valid, .mem_resp_data, .mem_resp_fault, .mem_resp_fault_addr,
    .out_valid(fetch_valid), .out_ready(fetch_ready), .out_pc(fetch_pc),
    .out_instruction(fetch_instruction), .out_access_fault(fetch_access_fault),
    .out_fault_addr(fetch_fault_addr),
    .redirect_valid, .redirect_pc,
    .predictor_valid(pred_valid), .predictor_taken(pred_taken),
    .predictor_target(pred_target)
  );

  mx64_branch_predictor #(.VA_W(VA_W), .ENTRIES(BTB_ENTRIES)) u_predictor (
    .clk, .rst_n, .fetch_pc(predictor_pc),
    .predict_valid(pred_valid), .predict_taken(pred_taken), .predict_target(pred_target),
    .resolve_valid(branch_resolve_valid), .resolve_pc(branch_resolve_pc),
    .resolve_taken(branch_resolve_taken), .resolve_target(branch_resolve_target),
    .flush(redirect_valid)
  );

  mx64_instruction_decoder u_decode (
    .pc(fetch_pc), .instruction(fetch_instruction), .valid_i(fetch_valid),
    .uop_o(decoded_raw)
  );

  always_comb begin
    decoded_uop = decoded_raw;
    if (fetch_access_fault && fetch_valid) begin
      decoded_uop = '0;
      decoded_uop.valid = 1'b1;
      decoded_uop.pc = fetch_pc;
      decoded_uop.instruction = fetch_instruction;
      decoded_uop.exception = mx64_pkg::EXC_INST_ACCESS_FAULT;
      decoded_uop.exception_value = fetch_fault_addr;
    end
  end
  assign decoded_valid = fetch_valid;
  assign fetch_ready = decoded_ready;
endmodule
