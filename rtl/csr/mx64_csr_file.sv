module mx64_csr_file #(
  parameter int XLEN = 64,
  parameter int VA_W = 48
) (
  input  logic              clk,
  input  logic              rst_n,

  input  logic              csr_read_en,
  input  logic [11:0]       csr_read_addr,
  output logic [XLEN-1:0]   csr_read_data,
  output logic             csr_read_legal,

  input  logic              csr_write_en,
  input  logic [11:0]       csr_write_addr,
  input  logic [XLEN-1:0]   csr_write_data,
  output logic             csr_write_legal,

  input  logic [1:0]        current_privilege,
  output logic [1:0]        privilege_mode,

  input  logic              trap_valid,
  input  logic [XLEN-1:0]   trap_pc,
  input  logic [XLEN-1:0]   trap_cause,
  input  logic [XLEN-1:0]   trap_value,
  input  logic              trap_is_interrupt,
  output logic [VA_W-1:0]   trap_vector,

  input  logic              mret,
  output logic [VA_W-1:0]   mret_pc,

  input  logic [1:0]        retired_count
);
  localparam logic [11:0] CSR_MSTATUS = 12'h300;
  localparam logic [11:0] CSR_MIE     = 12'h304;
  localparam logic [11:0] CSR_MTVEC   = 12'h305;
  localparam logic [11:0] CSR_MSCR   = 12'h340;
  localparam logic [11:0] CSR_MEPC    = 12'h341;
  localparam logic [11:0] CSR_MCAUSE  = 12'h342;
  localparam logic [11:0] CSR_MTVAL   = 12'h343;
  localparam logic [11:0] CSR_MIP     = 12'h344;
  localparam logic [11:0] CSR_CYCLE   = 12'hC00;
  localparam logic [11:0] CSR_INSTRET = 12'hC02;

  logic [XLEN-1:0] mstatus, mie, mtvec, mscratch;
  logic [XLEN-1:0] mepc, mcause, mtval, mip;
  logic [XLEN-1:0] cycle_counter, instret_counter;

  logic [XLEN-1:0] read_mux;
  logic read_legal_int, write_legal_int;
  logic [XLEN-1:0] mtvec_base;

  assign mtvec_base = {mtvec[XLEN-1:2], 2'b00};
  assign trap_vector = (trap_is_interrupt && mtvec[1:0] == 2'b01)
                     ? mtvec_base[VA_W-1:0] +
                       (trap_cause[VA_W-1:0] << 2)
                     : mtvec_base[VA_W-1:0];
  assign mret_pc = mepc[VA_W-1:0];
  assign privilege_mode = current_privilege;

  always_comb begin
    read_mux = '0;
    read_legal_int = 1'b1;
    case (csr_read_addr)
      CSR_MSTATUS: read_mux = mstatus;
      CSR_MIE:     read_mux = mie;
      CSR_MTVEC:   read_mux = mtvec;
      CSR_MSCR:    read_mux = mscratch;
      CSR_MEPC:    read_mux = mepc;
      CSR_MCAUSE:  read_mux = mcause;
      CSR_MTVAL:   read_mux = mtval;
      CSR_MIP:     read_mux = mip;
      CSR_CYCLE:   read_mux = cycle_counter;
      CSR_INSTRET: read_mux = instret_counter;
      default: begin read_mux = '0; read_legal_int = 1'b0; end
    endcase

    // This initial privileged baseline exposes machine CSRs only from M-mode.
    if (current_privilege != 2'b11)
      read_legal_int = 1'b0;

    write_legal_int = 1'b0;
    case (csr_write_addr)
      CSR_MSTATUS, CSR_MIE, CSR_MTVEC, CSR_MSCR,
      CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP:
        write_legal_int = (current_privilege == 2'b11);
      default: write_legal_int = 1'b0;
    endcase
  end

  assign csr_read_data = read_mux;
  assign csr_read_legal = !csr_read_en || read_legal_int;
  assign csr_write_legal = !csr_write_en || write_legal_int;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus        <= '0;
      mie            <= '0;
      mtvec          <= '0;
      mscratch       <= '0;
      mepc           <= '0;
      mcause         <= '0;
      mtval          <= '0;
      mip            <= '0;
      cycle_counter  <= '0;
      instret_counter<= '0;
    end else begin
      cycle_counter <= cycle_counter + {{(XLEN-1){1'b0}}, 1'b1};
      if (retired_count != 2'd0)
        instret_counter <= instret_counter + XLEN'(retired_count);

      if (csr_write_en && write_legal_int) begin
        case (csr_write_addr)
          CSR_MSTATUS: mstatus  <= csr_write_data;
          CSR_MIE:     mie      <= csr_write_data;
          CSR_MTVEC:   mtvec    <= csr_write_data;
          CSR_MSCR:    mscratch <= csr_write_data;
          CSR_MEPC:    mepc     <= {csr_write_data[XLEN-1:2], 2'b00};
          CSR_MCAUSE:  mcause   <= csr_write_data;
          CSR_MTVAL:   mtval    <= csr_write_data;
          CSR_MIP:     mip      <= csr_write_data;
          default: ;
        endcase
      end

      // Trap has priority over software CSR writes to trap-state registers.
      if (trap_valid) begin
        mepc <= {trap_pc[XLEN-1:2], 2'b00};
        mcause <= {trap_is_interrupt, trap_cause[XLEN-2:0]};
        mtval <= trap_value;
        mstatus[7] <= mstatus[3]; // MPIE <- MIE
        mstatus[3] <= 1'b0;        // MIE <- 0
        mstatus[12:11] <= current_privilege;
      end else if (mret) begin
        mstatus[3] <= mstatus[7]; // MIE <- MPIE
        mstatus[7] <= 1'b1;       // MPIE <- 1
        mstatus[12:11] <= 2'b00;  // return to U-mode baseline
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (XLEN != 64)
      $error("mx64_csr_file currently supports XLEN=64 only");
    if (VA_W > XLEN)
      $error("VA_W must not exceed XLEN");
  end
`endif
endmodule
