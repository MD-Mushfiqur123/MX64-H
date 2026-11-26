package mx64_pkg;
  parameter int ROB_INDEX_W = 6;
  parameter int ROB_EPOCH_W = 16;
  parameter int ROB_TAG_W = ROB_INDEX_W + ROB_EPOCH_W;
  typedef enum logic [4:0] {
    ALU_ADD=5'd0, ALU_SUB=5'd1, ALU_AND=5'd2, ALU_OR=5'd3,
    ALU_XOR=5'd4, ALU_NOT=5'd5, ALU_SLL=5'd6, ALU_SRL=5'd7,
    ALU_SRA=5'd8, ALU_SLT=5'd9, ALU_SLTU=5'd10, ALU_PASS=5'd11
  } alu_op_t;
  typedef enum logic [3:0] {
    EXC_NONE=4'd0, EXC_ILLEGAL=4'd1, EXC_BREAKPOINT=4'd2,
    EXC_ECALL=4'd3, EXC_LOAD_FAULT=4'd4, EXC_STORE_FAULT=4'd5,
    EXC_INST_MISALIGNED=4'd6, EXC_INST_ACCESS_FAULT=4'd7,
    EXC_LOAD_MISALIGNED=4'd8, EXC_STORE_MISALIGNED=4'd9,
    EXC_INST_PAGE_FAULT=4'd10, EXC_LOAD_PAGE_FAULT=4'd11,
    EXC_STORE_PAGE_FAULT=4'd12
  } exception_t;
  function automatic logic [63:0] mx64_exception_cause(input exception_t exc, input logic [1:0] privilege);
    case (exc)
      EXC_INST_MISALIGNED: mx64_exception_cause=64'd0;
      EXC_INST_ACCESS_FAULT: mx64_exception_cause=64'd1;
      EXC_ILLEGAL: mx64_exception_cause=64'd2;
      EXC_BREAKPOINT: mx64_exception_cause=64'd3;
      EXC_LOAD_MISALIGNED: mx64_exception_cause=64'd4;
      EXC_LOAD_FAULT: mx64_exception_cause=64'd5;
      EXC_STORE_MISALIGNED: mx64_exception_cause=64'd6;
      EXC_STORE_FAULT: mx64_exception_cause=64'd7;
      EXC_ECALL: begin
        if (privilege==2'b11) mx64_exception_cause=64'd11;
        else if (privilege==2'b00) mx64_exception_cause=64'd8;
        else mx64_exception_cause=64'hffff_ffff_ffff_ffff;
      end
      EXC_INST_PAGE_FAULT: mx64_exception_cause=64'd12;
      EXC_LOAD_PAGE_FAULT: mx64_exception_cause=64'd13;
      EXC_STORE_PAGE_FAULT: mx64_exception_cause=64'd15;
      default: mx64_exception_cause=64'hffff_ffff_ffff_ffff;
    endcase
  endfunction
  typedef struct packed {
    logic valid; logic [63:0] pc; logic [31:0] instruction;
    logic [4:0] rs1; logic [4:0] rs2; logic [4:0] rd;
    logic [63:0] immediate; alu_op_t alu_op; logic writes_rd;
    logic is_load; logic is_store; logic is_branch; logic is_jump;
    exception_t exception; logic [63:0] exception_value;
  } decoded_uop_t;
  typedef struct packed {
    logic valid; logic [63:0] pc; logic [31:0] instruction;
    logic [63:0] immediate; alu_op_t alu_op;
    logic [ROB_TAG_W-1:0] rob_tag; logic [31:0] seq_num;
    logic [6:0] dst_tag; logic writes_dst;
    logic [6:0] src1_tag; logic [6:0] src2_tag;
    logic src1_ready; logic src2_ready;
    logic [63:0] src1_value; logic [63:0] src2_value;
    logic is_load; logic is_store; logic is_branch; logic is_jump;
  } issue_uop_t;
endpackage
