// MX64-H Phase 32: single-request LSU front-end pipeline.
// Integrates AGU, conservative store ordering/forwarding, and physical-tag
// reference lifetime tracking. Cache/TLB/bus and completion scheduling remain external.
module mx64_lsu_pipeline #(
  parameter int DEPTH = 16,
  parameter int ADDR_W = 64,
  parameter int DATA_W = 64,
  parameter int SEQ_W = 32,
  parameter int PHYS_W = 7,
  parameter int SLOT_W = $clog2(DEPTH)
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
  input logic [SEQ_W-1:0] req_seq,
  input logic [DATA_W-1:0] req_store_data,
  input logic [PHYS_W-1:0] req_base_phys_tag,
  input logic [PHYS_W-1:0] req_store_data_phys_tag,

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
  input logic store_retire_valid,
  input logic [SLOT_W-1:0] store_retire_order_slot,

  output logic [3:0] ref_acquire_valid,
  output logic [3:0][PHYS_W-1:0] ref_acquire_tag,
  output logic [4*DEPTH-1:0] ref_release_valid,
  output logic [4*DEPTH-1:0][PHYS_W-1:0] ref_release_tag,
  output logic [$clog2(2*DEPTH+1)-1:0] outstanding_lsu_refs,
  output logic [$clog2(DEPTH+1)-1:0] store_order_occupancy
);
  logic [ADDR_W-1:0] agu_addr;
  logic [7:0] agu_mask;
  logic agu_size_valid, agu_misaligned;
  logic load_alloc_ready, store_lifecycle_ready, store_order_ready;
  logic [SLOT_W-1:0] load_lifecycle_slot, store_lifecycle_slot, store_order_slot;
  logic load_query_valid, load_can_issue, older_store_unresolved;
  logic [7:0] forward_mask;
  logic [DATA_W-1:0] forward_data;
  logic forward_complete;
  logic load_accept, store_accept;

  mx64_address_generation_unit #(.ADDR_W(ADDR_W), .BYTE_LANES(8)) u_agu (
    .base_value(req_base_value), .immediate(req_immediate),
    .size_log2(req_size_log2), .effective_addr(agu_addr),
    .byte_mask(agu_mask), .size_valid(agu_size_valid), .misaligned(agu_misaligned)
  );

  assign req_effective_addr = agu_addr;
  assign req_byte_mask = agu_mask;
  assign req_fault_valid = req_valid && !flush_all && (!agu_size_valid || agu_misaligned);
  assign load_query_valid = req_valid && !req_is_store && !req_fault_valid && !flush_all;
  assign load_order_blocked = load_query_valid && !load_can_issue;

  // A load waits if an older store address/data is unresolved. A store waits
  // for both its lifecycle slot and ordering-queue slot.
  always_comb begin
    req_ready = 1'b0;
    if (!flush_all && req_valid && !req_fault_valid) begin
      if (req_is_store)
        req_ready = store_lifecycle_ready && store_order_ready;
      else
        req_ready = load_alloc_ready && load_can_issue;
    end
  end
  assign load_accept = req_valid && req_ready && !req_is_store;
  assign store_accept = req_valid && req_ready && req_is_store;
  assign accepted_lifecycle_slot = req_is_store ? store_lifecycle_slot : load_lifecycle_slot;
  assign accepted_store_order_slot = store_order_slot;

  lsu_reference_lifecycle #(.DEPTH(DEPTH), .PHYS_W(PHYS_W), .SLOT_W(SLOT_W)) u_lsu_refs (
    .clk, .rst_n, .flush_all, .recover_valid, .recover_seq,
    .load_alloc_valid(load_accept), .load_alloc_ready, .load_base_tag(req_base_phys_tag),
    .load_alloc_slot(load_lifecycle_slot),
    .store_alloc_valid(store_accept), .store_alloc_ready(store_lifecycle_ready),
    .store_base_tag(req_base_phys_tag), .store_data_tag(req_store_data_phys_tag), .store_alloc_seq(req_seq),
    .store_alloc_slot(store_lifecycle_slot),
    .load_done_valid, .load_done_slot, .load_replay_valid, .load_replay_slot,
    .store_done_valid, .store_done_slot, .store_replay_valid, .store_replay_slot,
    .acquire_valid(ref_acquire_valid), .acquire_tag(ref_acquire_tag),
    .release_valid(ref_release_valid), .release_tag(ref_release_tag),
    .outstanding_count(outstanding_lsu_refs)
  );

  memory_ordering_unit #(.DEPTH(DEPTH), .ADDR_W(ADDR_W), .DATA_W(DATA_W), .SEQ_W(SEQ_W), .SLOT_W(SLOT_W)) u_memory_ordering (
    .clk, .rst_n, .flush_all, .recover_valid, .recover_seq,
    .store_alloc_valid(store_accept), .store_alloc_ready(store_order_ready),
    .store_alloc_slot(store_order_slot), .store_alloc_seq(req_seq),
    .store_alloc_addr_valid(1'b1), .store_alloc_addr(agu_addr),
    .store_alloc_mask(agu_mask), .store_alloc_data_valid(1'b1), .store_alloc_data(req_store_data),
    .store_addr_resolve_valid(1'b0), .store_addr_resolve_slot('0),
    .store_resolved_addr('0), .store_resolved_mask('0),
    .store_data_resolve_valid(1'b0), .store_data_resolve_slot('0), .store_resolved_data('0),
    .store_retire_valid, .store_retire_slot(store_retire_order_slot),
    .load_query_valid, .load_query_seq(req_seq), .load_query_addr(agu_addr), .load_query_mask(agu_mask),
    .load_can_issue, .older_store_unresolved,
    .forward_mask, .forward_data, .forward_complete,
    .store_occupancy(store_order_occupancy)
  );

  assign load_forward_mask = forward_mask;
  assign load_forward_data = forward_data;
  assign load_forward_complete = forward_complete;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n && !flush_all) begin
    if (req_valid && !req_is_store && req_fault_valid) assert (!load_accept) else $error("Misaligned/invalid load was accepted");
    if (req_valid && req_is_store && req_fault_valid) assert (!store_accept) else $error("Misaligned/invalid store was accepted");
    if (store_accept) assert (store_order_ready && store_lifecycle_ready) else $error("Store accepted without both queue slots");
    if (load_accept) assert (load_alloc_ready && load_can_issue) else $error("Load accepted while blocked by older store");
  end
`endif
endmodule
