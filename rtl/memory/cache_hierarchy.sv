// MX64-H Phase 33: blocking, direct-mapped, write-back L1 data cache.
// This is a synthesizable RTL cache controller model using flop arrays. SRAM
// macro substitution, L1I, L2 and coherence remain platform integration work.
module cache_hierarchy #(
  parameter int PADDR_W = 40,
  parameter int LINE_BYTES = 64,
  parameter int SETS = 16,
  parameter int DATA_W = 64,
  parameter int INDEX_W = $clog2(SETS),
  parameter int OFFSET_W = $clog2(LINE_BYTES),
  parameter int WORDS_PER_LINE = LINE_BYTES / (DATA_W / 8),
  parameter int TAG_W = PADDR_W - INDEX_W - OFFSET_W
) (
  input logic clk,
  input logic rst_n,
  input logic req_valid,
  output logic req_ready,
  input logic [PADDR_W-1:0] req_addr,
  input logic req_write,
  input logic [DATA_W-1:0] req_wdata,
  input logic [DATA_W/8-1:0] req_byte_enable,
  output logic rsp_valid,
  input logic rsp_ready,
  output logic [DATA_W-1:0] rsp_rdata,
  output logic rsp_error,

  output logic mem_req_valid,
  input logic mem_req_ready,
  output logic mem_req_write,
  output logic [PADDR_W-1:0] mem_req_addr,
  output logic [LINE_BYTES*8-1:0] mem_req_wdata,
  output logic [LINE_BYTES-1:0] mem_req_wstrb,
  input logic mem_rsp_valid,
  output logic mem_rsp_ready,
  input logic [LINE_BYTES*8-1:0] mem_rsp_rdata,
  input logic mem_rsp_error,

  input logic invalidate_all
);
  typedef enum logic [2:0] {S_IDLE, S_WB_REQ, S_WB_WAIT, S_REFILL_REQ,
                            S_REFILL_WAIT, S_RESP} state_t;
  state_t state_q;
  logic [SETS-1:0] valid_q, dirty_q;
  logic [TAG_W-1:0] tag_q [0:SETS-1];
  logic [LINE_BYTES*8-1:0] data_q [0:SETS-1];

  logic [PADDR_W-1:0] req_addr_q;
  logic req_write_q;
  logic [DATA_W-1:0] req_wdata_q;
  logic [DATA_W/8-1:0] req_be_q;
  logic [INDEX_W-1:0] req_index;
  logic [TAG_W-1:0] req_tag;
  logic [INDEX_W-1:0] saved_index_q;
  logic [TAG_W-1:0] saved_tag_q;
  logic [LINE_BYTES*8-1:0] victim_line_q;
  logic [PADDR_W-1:0] victim_addr_q;
  logic [DATA_W-1:0] response_data_q;
  logic response_error_q;
  logic invalidate_pending_q;
  logic [LINE_BYTES*8-1:0] refill_line;
  logic hit;
  logic [DATA_W-1:0] hit_word;
  logic [INDEX_W-1:0] word_index;

  assign req_index = req_addr[OFFSET_W + INDEX_W - 1:OFFSET_W];
  assign req_tag = req_addr[PADDR_W-1:OFFSET_W+INDEX_W];
  assign word_index = req_addr[OFFSET_W-1:3];
  assign hit = valid_q[req_index] && (tag_q[req_index] == req_tag);
  assign hit_word = data_q[req_index][word_index*DATA_W +: DATA_W];
  assign req_ready = (state_q == S_IDLE) && !invalidate_all && !invalidate_pending_q;
  assign rsp_valid = (state_q == S_RESP);
  assign rsp_rdata = response_data_q;
  assign rsp_error = response_error_q;
  assign mem_rsp_ready = (state_q == S_WB_WAIT) || (state_q == S_REFILL_WAIT);

  always_comb begin
    mem_req_valid = 1'b0;
    mem_req_write = 1'b0;
    mem_req_addr = '0;
    mem_req_wdata = '0;
    mem_req_wstrb = '0;
    case (state_q)
      S_WB_REQ: begin
        mem_req_valid = 1'b1;
        mem_req_write = 1'b1;
        mem_req_addr = victim_addr_q;
        mem_req_wdata = victim_line_q;
        mem_req_wstrb = '1;
      end
      S_REFILL_REQ: begin
        mem_req_valid = 1'b1;
        mem_req_write = 1'b0;
        mem_req_addr = {req_addr_q[PADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}};
      end
      default: begin end
    endcase
  end

  // Byte enables/data are low-aligned at the request interface. The cache
  // shifts them into the addressed byte lanes within the containing 64-bit word.
  always_comb begin
    refill_line = mem_rsp_rdata;
    for (int b = 0; b < DATA_W/8; b++) begin
      if (req_be_q[b]) begin
        refill_line[(req_addr_q[OFFSET_W-1:3]*DATA_W)+(req_addr_q[2:0]+b)*8 +: 8] = req_wdata_q[8*b +: 8];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      valid_q <= '0;
      dirty_q <= '0;
      req_addr_q <= '0;
      req_write_q <= 1'b0;
      req_wdata_q <= '0;
      req_be_q <= '0;
      saved_index_q <= '0;
      saved_tag_q <= '0;
      victim_line_q <= '0;
      victim_addr_q <= '0;
      response_data_q <= '0;
      response_error_q <= 1'b0;
      invalidate_pending_q <= 1'b0;
      for (int i = 0; i < SETS; i++) begin
        tag_q[i] <= '0;
        data_q[i] <= '0;
      end
    end else if ((state_q == S_IDLE) && (invalidate_all || invalidate_pending_q)) begin
      // Maintenance invalidation is explicit. Dirty lines must be cleaned by
      // software/platform policy before invalidation; this signal discards them.
      // A pulse received while busy is latched and serviced once the response
      // has drained and the controller returns to idle.
      valid_q <= '0;
      dirty_q <= '0;
      invalidate_pending_q <= 1'b0;
    end else begin
      if (invalidate_all && state_q != S_IDLE)
        invalidate_pending_q <= 1'b1;
      case (state_q)
        S_IDLE: begin
          if (req_valid && req_ready) begin
            req_addr_q <= req_addr;
            req_write_q <= req_write;
            req_wdata_q <= req_wdata;
            req_be_q <= req_byte_enable;
            saved_index_q <= req_index;
            saved_tag_q <= req_tag;
            response_error_q <= 1'b0;
            if (hit) begin
              if (req_write) begin
                for (int b = 0; b < DATA_W/8; b++) begin
                  if (req_byte_enable[b])
                    data_q[req_index][(req_addr[OFFSET_W-1:0]*8)+(8*b) +: 8] <= req_wdata[8*b +: 8];
                end
                dirty_q[req_index] <= 1'b1;
                response_data_q <= '0;
              end else begin
                response_data_q <= hit_word;
              end
              state_q <= S_RESP;
            end else begin
              if (valid_q[req_index] && dirty_q[req_index]) begin
                victim_line_q <= data_q[req_index];
                victim_addr_q <= {tag_q[req_index], req_index, {OFFSET_W{1'b0}}};
                state_q <= S_WB_REQ;
              end else begin
                state_q <= S_REFILL_REQ;
              end
            end
          end
        end
        S_WB_REQ: if (mem_req_valid && mem_req_ready) state_q <= S_WB_WAIT;
        S_WB_WAIT: begin
          if (mem_rsp_valid) begin
            if (mem_rsp_error) begin
              response_error_q <= 1'b1;
              response_data_q <= '0;
              state_q <= S_RESP;
            end else begin
              dirty_q[saved_index_q] <= 1'b0;
              state_q <= S_REFILL_REQ;
            end
          end
        end
        S_REFILL_REQ: if (mem_req_valid && mem_req_ready) state_q <= S_REFILL_WAIT;
        S_REFILL_WAIT: begin
          if (mem_rsp_valid) begin
            if (mem_rsp_error) begin
              response_error_q <= 1'b1;
              response_data_q <= '0;
              state_q <= S_RESP;
            end else begin
              data_q[saved_index_q] <= req_write_q ? refill_line : mem_rsp_rdata;
              tag_q[saved_index_q] <= saved_tag_q;
              valid_q[saved_index_q] <= 1'b1;
              dirty_q[saved_index_q] <= req_write_q;
              response_data_q <= req_write_q ? '0 : mem_rsp_rdata[(req_addr_q[OFFSET_W-1:3])*DATA_W +: DATA_W];
              state_q <= S_RESP;
            end
          end
        end
        S_RESP: if (rsp_valid && rsp_ready) state_q <= S_IDLE;
        default: state_q <= S_IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert ((SETS & (SETS-1)) == 0) else $error("Cache SETS must be a power of two");
    assert ((LINE_BYTES & (LINE_BYTES-1)) == 0) else $error("Cache LINE_BYTES must be a power of two");
    assert (LINE_BYTES >= 8 && (LINE_BYTES % (DATA_W/8)) == 0) else $error("Cache line geometry is invalid");
    assert (DATA_W == 64) else $error("Current cache datapath expects 64-bit words");
  end
  always_ff @(posedge clk) if (rst_n) begin
    if (invalidate_pending_q)
      assert (!req_ready) else $error("Cache accepted a request before pending invalidation");
    if (req_valid && req_ready) begin
      assert (req_byte_enable != '0) else $error("Cache request has no enabled bytes");
      assert ((req_byte_enable & (req_byte_enable + 8'd1)) == '0)
        else $error("Cache byte enable must be low-contiguous");
      assert ((req_addr[2:0] + $countones(req_byte_enable)) <= (DATA_W/8))
        else $error("Cache access crosses a 64-bit word boundary");
    end
    if (rsp_valid && !rsp_ready) assert ($stable(rsp_rdata) && $stable(rsp_error))
      else $error("Cache response changed under backpressure");
  end
`endif
endmodule
