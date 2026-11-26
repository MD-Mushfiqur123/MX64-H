// MX64-H Phase 30: load/store queue ownership of physical source tags.
// One load and one store may be accepted per cycle. Each retained entry owns
// address-base and (for stores) store-data tags until completion, replay, or flush.
module lsu_reference_lifecycle #(
  parameter int DEPTH = 16,
  parameter int PHYS_W = 7,
  parameter int SLOT_W = $clog2(DEPTH)
) (
  input logic clk,
  input logic rst_n,
  input logic flush_all,
  input logic recover_valid,
  input logic [31:0] recover_seq,
  input logic load_alloc_valid,
  output logic load_alloc_ready,
  input logic [PHYS_W-1:0] load_base_tag,
  output logic [SLOT_W-1:0] load_alloc_slot,
  input logic store_alloc_valid,
  output logic store_alloc_ready,
  input logic [PHYS_W-1:0] store_base_tag,
  input logic [PHYS_W-1:0] store_data_tag,
  input logic [31:0] store_alloc_seq,
  output logic [SLOT_W-1:0] store_alloc_slot,
  input logic load_done_valid,
  input logic [SLOT_W-1:0] load_done_slot,
  input logic load_replay_valid,
  input logic [SLOT_W-1:0] load_replay_slot,
  input logic store_done_valid,
  input logic [SLOT_W-1:0] store_done_slot,
  input logic store_replay_valid,
  input logic [SLOT_W-1:0] store_replay_slot,
  output logic [3:0] acquire_valid,
  output logic [3:0][PHYS_W-1:0] acquire_tag,
  output logic [4*DEPTH-1:0] release_valid,
  output logic [4*DEPTH-1:0][PHYS_W-1:0] release_tag,
  output logic [$clog2(2*DEPTH+1)-1:0] outstanding_count
);
  logic [DEPTH-1:0] load_valid_q, store_valid_q;
  logic [PHYS_W-1:0] load_base_q [0:DEPTH-1];
  logic [PHYS_W-1:0] store_base_q [0:DEPTH-1], store_data_q [0:DEPTH-1];
  logic [31:0] store_seq_q [0:DEPTH-1];
  logic [DEPTH-1:0] load_valid_d, store_valid_d;
  logic [PHYS_W-1:0] load_base_d [0:DEPTH-1];
  logic [PHYS_W-1:0] store_base_d [0:DEPTH-1], store_data_d [0:DEPTH-1];
  logic load_done_fire, load_replay_fire, store_done_fire, store_replay_fire;

  function automatic logic seq_younger(input logic [31:0] a, input logic [31:0] b);
    seq_younger = $signed(a - b) > 0;
  endfunction

  always_comb begin
    load_alloc_ready = 1'b0; store_alloc_ready = 1'b0;
    load_alloc_slot = '0; store_alloc_slot = '0;
    for (int i = DEPTH-1; i >= 0; i--) begin
      if (!load_valid_q[i]) begin load_alloc_ready = 1'b1; load_alloc_slot = SLOT_W'(i); end
      if (!store_valid_q[i]) begin store_alloc_ready = 1'b1; store_alloc_slot = SLOT_W'(i); end
    end
    load_done_fire = load_done_valid && (load_done_slot < DEPTH) && load_valid_q[load_done_slot];
    load_replay_fire = load_replay_valid && (load_replay_slot < DEPTH) && load_valid_q[load_replay_slot];
    store_done_fire = store_done_valid && (store_done_slot < DEPTH) && store_valid_q[store_done_slot];
    store_replay_fire = store_replay_valid && (store_replay_slot < DEPTH) && store_valid_q[store_replay_slot];

    acquire_valid = '0; acquire_tag = '0;
    if (!flush_all && load_alloc_valid && load_alloc_ready) begin
      acquire_valid[0] = 1'b1; acquire_tag[0] = load_base_tag;
    end
    if (!flush_all && store_alloc_valid && store_alloc_ready) begin
      acquire_valid[2] = 1'b1; acquire_tag[2] = store_base_tag;
      acquire_valid[3] = 1'b1; acquire_tag[3] = store_data_tag;
    end

    release_valid = '0; release_tag = '0;
    for (int i = 0; i < DEPTH; i++) begin
      if (load_valid_q[i] && (flush_all || (load_done_fire && load_done_slot == SLOT_W'(i)) || (load_replay_fire && load_replay_slot == SLOT_W'(i)))) begin
        release_valid[2*i] = 1'b1; release_tag[2*i] = load_base_q[i];
      end
      if (store_valid_q[i] && (flush_all || (recover_valid && seq_younger(store_seq_q[i], recover_seq)) || (store_done_fire && store_done_slot == SLOT_W'(i)) || (store_replay_fire && store_replay_slot == SLOT_W'(i)))) begin
        release_valid[2*DEPTH+2*i] = 1'b1; release_tag[2*DEPTH+2*i] = store_base_q[i];
        release_valid[2*DEPTH+2*i+1] = 1'b1; release_tag[2*DEPTH+2*i+1] = store_data_q[i];
      end
    end
  end

  always_comb begin
    load_valid_d = load_valid_q; store_valid_d = store_valid_q;
    for (int i = 0; i < DEPTH; i++) begin
      load_base_d[i] = load_base_q[i];
      store_base_d[i] = store_base_q[i]; store_data_d[i] = store_data_q[i];
      if (flush_all || (load_done_fire && load_done_slot == SLOT_W'(i)) || (load_replay_fire && load_replay_slot == SLOT_W'(i))) load_valid_d[i] = 1'b0;
      if (flush_all || (recover_valid && seq_younger(store_seq_q[i], recover_seq)) || (store_done_fire && store_done_slot == SLOT_W'(i)) || (store_replay_fire && store_replay_slot == SLOT_W'(i))) store_valid_d[i] = 1'b0;
    end
    if (!flush_all && load_alloc_valid && load_alloc_ready) begin
      load_valid_d[load_alloc_slot] = 1'b1; load_base_d[load_alloc_slot] = load_base_tag;
    end
    if (!flush_all && store_alloc_valid && store_alloc_ready) begin
      store_valid_d[store_alloc_slot] = 1'b1; store_base_d[store_alloc_slot] = store_base_tag;
      store_data_d[store_alloc_slot] = store_data_tag;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_valid_q <= '0; store_valid_q <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        load_base_q[i] <= '0; store_base_q[i] <= '0; store_data_q[i] <= '0; store_seq_q[i] <= '0;
      end
    end else begin
      load_valid_q <= load_valid_d; store_valid_q <= store_valid_d;
      for (int i = 0; i < DEPTH; i++) begin
        load_base_q[i] <= load_base_d[i]; store_base_q[i] <= store_base_d[i];
        store_data_q[i] <= store_data_d[i];
        if (store_alloc_valid && store_alloc_ready && store_alloc_slot == SLOT_W'(i)) store_seq_q[i] <= store_alloc_seq;
      end
    end
  end

  always_comb outstanding_count = $clog2(2*DEPTH+1)'($countones(load_valid_q) + $countones(store_valid_q));

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n && !flush_all) begin
    if (load_done_valid) assert (load_done_fire) else $error("LSU load completion references an inactive slot");
    if (load_replay_valid) assert (load_replay_fire) else $error("LSU load replay references an inactive slot");
    if (store_done_valid) assert (store_done_fire) else $error("LSU store completion references an inactive slot");
    if (store_replay_valid) assert (store_replay_fire) else $error("LSU store replay references an inactive slot");
    assert (!(load_done_fire && load_replay_fire && load_done_slot == load_replay_slot)) else $error("LSU load slot completed and replayed twice");
    assert (!(store_done_fire && store_replay_fire && store_done_slot == store_replay_slot)) else $error("LSU store slot completed and replayed twice");
  end
`endif
endmodule
