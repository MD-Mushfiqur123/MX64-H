module mx64_instruction_decoder (
  input  logic [63:0] pc,
  input  logic [31:0] instruction,
  input  logic       valid_i,
  output mx64_pkg::decoded_uop_t uop_o
);
  import mx64_pkg::*;
  logic [5:0] major;
  logic [3:0] minor;
  logic [4:0] rd, rs1, rs2;
  logic [11:0] imm12;
  logic [63:0] simm12;
  logic legal;
  integer i;

  always_comb begin
    major = instruction[31:26];
    minor = instruction[15:12];
    rd = instruction[25:21];
    rs1 = instruction[20:16];
    rs2 = instruction[15:11];
    imm12 = instruction[11:0];
    simm12 = {{52{imm12[11]}}, imm12};
    uop_o = '0;
    uop_o.valid = valid_i;
    uop_o.pc = pc;
    uop_o.instruction = instruction;
    uop_o.rs1 = rs1;
    uop_o.rs2 = rs2;
    uop_o.rd = rd;
    uop_o.immediate = simm12;
    uop_o.alu_op = ALU_PASS;
    legal = 1'b1;

    if (valid_i) begin
      case (major)
        6'h00: begin
          case (instruction[5:0])
            6'd0: begin uop_o.writes_rd = 1'b0; end // NOP
            6'd1: begin uop_o.writes_rd = 1'b0; end // HALT
            6'd2: begin uop_o.exception = EXC_ECALL; uop_o.writes_rd = 1'b0; end
            6'd3: begin uop_o.exception = EXC_BREAKPOINT; uop_o.writes_rd = 1'b0; end
            6'd4: begin uop_o.writes_rd = 1'b0; end // MRET, handled by privileged backend
            default: legal = 1'b0;
          endcase
        end
        6'h01: begin
          uop_o.writes_rd = 1'b1;
          case (instruction[5:0])
            6'd0: uop_o.alu_op = ALU_ADD;
            6'd1: uop_o.alu_op = ALU_SUB;
            6'd2: uop_o.alu_op = ALU_AND;
            6'd3: uop_o.alu_op = ALU_OR;
            6'd4: uop_o.alu_op = ALU_XOR;
            6'd6: uop_o.alu_op = ALU_SLT;
            6'd7: uop_o.alu_op = ALU_SLTU;
            default: legal = 1'b0;
          endcase
        end
        6'h02: begin
          uop_o.writes_rd = 1'b1;
          case (instruction[5:0])
            6'd0: uop_o.alu_op = ALU_SLL;
            6'd1: uop_o.alu_op = ALU_SRL;
            6'd2: uop_o.alu_op = ALU_SRA;
            default: legal = 1'b0;
          endcase
        end
        6'h04: begin
          uop_o.writes_rd = 1'b1;
          uop_o.rs2 = 5'd0;
          case (minor)
            4'd0: uop_o.alu_op = ALU_ADD;
            4'd1: uop_o.alu_op = ALU_AND;
            4'd2: uop_o.alu_op = ALU_OR;
            4'd3: uop_o.alu_op = ALU_XOR;
            4'd4: uop_o.alu_op = ALU_SLT;
            4'd5: uop_o.alu_op = ALU_SLTU;
            default: legal = 1'b0;
          endcase
        end
        6'h05: begin
          uop_o.writes_rd = 1'b1;
          uop_o.rs2 = 5'd0;
          case (minor)
            4'd0: uop_o.alu_op = ALU_SLL;
            4'd1: uop_o.alu_op = ALU_SRL;
            4'd2: uop_o.alu_op = ALU_SRA;
            default: legal = 1'b0;
          endcase
        end
        6'h06: begin
          uop_o.writes_rd = 1'b1;
          uop_o.is_load = 1'b1;
          uop_o.rs2 = 5'd0;
          uop_o.alu_op = ALU_ADD;
          if (minor > 4'd6) legal = 1'b0;
        end
        6'h07: begin
          uop_o.rs2 = instruction[25:21];
          uop_o.is_store = 1'b1;
          uop_o.writes_rd = 1'b0;
          uop_o.alu_op = ALU_ADD;
          if (minor > 4'd3) legal = 1'b0;
        end
        6'h08: begin
          uop_o.rs2 = instruction[25:21];
          uop_o.is_branch = 1'b1;
          uop_o.writes_rd = 1'b0;
          if (minor > 4'd5) legal = 1'b0;
          uop_o.immediate = {{50{instruction[11]}}, instruction[11:0], 2'b00};
        end
        6'h09: begin
          uop_o.is_jump = 1'b1;
          uop_o.writes_rd = 1'b1;
          uop_o.rs1 = 5'd0;
          uop_o.rs2 = 5'd0;
          uop_o.immediate = {{36{instruction[25]}}, instruction[25:0], 2'b00};
        end
        6'h0A: begin
          uop_o.is_jump = 1'b1;
          uop_o.writes_rd = 1'b1;
          uop_o.rs2 = 5'd0;
          uop_o.alu_op = ALU_ADD;
        end
        6'h0B: begin
          uop_o.writes_rd = 1'b1;
          uop_o.rs1 = 5'd0;
          uop_o.rs2 = 5'd0;
          uop_o.immediate = {instruction[16:0], 47'b0};
          if (instruction[20:17] == 4'd1) uop_o.alu_op = ALU_ADD; // AUIPC consumes PC downstream
          else if (instruction[20:17] == 4'd0) uop_o.alu_op = ALU_PASS; // LUI
          else legal = 1'b0;
        end
        6'h0C: begin
          uop_o.writes_rd = 1'b0;
          if (instruction[5:0] > 6'd1) legal = 1'b0;
        end
        default: legal = 1'b0;
      endcase
      if (!legal) begin
        uop_o = '0;
        uop_o.valid = 1'b1;
        uop_o.pc = pc;
        uop_o.instruction = instruction;
        uop_o.exception = EXC_ILLEGAL;
        uop_o.exception_value = {32'b0, instruction};
      end
      if (uop_o.writes_rd && uop_o.rd == 5'd0)
        uop_o.writes_rd = 1'b0;
      if (pc[1:0] != 2'b00) begin
        uop_o.exception = EXC_INST_MISALIGNED;
        uop_o.exception_value = pc;
      end
    end
  end
endmodule
