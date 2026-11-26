// MX64-H Phase 34: physical-address LSU-to-L1D request/response bridge.
// The upstream LSU must perform translation, ordering, forwarding and replay
// decisions before presenting a request. This bridge handles cache handshake
// and architectural load-result extraction only.
module mx64_lsu_cache_bridge #(
  parameter int PADDR_W = 40,
  parameter int LINE_BYTES = 64,
  parameter int SETS = 16,
  parameter int DATA_W = 64,
  parameter int BYTE_LANES = DATA_W / 8
) (
  input  logic clk,
  input  logic rst_n,

  input  logic req_valid,
  output logic req_ready,
  input  logic [PADDR_W-1:0] req_paddr,
  input  logic req_write,
  input  logic [DATA_W-1:0] req_wdata,
  input  logic [BYTE_LANES-1:0] req_byte_enable,
  input  logic [1:0] req_size,       // 0=byte, 1=half, 2=word, 3=doubleword
  input  logic req_signed,          // ignored for stores

  output logic rsp_valid,
  input  logic rsp_ready,
  output logic [DATA_W-1:0] rsp_rdata,
  output logic rsp_error,

  output logic mem_req_valid,
  input  logic mem_req_ready,
  output logic mem_req_write,
  output logic [PADDR_W-1:0] mem_req_addr,
  output logic [LINE_BYTES*8-1:0] mem_req_wdata,
  output logic [LINE_BYTES-1:0] mem_req_wstrb,
  input  logic mem_rsp_valid,
  output logic mem_rsp_ready,
  input  logic [LINE_BYTES*8-1:0] mem_rsp_rdata,
  input  logic mem_rsp_error,

  input logic invalidate_all
);
  logic cache_req_ready;
  logic cache_rsp_valid;
  logic cache_rsp_ready;
  logic [DATA_W-1:0] cache_rsp_rdata;
  logic cache_rsp_error;
  logic [DATA_W-1:0] shifted_load;
  logic [DATA_W-1:0] formatted_load;
  logic [5:0] byte_shift;
  logic [2:0] req_offset_q;
  logic [1:0] req_size_q;
  logic req_signed_q, req_write_q;

  assign req_ready = cache_req_ready;
  assign rsp_valid = cache_rsp_valid;
  assign rsp_error = cache_rsp_error;
  assign cache_rsp_ready = rsp_ready;
  assign byte_shift = {req_offset_q, 3'b000};
  assign shifted_load = cache_rsp_rdata >> byte_shift;

  always_comb begin
    formatted_load = shifted_load;
    if (req_signed_q) begin
      case (req_size_q)
        2'd0: formatted_load = {{(DATA_W-8){shifted_load[7]}}, shifted_load[7:0]};
        2'd1: formatted_load = {{(DATA_W-16){shifted_load[15]}}, shifted_load[15:0]};
        2'd2: formatted_load = {{(DATA_W-32){shifted_load[31]}}, shifted_load[31:0]};
        default: formatted_load = shifted_load;
      endcase
    end else begin
      case (req_size_q)
        2'd0: formatted_load = {{(DATA_W-8){1'b0}}, shifted_load[7:0]};
        2'd1: formatted_load = {{(DATA_W-16){1'b0}}, shifted_load[15:0]};
        2'd2: formatted_load = {{(DATA_W-32){1'b0}}, shifted_load[31:0]};
        default: formatted_load = shifted_load;
      endcase
    end
    rsp_rdata = '0;
    if (!req_write_q) rsp_rdata = formatted_load;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_offset_q <= '0;
      req_size_q <= '0;
      req_signed_q <= 1'b0;
      req_write_q <= 1'b0;
    end else if (req_valid && req_ready) begin
      req_offset_q <= req_paddr[2:0];
      req_size_q <= req_size;
      req_signed_q <= req_signed;
      req_write_q <= req_write;
    end
  end

  cache_hierarchy #(
    .PADDR_W(PADDR_W), .LINE_BYTES(LINE_BYTES), .SETS(SETS), .DATA_W(DATA_W)
  ) u_l1d (
    .clk, .rst_n,
    .req_valid, .req_ready(cache_req_ready), .req_addr(req_paddr),
    .req_write, .req_wdata, .req_byte_enable,
    .rsp_valid(cache_rsp_valid), .rsp_ready(cache_rsp_ready),
    .rsp_rdata(cache_rsp_rdata), .rsp_error(cache_rsp_error),
    .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
    .mem_req_wdata, .mem_req_wstrb,
    .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_error,
    .invalidate_all
  );

`ifndef SYNTHESIS
  initial begin
    assert (DATA_W == 64) else $error("LSU cache bridge currently expects 64-bit data");
    assert (PADDR_W >= 16) else $error("Physical address width is too small");
  end
  always_ff @(posedge clk) if (rst_n) begin
    if (req_valid && req_ready) begin
      assert (req_byte_enable != '0) else $error("LSU cache bridge received empty byte mask");
      assert ((req_byte_enable & (req_byte_enable + BYTE_LANES'(1))) == '0)
        else $error("LSU cache bridge expects low-contiguous byte enables");
      assert ((req_paddr[2:0] + $countones(req_byte_enable)) <= BYTE_LANES)
        else $error("LSU cache bridge request crosses a 64-bit word");
      assert (req_size <= 3) else $error("LSU cache bridge received invalid access size");
    end
    if (rsp_valid && !rsp_ready)
      assert ($stable(rsp_rdata) && $stable(rsp_error))
        else $error("LSU cache bridge response changed under backpressure");
  end
`endif
endmodule
