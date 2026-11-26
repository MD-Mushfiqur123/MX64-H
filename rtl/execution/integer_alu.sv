module integer_alu (
  input  logic [63:0] a,
  input  logic [63:0] b,
  input  logic [4:0]  op,
  output logic [63:0] result,
  output logic        zero,
  output logic        signed_lt,
  output logic        unsigned_lt
);
  import mx64_pkg::*;

  always_comb begin
    result = 64'b0;
    unique case (alu_op_t'(op))
      ALU_ADD:  result = a + b;
      ALU_SUB:  result = a - b;
      ALU_AND:  result = a & b;
      ALU_OR:   result = a | b;
      ALU_XOR:  result = a ^ b;
      ALU_NOT:  result = ~a;
      ALU_SLL:  result = a << b[5:0];
      ALU_SRL:  result = a >> b[5:0];
      ALU_SRA:  result = $signed(a) >>> b[5:0];
      ALU_SLT:  result = {63'b0, ($signed(a) < $signed(b))};
      ALU_SLTU: result = {63'b0, (a < b)};
      ALU_PASS: result = a;
      default:  result = 64'b0;
    endcase
  end

  assign zero        = (result == 64'b0);
  assign signed_lt   = ($signed(a) < $signed(b));
  assign unsigned_lt = (a < b);
endmodule
