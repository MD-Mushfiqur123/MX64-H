// MX64-H Phase 37.1: in-order memory-operation issue queue.
// Keeps memory operations in program order until accepted by the LSU. This is
// deliberately conservative: an older unresolved memory op blocks younger
// memory ops so the LSU's store-dependence scan cannot miss an undispatched op.
module mx64_memory_issue_queue #(
  parameter int DEPTH = 16,
  parameter int WIDTH = 2,
  parameter int WAKEUP_WIDTH = 4,
  parameter int XLEN = 64,
  parameter int PHYS_W = 7,
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W,
  parameter int SEQ_W = 32
) (
  input logic clk,
  input logic rst_n,
  input logic flush,
  input logic recover_valid,
  input logic [SEQ_W-1:0] recover_seq,

  input logic [WIDTH-1:0] enq_valid,
  output logic [WIDTH-1:0] enq_ready,
  input mx64_pkg::issue_uop_t enq_uop [0:WIDTH-1],

  input logic [WAKEUP_WIDTH-1:0] wakeup_valid,
  input logic [WAKEUP_WIDTH-1:0][PHYS_W-1:0] wakeup_tag,
  input logic [WAKEUP_WIDTH-1:0][XLEN-1:0] wakeup_data,

  output logic issue_valid,
  input logic issue_ready,
  output mx64_pkg::issue_uop_t issue_uop,

  output logic [2*WIDTH-1:0] ref_acquire_valid,
  output logic [2*WIDTH-1:0][PHYS_W-1:0] ref_acquire_tag,
  output logic [2*DEPTH-1:0] ref_release_valid,
  output logic [2*DEPTH-1:0][PHYS_W-1:0] ref_release_tag,
  output logic [$clog2(DEPTH+1)-1:0] occupancy
);
  import mx64_pkg::*;
  localparam int COUNT_W = $clog2(DEPTH+1);
  typedef logic [SEQ_W-1:0] seq_t;

  issue_uop_t entry_q [0:DEPTH-1];
  issue_uop_t effective_entry [0:DEPTH-1];
  issue_uop_t effective_enq [0:WIDTH-1];
  logic [DEPTH-1:0] valid_q;
  logic [DEPTH-1:0] recover_kill;
  logic [WIDTH-1:0] enq_fire;
  logic issue_fire;
  logic [COUNT_W-1:0] count_q;
  integer candidate_idx;
  logic candidate_found;
  logic candidate_ready;
  integer enq_count;
  integer kill_count;
  integer free_slots;

  function automatic logic is_older(input seq_t a, input seq_t b);
    is_older = $signed(a - b) < 0;
  endfunction
  function automatic logic is_younger(input seq_t a, input seq_t b);
    is_younger = $signed(a - b) > 0;
  endfunction

  always_comb begin : p_memory_issue
    logic src1_woken;
    logic src2_woken;
    enq_ready = '0;
    enq_fire = '0;
    issue_valid = 1'b0;
    issue_uop = '0;
    issue_fire = 1'b0;
    recover_kill = '0;
    ref_acquire_valid = '0;
    ref_acquire_tag = '0;
    ref_release_valid = '0;
    ref_release_tag = '0;
    occupancy = count_q;
    enq_count = 0;
    kill_count = 0;
    free_slots = DEPTH - int'(count_q);
    candidate_idx = -1;
    candidate_found = 1'b0;
    candidate_ready = 1'b0;

    for (int e = 0; e < DEPTH; e++) begin
      effective_entry[e] = entry_q[e];
      if (valid_q[e]) begin
        // Ascending index gives wakeup lane 0 priority, matching the
        // physical register file's documented write-port-0 collision priority.
        for (int w = 0; w < WAKEUP_WIDTH; w++) begin
          if (wakeup_valid[w]) begin
            if (!effective_entry[e].src1_ready &&
                effective_entry[e].src1_tag == wakeup_tag[w]) begin
              effective_entry[e].src1_ready = 1'b1;
              effective_entry[e].src1_value = wakeup_data[w];
            end
            if (!effective_entry[e].src2_ready &&
                effective_entry[e].src2_tag == wakeup_tag[w]) begin
              effective_entry[e].src2_ready = 1'b1;
              effective_entry[e].src2_value = wakeup_data[w];
            end
          end
        end
      end
    end

    // The oldest valid memory op is the only candidate. A younger ready op
    // may not pass an older unresolved op.
    for (int e = 0; e < DEPTH; e++) begin
      if (valid_q[e]) begin
        if (!candidate_found) begin
          candidate_found = 1'b1;
          candidate_idx = e;
        end else if (is_older(seq_t'(entry_q[e].seq_num),
                              seq_t'(entry_q[candidate_idx].seq_num))) begin
          candidate_idx = e;
        end
      end
    end
    if (candidate_found) begin
      candidate_ready = effective_entry[candidate_idx].src1_ready &&
                        effective_entry[candidate_idx].src2_ready;
      if (!flush && !recover_valid && candidate_ready) begin
        issue_valid = 1'b1;
        issue_uop = effective_entry[candidate_idx];
      end
    end
    issue_fire = issue_valid && issue_ready;

    // Capacity is independent of valid. Same-cycle dequeue does not create a
    // same-cycle allocation slot, avoiding ambiguous slot reuse.
    for (int p = 0; p < WIDTH; p++) begin
      if (!flush && !recover_valid && free_slots > 0 &&
          ((p == 0) || !enq_valid[0] || enq_ready[0])) begin
        enq_ready[p] = 1'b1;
        enq_fire[p] = enq_valid[p];
        if (enq_valid[p]) begin
          free_slots = free_slots - 1;
          enq_count = enq_count + 1;
        end
      end
    end

    // Apply wakeup to same-cycle enqueues before reference acquisition.
    for (int p = 0; p < WIDTH; p++) begin
      effective_enq[p] = enq_uop[p];
      if (enq_fire[p]) begin
        for (int w = 0; w < WAKEUP_WIDTH; w++) begin
          if (wakeup_valid[w]) begin
            if (!effective_enq[p].src1_ready &&
                effective_enq[p].src1_tag == wakeup_tag[w]) begin
              effective_enq[p].src1_ready = 1'b1;
              effective_enq[p].src1_value = wakeup_data[w];
            end
            if (!effective_enq[p].src2_ready &&
                effective_enq[p].src2_tag == wakeup_tag[w]) begin
              effective_enq[p].src2_ready = 1'b1;
              effective_enq[p].src2_value = wakeup_data[w];
            end
          end
        end
        if (!effective_enq[p].src1_ready) begin
          ref_acquire_valid[2*p] = 1'b1;
          ref_acquire_tag[2*p] = effective_enq[p].src1_tag;
        end
        if (!effective_enq[p].src2_ready) begin
          ref_acquire_valid[2*p+1] = 1'b1;
          ref_acquire_tag[2*p+1] = effective_enq[p].src2_tag;
        end
      end
    end

    // Release one reference per newly-woken operand, or release every
    // unresolved operand on flush/recovery kill.
    for (int e = 0; e < DEPTH; e++) begin
      if (valid_q[e]) begin
        if (flush || (recover_valid && is_younger(seq_t'(entry_q[e].seq_num), seq_t'(recover_seq)))) begin
          if (!entry_q[e].src1_ready) begin
            ref_release_valid[2*e] = 1'b1;
            ref_release_tag[2*e] = entry_q[e].src1_tag;
          end
          if (!entry_q[e].src2_ready) begin
            ref_release_valid[2*e+1] = 1'b1;
            ref_release_tag[2*e+1] = entry_q[e].src2_tag;
          end
        end else begin
          src1_woken = 1'b0;
          src2_woken = 1'b0;
          for (int w = 0; w < WAKEUP_WIDTH; w++) begin
            if (wakeup_valid[w] && !entry_q[e].src1_ready &&
                entry_q[e].src1_tag == wakeup_tag[w]) src1_woken = 1'b1;
            if (wakeup_valid[w] && !entry_q[e].src2_ready &&
                entry_q[e].src2_tag == wakeup_tag[w]) src2_woken = 1'b1;
          end
          if (src1_woken) begin
            ref_release_valid[2*e] = 1'b1;
            ref_release_tag[2*e] = entry_q[e].src1_tag;
          end
          if (src2_woken) begin
            ref_release_valid[2*e+1] = 1'b1;
            ref_release_tag[2*e+1] = entry_q[e].src2_tag;
          end
        end
      end
    end

    for (int e = 0; e < DEPTH; e++) begin
      if (valid_q[e] && recover_valid && is_younger(seq_t'(entry_q[e].seq_num), seq_t'(recover_seq)))
        begin recover_kill[e] = 1'b1; kill_count = kill_count + 1; end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : p_memory_issue_state
    integer alloc_slot;
    logic found_free_slot;
    logic [DEPTH-1:0] allocated_mask;
    if (!rst_n) begin
      valid_q <= '0;
      count_q <= '0;
      for (int e = 0; e < DEPTH; e++) entry_q[e] <= '0;
    end else if (flush) begin
      valid_q <= '0;
      count_q <= '0;
    end else if (recover_valid) begin
      for (int e = 0; e < DEPTH; e++) begin
        if (recover_kill[e]) valid_q[e] <= 1'b0;
        else if (valid_q[e]) entry_q[e] <= effective_entry[e];
      end
      count_q <= count_q - COUNT_W'(kill_count);
    end else begin
      allocated_mask = valid_q;
      alloc_slot = -1;
      found_free_slot = 1'b0;
      for (int e = 0; e < DEPTH; e++) begin
        if (valid_q[e]) begin
          entry_q[e] <= effective_entry[e];
          if (issue_fire && candidate_idx == e) valid_q[e] <= 1'b0;
        end
      end
      if (issue_fire) valid_q[candidate_idx] <= 1'b0;
      for (int p = 0; p < WIDTH; p++) begin
        if (enq_fire[p]) begin
          alloc_slot = -1;
          found_free_slot = 1'b0;
          for (int e = 0; e < DEPTH; e++) begin
            if (!allocated_mask[e] && !found_free_slot) begin
              alloc_slot = e;
              found_free_slot = 1'b1;
            end
          end
          if (found_free_slot) begin
            entry_q[alloc_slot] <= effective_enq[p];
            valid_q[alloc_slot] <= 1'b1;
            allocated_mask[alloc_slot] = 1'b1;
          end
        end
      end
      count_q <= count_q + COUNT_W'(enq_count) - COUNT_W'(issue_fire);
    end
  end

`ifndef SYNTHESIS
  property p_issue_payload_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n || flush || recover_valid)
      (issue_valid && !issue_ready) |=> (issue_valid && $stable(issue_uop));
  endproperty
  assert property (p_issue_payload_stable_when_stalled)
    else $error("memory issue queue changed output while stalled");

  always_ff @(posedge clk) begin
    if (rst_n && !flush && !recover_valid && issue_fire)
      assert (issue_uop.is_load || issue_uop.is_store)
        else $error("non-memory operation entered memory issue queue");
  end
  initial if (DEPTH < 2 || WIDTH < 1) $error("invalid memory issue queue geometry");
`endif
endmodule
