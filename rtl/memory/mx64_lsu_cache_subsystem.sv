// MX64-H Phase 35: integrated LSU control slice and blocking L1D request path.
// Loads are admitted only when the single-outstanding cache bridge can accept
// them. Stores enter the LSU queues speculatively and reach L1D only through
// the explicit in-order store-commit interface below.
// Translation, privilege checks, load-result forwarding merge, replay policy,
// and retirement completion remain explicit upstream/downstream contracts.
module mx64_lsu_cache_subsystem #(
  parameter int LSU_DEPTH = 16,
  parameter int PADDR_W = 40,
  parameter int ADDR_W = 64,
  parameter int DATA_W = 64,
  parameter int SEQ_W = 32,
  parameter int PHYS_W = 7,
  parameter int SLOT_W = $clog2(LSU_DEPTH),
  parameter int LINE_BYTES = 64,
  parameter int CACHE_SETS = 16
) (
  input logic clk,
  input logic rst_n,
  input logic flush_all,
  input logic recover_valid,
  input logic [SEQ_W-1:0] recover_seq,

  input logic req_valid,
  output logic req_ready,
  input logic req_is_store,
  input logic [ADDR_W-1:0] req_base_value,
  input logic [ADDR_W-1:0] req_immediate,
  input logic [2:0] req_size_log2,
  input logic req_signed,
  input logic [SEQ_W-1:0] req_seq,
  input logic [DATA_W-1:0] req_store_data,
  input logic [PHYS_W-1:0] req_base_phys_tag,
  input logic [PHYS_W-1:0] req_store_data_phys_tag,
  input logic [PADDR_W-1:0] req_paddr,

  output logic req_fault_valid,
  output logic [ADDR_W-1:0] req_effective_addr,
  output logic [7:0] req_byte_mask,
  output logic load_order_blocked,
  output logic [7:0] load_forward_mask,
  output logic [DATA_W-1:0] load_forward_data,
  output logic load_forward_complete,
  output logic [SLOT_W-1:0] accepted_lifecycle_slot,
  output logic [SLOT_W-1:0] accepted_store_order_slot,

  input logic load_done_valid,
  input logic [SLOT_W-1:0] load_done_slot,
  input logic load_replay_valid,
  input logic [SLOT_W-1:0] load_replay_slot,
  input logic store_done_valid,
  input logic [SLOT_W-1:0] store_done_slot,
  input logic store_replay_valid,
  input logic [SLOT_W-1:0] store_replay_slot,
  input logic store_commit_valid,
  output logic store_commit_ready,
  input logic [SLOT_W-1:0] store_commit_order_slot,
  input logic [SLOT_W-1:0] store_commit_lifecycle_slot,
  input logic [PADDR_W-1:0] store_commit_paddr,
  input logic [DATA_W-1:0] store_commit_data,
  input logic [7:0] store_commit_byte_enable,
  input logic [1:0] store_commit_size,

  output logic cache_rsp_valid,
  input logic cache_rsp_ready,
  output logic cache_rsp_is_store,
  output logic [SLOT_W-1:0] cache_rsp_lifecycle_slot,
  output logic [DATA_W-1:0] cache_rsp_rdata,
  output logic cache_rsp_error,

  // Independent acknowledgement for failures of already-committed stores.
  output logic store_error_valid,
  input logic store_error_ready,
  output logic [SLOT_W-1:0] store_error_lifecycle_slot,

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
  input logic invalidate_all,

  output logic [3:0] ref_acquire_valid,
  output logic [3:0][PHYS_W-1:0] ref_acquire_tag,
  output logic [4*LSU_DEPTH-1:0] ref_release_valid,
  output logic [4*LSU_DEPTH-1:0][PHYS_W-1:0] ref_release_tag,
  output logic [$clog2(2*LSU_DEPTH+1)-1:0] outstanding_lsu_refs,
  output logic [$clog2(LSU_DEPTH+1)-1:0] store_order_occupancy
);
  logic pipe_req_valid, pipe_req_ready;
  logic cache_req_valid, cache_req_ready;
  logic cache_req_write;
  logic [PADDR_W-1:0] cache_req_addr;
  logic [DATA_W-1:0] cache_req_wdata;
  logic [7:0] cache_req_be;
  logic [1:0] cache_req_size;
  logic cache_req_signed;
  logic bridge_rsp_valid, bridge_rsp_ready;
  logic [DATA_W-1:0] bridge_rsp_data;
  logic bridge_rsp_error;
  logic [SLOT_W-1:0] response_slot_q;
  logic response_is_store_q;
  logic [SLOT_W-1:0] accepted_load_slot;
  logic [SLOT_W-1:0] ignored_store_slot;
  logic [$clog2(2*LSU_DEPTH+1)-1:0] unused_ref_count;

  // One cache transaction may be outstanding. A committing store has
  // priority; a new load is backpressured until the cache port is available.
  assign pipe_req_valid = req_valid &&
      (req_is_store || (cache_req_ready && !store_commit_valid));
  assign req_ready = pipe_req_ready;

  mx64_lsu_pipeline #(
    .DEPTH(LSU_DEPTH), .ADDR_W(ADDR_W), .DATA_W(DATA_W),
    .SEQ_W(SEQ_W), .PHYS_W(PHYS_W), .SLOT_W(SLOT_W)
  ) u_lsu_pipeline (
    .clk, .rst_n, .flush_all, .recover_valid, .recover_seq,
    .req_valid(pipe_req_valid), .req_ready(pipe_req_ready), .req_is_store,
    .req_base_value, .req_immediate, .req_size_log2, .req_seq,
    .req_store_data, .req_base_phys_tag, .req_store_data_phys_tag,
    .req_fault_valid, .req_effective_addr, .req_byte_mask,
    .load_order_blocked, .load_forward_mask, .load_forward_data,
    .load_forward_complete,
    .accepted_lifecycle_slot, .accepted_store_order_slot,
    .load_done_valid, .load_done_slot, .load_replay_valid, .load_replay_slot,
    .store_done_valid, .store_done_slot, .store_replay_valid, .store_replay_slot,
    .store_retire_valid(store_commit_valid && store_commit_ready),
    .store_retire_order_slot(store_commit_order_slot),
    .ref_acquire_valid, .ref_acquire_tag, .ref_release_valid, .ref_release_tag,
    .outstanding_lsu_refs, .store_order_occupancy
  );

  always_comb begin
    cache_req_valid = 1'b0;
    cache_req_write = 1'b0;
    cache_req_addr = '0;
    cache_req_wdata = '0;
    cache_req_be = '0;
    cache_req_size = '0;
    cache_req_signed = 1'b0;
    if (store_commit_valid && !flush_all) begin
      cache_req_valid = 1'b1;
      cache_req_write = 1'b1;
      cache_req_addr = store_commit_paddr;
      cache_req_wdata = store_commit_data;
      cache_req_be = store_commit_byte_enable;
      cache_req_size = store_commit_size;
    end else if (req_valid && !req_is_store && pipe_req_ready && !req_fault_valid) begin
      cache_req_valid = 1'b1;
      cache_req_write = 1'b0;
      cache_req_addr = req_paddr;
      cache_req_be = req_byte_mask;
      cache_req_size = req_size_log2[1:0];
      cache_req_signed = req_signed;
    end
  end

  assign store_commit_ready = store_commit_valid && cache_req_ready && !flush_all;
  assign accepted_load_slot = accepted_lifecycle_slot;
  assign cache_rsp_valid = bridge_rsp_valid;
  assign store_error_valid = bridge_rsp_valid && response_is_store_q && bridge_rsp_error;
  assign store_error_lifecycle_slot = response_slot_q;
  // Do not consume a committed-store error until both consumers acknowledge.
  assign bridge_rsp_ready = cache_rsp_ready &&
                            (!store_error_valid || store_error_ready);
  assign cache_rsp_rdata = bridge_rsp_data;
  assign cache_rsp_error = bridge_rsp_error;
  assign cache_rsp_is_store = response_is_store_q;
  assign cache_rsp_lifecycle_slot = response_slot_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      response_slot_q <= '0;
      response_is_store_q <= 1'b0;
    end else if (cache_req_valid && cache_req_ready) begin
      response_is_store_q <= cache_req_write;
      response_slot_q <= cache_req_write ? store_commit_lifecycle_slot : accepted_load_slot;
    end
  end

  mx64_lsu_cache_bridge #(
    .PADDR_W(PADDR_W), .LINE_BYTES(LINE_BYTES), .SETS(CACHE_SETS), .DATA_W(DATA_W)
  ) u_lsu_l1d_bridge (
    .clk, .rst_n,
    .req_valid(cache_req_valid), .req_ready(cache_req_ready),
    .req_paddr(cache_req_addr), .req_write(cache_req_write),
    .req_wdata(cache_req_wdata), .req_byte_enable(cache_req_be),
    .req_size(cache_req_size), .req_signed(cache_req_signed),
    .rsp_valid(bridge_rsp_valid), .rsp_ready(bridge_rsp_ready),
    .rsp_rdata(bridge_rsp_data), .rsp_error(bridge_rsp_error),
    .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
    .mem_req_wdata, .mem_req_wstrb,
    .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_error,
    .invalidate_all
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (store_commit_valid && store_commit_ready)
      assert (cache_req_valid && cache_req_write) else $error("Store commit accepted without an L1D write request");
    if (req_valid && !req_is_store && req_ready)
      assert (cache_req_valid && !cache_req_write) else $error("Load accepted without an L1D read request");
    if (cache_rsp_valid && !bridge_rsp_ready)
      assert ($stable(response_slot_q) && $stable(response_is_store_q))
        else $error("LSU cache response identity changed under backpressure");
    if (store_error_valid)
      assert (cache_rsp_valid && response_is_store_q && cache_rsp_error &&
              store_error_lifecycle_slot == response_slot_q)
        else $error("Committed-store error sink identity mismatch");
    if (store_error_valid && !store_error_ready)
      assert (!bridge_rsp_ready)
        else $error("Committed-store error was consumed before error-sink acknowledgement");
  end
`endif
endmodule
