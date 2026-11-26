module mx64_fetch_unit #(
  parameter int VA_W = 48
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [VA_W-1:0] reset_pc,
  output logic mem_req_valid,
  input  logic mem_req_ready,
  output logic [VA_W-1:0] mem_req_addr,
  input  logic mem_resp_valid,
  input  logic [31:0] mem_resp_data,
  input  logic mem_resp_fault,
  input  logic [VA_W-1:0] mem_resp_fault_addr,
  output logic out_valid,
  input  logic out_ready,
  output logic [VA_W-1:0] out_pc,
  output logic [31:0] out_instruction,
  output logic out_access_fault,
  output logic [VA_W-1:0] out_fault_addr,
  input  logic redirect_valid,
  input  logic [VA_W-1:0] redirect_pc,
  input  logic predictor_valid,
  input  logic predictor_taken,
  input  logic [VA_W-1:0] predictor_target
);
  logic [VA_W-1:0] pc_q, outstanding_pc_q, buffer_pc_q;
  logic outstanding_q, discard_response_q, buffer_valid_q;
  logic [31:0] buffer_instruction_q;
  logic buffer_fault_q;
  logic [VA_W-1:0] buffer_fault_addr_q;
  logic req_fire, resp_fire, out_fire;

  assign mem_req_valid = rst_n && !outstanding_q && !buffer_valid_q && !redirect_valid;
  assign mem_req_addr = pc_q;
  assign req_fire = mem_req_valid && mem_req_ready;
  assign resp_fire = mem_resp_valid && outstanding_q;
  assign out_valid = buffer_valid_q;
  assign out_pc = buffer_pc_q;
  assign out_instruction = buffer_instruction_q;
  assign out_access_fault = buffer_fault_q;
  assign out_fault_addr = buffer_fault_addr_q;
  assign out_fire = out_valid && out_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= reset_pc;
      outstanding_pc_q <= '0;
      outstanding_q <= 1'b0;
      discard_response_q <= 1'b0;
      buffer_valid_q <= 1'b0;
      buffer_pc_q <= '0;
      buffer_instruction_q <= '0;
      buffer_fault_q <= 1'b0;
      buffer_fault_addr_q <= '0;
    end else begin
      if (redirect_valid) begin
        pc_q <= redirect_pc;
        if (resp_fire) begin
          outstanding_q <= 1'b0;
          discard_response_q <= 1'b0;
        end else if (outstanding_q) begin
          discard_response_q <= 1'b1;
        end
        buffer_valid_q <= 1'b0;
      end else begin
        if (req_fire) begin
          outstanding_q <= 1'b1;
          outstanding_pc_q <= pc_q;
        end
        if (resp_fire) begin
          outstanding_q <= 1'b0;
          if (discard_response_q) begin
            discard_response_q <= 1'b0;
          end else begin
            buffer_valid_q <= 1'b1;
            buffer_pc_q <= outstanding_pc_q;
            buffer_instruction_q <= mem_resp_data;
            buffer_fault_q <= mem_resp_fault;
            buffer_fault_addr_q <= mem_resp_fault_addr;
            if (predictor_valid && predictor_taken)
              pc_q <= predictor_target;
            else
              pc_q <= outstanding_pc_q + VA_W'(4);
          end
        end
        if (out_fire)
          buffer_valid_q <= 1'b0;
      end
    end
  end
endmodule
