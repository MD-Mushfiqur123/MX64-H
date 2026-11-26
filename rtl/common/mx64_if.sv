interface mx64_req_rsp_if #(
  parameter int ADDR_W = 48,
  parameter int DATA_W = 64,
  parameter int ID_W = 6
) (input logic clk);
  logic req_valid;
  logic req_ready;
  logic [ADDR_W-1:0] req_addr;
  logic [DATA_W-1:0] req_wdata;
  logic [DATA_W/8-1:0] req_be;
  logic req_write;
  logic [ID_W-1:0] req_id;

  logic rsp_valid;
  logic rsp_ready;
  logic [DATA_W-1:0] rsp_rdata;
  logic [ID_W-1:0] rsp_id;
  logic rsp_error;

  modport master (
    output req_valid, req_addr, req_wdata, req_be, req_write, req_id, rsp_ready,
    input req_ready, rsp_valid, rsp_rdata, rsp_id, rsp_error
  );
  modport slave (
    input req_valid, req_addr, req_wdata, req_be, req_write, req_id, rsp_ready,
    output req_ready, rsp_valid, rsp_rdata, rsp_id, rsp_error
  );
endinterface
