// MX64-H Phase 31: conservative store-queue ordering and byte forwarding.
// This is an ordering/forwarding primitive, not a complete LSU or bus interface.
module memory_ordering_unit #(
  parameter int DEPTH = 16,
  parameter int ADDR_W = 64,
  parameter int DATA_W = 64,
  parameter int SEQ_W = 32,
  parameter int SLOT_W = $clog2(DEPTH),
  parameter int BYTE_LANES = DATA_W / 8
) (
  input  logic clk,
  input  logic rst_n,
  input  logic flush_all,
  input  logic recover_valid,
  input  logic [SEQ_W-1:0] recover_seq,

  input  logic store_alloc_valid,
  output logic store_alloc_ready,
  output logic [SLOT_W-1:0] store_alloc_slot,
  input  logic [SEQ_W-1:0] store_alloc_seq,
  input  logic store_alloc_addr_valid,
  input  logic [ADDR_W-1:0] store_alloc_addr,
  input  logic [BYTE_LANES-1:0] store_alloc_mask,
  input  logic store_alloc_data_valid,
  input  logic [DATA_W-1:0] store_alloc_data,

  input  logic store_addr_resolve_valid,
  input  logic [SLOT_W-1:0] store_addr_resolve_slot,
  input  logic [ADDR_W-1:0] store_resolved_addr,
  input  logic [BYTE_LANES-1:0] store_resolved_mask,
  input  logic store_data_resolve_valid,
  input  logic [SLOT_W-1:0] store_data_resolve_slot,
  input  logic [DATA_W-1:0] store_resolved_data,

  input  logic store_retire_valid,
  input  logic [SLOT_W-1:0] store_retire_slot,

  input  logic load_query_valid,
  input  logic [SEQ_W-1:0] load_query_seq,
  input  logic [ADDR_W-1:0] load_query_addr,
  input  logic [BYTE_LANES-1:0] load_query_mask,
  output logic load_can_issue,
  output logic older_store_unresolved,
  output logic [BYTE_LANES-1:0] forward_mask,
  output logic [DATA_W-1:0] forward_data,
  output logic forward_complete,
  output logic [$clog2(DEPTH+1)-1:0] store_occupancy
);
  logic [DEPTH-1:0] valid_q, valid_d;
  logic [DEPTH-1:0] addr_valid_q, data_valid_q;
  logic [SEQ_W-1:0] seq_q [0:DEPTH-1];
  logic [ADDR_W-1:0] addr_q [0:DEPTH-1];
  logic [BYTE_LANES-1:0] mask_q [0:DEPTH-1];
  logic [DATA_W-1:0] data_q [0:DEPTH-1];
  logic retire_fire;

  function automatic logic seq_older(input logic [SEQ_W-1:0] a, input logic [SEQ_W-1:0] b);
    seq_older = $signed(a - b) < 0;
  endfunction

  function automatic logic seq_younger(input logic [SEQ_W-1:0] a, input logic [SEQ_W-1:0] b);
    seq_younger = $signed(a - b) > 0;
  endfunction

  always_comb begin
    store_alloc_ready = 1'b0;
    store_alloc_slot = '0;
    for (int i = DEPTH-1; i >= 0; i--) begin
      if (!valid_q[i]) begin
        store_alloc_ready = !flush_all;
        store_alloc_slot = SLOT_W'(i);
      end
    end
    retire_fire = store_retire_valid && (store_retire_slot < DEPTH) && valid_q[store_retire_slot];

    older_store_unresolved = 1'b0;
    forward_mask = '0;
    forward_data = '0;
    // For each requested load byte, select the youngest older matching store.
    // Sequence numbers are monotonically increasing and must not wrap while
    // any entry in this queue remains live.
    for (int b = 0; b < BYTE_LANES; b++) begin : g_forward_byte
      logic found_byte;
      logic [SEQ_W-1:0] best_seq;
      logic [7:0] best_data;
      found_byte = 1'b0;
      best_seq = '0;
      best_data = '0;
      if (load_query_valid && load_query_mask[b]) begin
        for (int s = 0; s < DEPTH; s++) begin
          if (valid_q[s] && seq_older(seq_q[s], load_query_seq)) begin
            if (!addr_valid_q[s]) begin
              older_store_unresolved = 1'b1;
            end else if (mask_q[s][0] && (addr_q[s] + ADDR_W'(0) == load_query_addr + ADDR_W'(b))) begin
              if (!data_valid_q[s]) begin
                older_store_unresolved = 1'b1;
              end else if (!found_byte || seq_younger(seq_q[s], best_seq)) begin
                found_byte = 1'b1;
                best_seq = seq_q[s];
                best_data = data_q[s][7:0];
              end
            end
            // Other bytes of a store are compared against their byte address.
            for (int sb = 1; sb < BYTE_LANES; sb++) begin
              if (addr_valid_q[s] && mask_q[sb] &&
                  (addr_q[s] + ADDR_W'(sb) == load_query_addr + ADDR_W'(b))) begin
                if (!data_valid_q[s]) begin
                  older_store_unresolved = 1'b1;
                end else if (!found_byte || seq_younger(seq_q[s], best_seq)) begin
                  found_byte = 1'b1;
                  best_seq = seq_q[s];
                  best_data = data_q[s][8*sb +: 8];
                end
              end
            end
          end
        end
      end
      if (found_byte) begin
        forward_mask[b] = 1'b1;
        forward_data[8*b +: 8] = best_data;
      end
    end
    forward_complete = load_query_valid && ((forward_mask & load_query_mask) == load_query_mask);
    load_can_issue = load_query_valid && !older_store_unresolved;
  end

  always_comb begin
    valid_d = valid_q;
    if (flush_all) valid_d = '0;
    else begin
      if (recover_valid) begin
        for (int r = 0; r < DEPTH; r++)
          if (valid_q[r] && seq_younger(seq_q[r], recover_seq)) valid_d[r] = 1'b0;
      end
      if (retire_fire) valid_d[store_retire_slot] = 1'b0;
      if (store_alloc_valid && store_alloc_ready) valid_d[store_alloc_slot] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        addr_valid_q[i] <= 1'b0;
        data_valid_q[i] <= 1'b0;
        seq_q[i] <= '0;
        addr_q[i] <= '0;
        mask_q[i] <= '0;
        data_q[i] <= '0;
      end
    end else begin
      valid_q <= valid_d;
      if (flush_all) begin
        addr_valid_q <= '0;
        data_valid_q <= '0;
      end else begin
        if (recover_valid) begin
          for (int r = 0; r < DEPTH; r++) begin
            if (valid_q[r] && seq_younger(seq_q[r], recover_seq)) begin
              addr_valid_q[r] <= 1'b0;
              data_valid_q[r] <= 1'b0;
            end
          end
        end
        if (retire_fire) begin
          addr_valid_q[store_retire_slot] <= 1'b0;
          data_valid_q[store_retire_slot] <= 1'b0;
        end
        if (store_addr_resolve_valid && (store_addr_resolve_slot < DEPTH) && valid_q[store_addr_resolve_slot]) begin
          addr_valid_q[store_addr_resolve_slot] <= 1'b1;
          addr_q[store_addr_resolve_slot] <= store_resolved_addr;
          mask_q[store_addr_resolve_slot] <= store_resolved_mask;
        end
        if (store_data_resolve_valid && (store_data_resolve_slot < DEPTH) && valid_q[store_data_resolve_slot]) begin
          data_valid_q[store_data_resolve_slot] <= 1'b1;
          data_q[store_data_resolve_slot] <= store_resolved_data;
        end
        if (store_alloc_valid && store_alloc_ready) begin
          seq_q[store_alloc_slot] <= store_alloc_seq;
          addr_valid_q[store_alloc_slot] <= store_alloc_addr_valid;
          addr_q[store_alloc_slot] <= store_alloc_addr;
          mask_q[store_alloc_slot] <= store_alloc_mask;
          data_valid_q[store_alloc_slot] <= store_alloc_data_valid;
          data_q[store_alloc_slot] <= store_alloc_data;
        end
      end
    end
  end

  always_comb store_occupancy = $clog2(DEPTH+1)'($countones(valid_q));

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n && !flush_all) begin
    if (store_retire_valid) assert (retire_fire) else $error("Memory ordering unit retires an inactive store slot");
    if (store_alloc_valid && store_alloc_ready) assert (store_alloc_mask != '0) else $error("Store allocation has an empty byte mask");
    if (store_addr_resolve_valid) assert ((store_addr_resolve_slot < DEPTH) && valid_q[store_addr_resolve_slot]) else $error("Store address resolution references an inactive slot");
    if (store_data_resolve_valid) assert ((store_data_resolve_slot < DEPTH) && valid_q[store_data_resolve_slot]) else $error("Store data resolution references an inactive slot");
  end
`endif
endmodule
