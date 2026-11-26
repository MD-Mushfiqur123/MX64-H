// MX64 M2 draft: age-ordered, two-enqueue/two-issue integer issue queue.
// Wakeup is applied combinationally, so a completion broadcast can make an
// operand eligible for issue in the same cycle. This is an initial RTL draft;
// compile, simulation and formal verification are still required.
module issue_queue #(
  parameter int DEPTH = 16,
  parameter int WIDTH = 2,
  parameter int WAKEUP_WIDTH = WIDTH,
  parameter int XLEN = 64,
  parameter int PHYS_W = 7,
  parameter int ROB_TAG_W = mx64_pkg::ROB_TAG_W,
  parameter int SEQ_W = 32
) (
  input  logic clk,
  input  logic rst_n,
  input  logic flush,
  input  logic recover_valid,
  input  logic [31:0] recover_seq,

  input  logic [WIDTH-1:0] enq_valid,
  output logic [WIDTH-1:0] enq_ready,
  input  mx64_pkg::issue_uop_t enq_uop [0:WIDTH-1],

  input  logic [WAKEUP_WIDTH-1:0] wakeup_valid,
  input  logic [WAKEUP_WIDTH-1:0][PHYS_W-1:0] wakeup_tag,
  input  logic [WAKEUP_WIDTH-1:0][XLEN-1:0] wakeup_data,

  output logic [WIDTH-1:0] issue_valid,
  input  logic [WIDTH-1:0] issue_ready,
  output mx64_pkg::issue_uop_t issue_uop [0:WIDTH-1],
  output logic [2*WIDTH-1:0] ref_acquire_valid,
  output logic [2*WIDTH-1:0][PHYS_W-1:0] ref_acquire_tag,
  output logic [2*DEPTH-1:0] ref_release_valid,
  output logic [2*DEPTH-1:0][PHYS_W-1:0] ref_release_tag,

  output logic [$clog2(DEPTH+1)-1:0] occupancy,
  output logic full,
  output logic empty
);
  import mx64_pkg::*;

  localparam int COUNT_W = $clog2(DEPTH+1);
  typedef logic [SEQ_W-1:0] seq_t;

  issue_uop_t entry_q [0:DEPTH-1];
  seq_t       age_q   [0:DEPTH-1];
  logic [DEPTH-1:0] valid_q;
  seq_t next_age_q;

  logic [DEPTH-1:0] ready_entry;
  issue_uop_t effective_entry [0:DEPTH-1];
  issue_uop_t effective_enq_uop [0:WIDTH-1];
  logic [WIDTH-1:0] selected_valid;
  logic [WIDTH-1:0][$clog2(DEPTH)-1:0] selected_idx;
  logic [DEPTH-1:0] selected_mask;
  logic [DEPTH-1:0] recover_kill_mask;
  integer recover_kill_count;
  logic [WIDTH-1:0] issue_fire;
  logic [WIDTH-1:0] enq_fire;
  logic [COUNT_W-1:0] count_q;
  integer i;

  function automatic logic is_older(input seq_t a, input seq_t b);
    // Valid while fewer than 2^(SEQ_W-1) allocations separate live entries.
    is_older = $signed(a - b) < 0;
  endfunction

  function automatic logic is_younger(input seq_t a, input seq_t b);
    is_younger = $signed(a - b) > 0;
  endfunction

  always_comb begin : p_issue_select
    integer best;
    logic found;
    integer free_slots;

    ready_entry = '0;
    selected_mask = '0;
    recover_kill_mask = '0;
    recover_kill_count = 0;
    selected_valid = '0;
    selected_idx = '0;
    issue_valid = '0;
    issue_fire = '0;
    enq_ready = '0;
    enq_fire = '0;
    for (int p = 0; p < WIDTH; p++)
      effective_enq_uop[p] = enq_uop[p];
    ref_acquire_valid = '0;
    ref_acquire_tag = '0;
    ref_release_valid = '0;
    ref_release_tag = '0;
    occupancy = count_q;
    full = (count_q == COUNT_W'(DEPTH));
    empty = (count_q == '0);

    // Recovery removes only entries younger than the resolved branch.
    for (int e = 0; e < DEPTH; e++) begin
      if (valid_q[e] && is_younger(seq_t'(entry_q[e].seq_num), seq_t'(recover_seq))) begin
        recover_kill_mask[e] = 1'b1;
        recover_kill_count = recover_kill_count + 1;
      end
    end

    // Apply both completion buses before selection (same-cycle wakeup).
    for (int e = 0; e < DEPTH; e++) begin
      effective_entry[e] = entry_q[e];
      if (valid_q[e]) begin
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
        ready_entry[e] = effective_entry[e].src1_ready &&
                         effective_entry[e].src2_ready;
      end
    end

    // Select up to WIDTH oldest ready entries. The selected mask prevents
    // issuing one queue entry twice in the same cycle.
    for (int p = 0; p < WIDTH; p++) begin
      best = -1;
      found = 1'b0;
      for (int e = 0; e < DEPTH; e++) begin
        if (!flush && !recover_valid && valid_q[e] && !recover_kill_mask[e] &&
            ready_entry[e] && !selected_mask[e]) begin
          if (!found) begin
            best = e;
            found = 1'b1;
          end else if (is_older(age_q[e], age_q[best])) begin
            best = e;
          end
        end
      end
      if (found) begin
        selected_valid[p] = 1'b1;
        selected_idx[p] = $clog2(DEPTH)'(best);
        selected_mask[best] = 1'b1;
        // Grant-style internal issue interface: valid is asserted only when
        // the target execution port is ready, avoiding an unstable stalled
        // candidate while wakeups can change age priority.
        issue_valid[p] = issue_ready[p];
        issue_uop[p] = effective_entry[best];
        issue_uop[p].valid = issue_ready[p];
        issue_fire[p] = issue_valid[p];
      end else begin
        issue_uop[p] = '0;
      end
    end

    // Account for same-cycle issue when advertising enqueue capacity.
    // Enqueue only uses slots that were already free at cycle start. This
    // avoids same-cycle slot reuse ambiguity in the sequential allocator.
    free_slots = DEPTH - int'(count_q);
    for (int p = 0; p < WIDTH; p++) begin
      // Standard ready/valid contract: ready reports capacity independently
      // of valid. Younger lane is blocked if an older valid lane cannot fit.
      if (!flush && !recover_valid && free_slots > 0 &&
          ((p == 0) || !enq_valid[0] || enq_ready[0])) begin
        enq_ready[p] = 1'b1;
        enq_fire[p] = enq_valid[p];
        if (enq_valid[p])
          free_slots = free_slots - 1;
      end
    end

    // Capture a completion that coincides with enqueue. Without this path,
    // the new entry is not yet valid_q during the wakeup loop above, so the
    // broadcast would be lost and its just-acquired reference would leak.
    for (int p = 0; p < WIDTH; p++) begin
      if (enq_valid[p] && enq_ready[p] && !flush && !recover_valid) begin
        for (int w = 0; w < WAKEUP_WIDTH; w++) begin
          if (wakeup_valid[w]) begin
            if (!effective_enq_uop[p].src1_ready &&
                effective_enq_uop[p].src1_tag == wakeup_tag[w]) begin
              effective_enq_uop[p].src1_ready = 1'b1;
              effective_enq_uop[p].src1_value = wakeup_data[w];
            end
            if (!effective_enq_uop[p].src2_ready &&
                effective_enq_uop[p].src2_tag == wakeup_tag[w]) begin
              effective_enq_uop[p].src2_ready = 1'b1;
              effective_enq_uop[p].src2_value = wakeup_data[w];
            end
          end
        end
      end
    end


    // Retain unresolved source tags while their queue entries are resident.
    for (int p = 0; p < WIDTH; p++) begin
      if (enq_fire[p]) begin
        if (!effective_enq_uop[p].src1_ready) begin
          ref_acquire_valid[2*p] = 1'b1;
          ref_acquire_tag[2*p] = effective_enq_uop[p].src1_tag;
        end
        if (!effective_enq_uop[p].src2_ready) begin
          ref_acquire_valid[2*p+1] = 1'b1;
          ref_acquire_tag[2*p+1] = effective_enq_uop[p].src2_tag;
        end
      end
    end

    // Release references when a pending operand wakes, or when its queue
    // entry is discarded by flush/recovery. A recovery-killed entry is not
    // also counted as a wakeup release in the same cycle.
    for (int e = 0; e < DEPTH; e++) begin
      if (valid_q[e]) begin
        if (flush || (recover_valid && recover_kill_mask[e])) begin
          if (!entry_q[e].src1_ready) begin
            ref_release_valid[2*e] = 1'b1;
            ref_release_tag[2*e] = entry_q[e].src1_tag;
          end
          if (!entry_q[e].src2_ready) begin
            ref_release_valid[2*e+1] = 1'b1;
            ref_release_tag[2*e+1] = entry_q[e].src2_tag;
          end
        end else begin
          for (int w = 0; w < WAKEUP_WIDTH; w++) begin
            if (wakeup_valid[w]) begin
              if (!entry_q[e].src1_ready && entry_q[e].src1_tag == wakeup_tag[w]) begin
                ref_release_valid[2*e] = 1'b1;
                ref_release_tag[2*e] = entry_q[e].src1_tag;
              end
              if (!entry_q[e].src2_ready && entry_q[e].src2_tag == wakeup_tag[w]) begin
                ref_release_valid[2*e+1] = 1'b1;
                ref_release_tag[2*e+1] = entry_q[e].src2_tag;
              end
            end
          end
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : p_issue_state
    integer write_slot;
    logic [DEPTH-1:0] alloc_mask;
    seq_t age_alloc;
    if (!rst_n) begin
      valid_q <= '0;
      count_q <= '0;
      next_age_q <= '0;
      for (i = 0; i < DEPTH; i++) begin
        entry_q[i] <= '0;
        age_q[i] <= '0;
      end
    end else if (flush) begin
      valid_q <= '0;
      count_q <= '0;
      // Do not reset the age counter on a full pipeline flush.
    end else if (recover_valid) begin
      for (int e = 0; e < DEPTH; e++) begin
        if (recover_kill_mask[e]) begin
          valid_q[e] <= 1'b0;
        end else if (valid_q[e]) begin
          // Preserve same-cycle wakeups for surviving older entries while
          // the younger wrong-path entries are selectively discarded.
          entry_q[e] <= effective_entry[e];
        end
      end
      count_q <= count_q - COUNT_W'(recover_kill_count);
    end else begin
      alloc_mask = valid_q;
      age_alloc = next_age_q;
      for (int p = 0; p < WIDTH; p++) begin
        if (issue_fire[p]) begin
          valid_q[selected_idx[p]] <= 1'b0;
        end
      end

      // Allocate accepted entries into distinct slots that were free at the
      // start of the cycle. Issued slots become reusable next cycle.
      for (int p = 0; p < WIDTH; p++) begin
        if (enq_fire[p]) begin
          write_slot = -1;
          for (int s = 0; s < DEPTH; s++) begin
            if (!alloc_mask[s] && write_slot == -1)
              write_slot = s;
          end
          if (write_slot >= 0) begin
            entry_q[write_slot] <= effective_enq_uop[p];
            entry_q[write_slot].valid <= 1'b1;
            age_q[write_slot] <= age_alloc;
            valid_q[write_slot] <= 1'b1;
            alloc_mask[write_slot] = 1'b1;
            age_alloc = age_alloc + 1'b1;
          end
        end
      end
      next_age_q <= age_alloc;

      case ({(enq_fire[0] | ((WIDTH > 1) && enq_fire[1])),
             (issue_fire[0] | ((WIDTH > 1) && issue_fire[1]))})
        2'b10: count_q <= count_q + COUNT_W'(enq_fire[0]) +
                                      ((WIDTH > 1) ? COUNT_W'(enq_fire[1]) : COUNT_W'(0));
        2'b01: count_q <= count_q - COUNT_W'(issue_fire[0]) -
                                      ((WIDTH > 1) ? COUNT_W'(issue_fire[1]) : COUNT_W'(0));
        2'b11: count_q <= count_q + COUNT_W'(enq_fire[0]) +
                                      ((WIDTH > 1) ? COUNT_W'(enq_fire[1]) : COUNT_W'(0)) -
                                      COUNT_W'(issue_fire[0]) -
                                      ((WIDTH > 1) ? COUNT_W'(issue_fire[1]) : COUNT_W'(0));
        default: count_q <= count_q;
      endcase
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (SEQ_W != 32) $error("Issue queue sequence width must match issue_uop_t.seq_num");
    if (WIDTH != 2) $error("Initial issue_queue implementation requires WIDTH=2");
  end
`endif
endmodule
