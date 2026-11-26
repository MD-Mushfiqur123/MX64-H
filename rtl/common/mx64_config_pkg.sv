package mx64_config_pkg;
  parameter int XLEN = 64;
  parameter int VA_W = 48;
  // Must be set by the platform integration; this value is only a compile scaffold.
  parameter int PADDR_W = 40;
  parameter int ARCH_REGS = 32;
  parameter int PHYS_REGS = 80;
  parameter int ROB_DEPTH = 48;
  parameter int ISSUEQ_DEPTH = 16;
  parameter int LOADQ_DEPTH = 16;
  parameter int STOREQ_DEPTH = 16;
  parameter int DISPATCH_WIDTH = 2;
  parameter int RETIRE_WIDTH = 2;
  parameter int CACHE_LINE_BYTES = 64;

  typedef logic [XLEN-1:0] xlen_t;
  typedef logic [VA_W-1:0] vaddr_t;
  typedef logic [PADDR_W-1:0] paddr_t;
  typedef logic [4:0] arch_reg_t;
  typedef logic [$clog2(PHYS_REGS)-1:0] phys_reg_t;
  typedef logic [$clog2(ROB_DEPTH)-1:0] rob_idx_t;

  // Platform integration must override PADDR_W and validate all dependent widths.
endpackage
