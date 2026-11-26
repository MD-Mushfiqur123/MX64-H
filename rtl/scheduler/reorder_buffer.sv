module reorder_buffer #(
  parameter int DEPTH = 48,
  parameter int WIDTH = 2,
  parameter int COMPLETE_WIDTH = WIDTH,
  parameter int TAG_W = $clog2(DEPTH),
  parameter int GEN_W = 16,
  parameter int FULL_TAG_W = TAG_W + GEN_W
) (
  input logic clk,
  input logic rst_n,
  input logic flush,
  input logic tag_query_valid,
  input logic [FULL_TAG_W-1:0] tag_query_tag,
  output logic tag_query_found,
  input logic recover_valid,
  input logic [FULL_TAG_W-1:0] recover_tag,
  output logic recover_found,

  input logic [WIDTH-1:0] alloc_valid,
  output logic [WIDTH-1:0] alloc_ready,
  output logic [WIDTH-1:0][FULL_TAG_W-1:0] alloc_tag,
  input logic [WIDTH-1:0][63:0] alloc_pc,
  input logic [WIDTH-1:0][4:0] alloc_rd,
  input logic [WIDTH-1:0][6:0] alloc_kind,
  input logic [WIDTH-1:0][6:0] alloc_prd,
  input logic [WIDTH-1:0][6:0] alloc_old_prd,
  input logic [WIDTH-1:0] alloc_exception,
  input logic [WIDTH-1:0][3:0] alloc_exception_code,
  input logic [WIDTH-1:0][63:0] alloc_exception_value,

  input logic [COMPLETE_WIDTH-1:0] complete_valid,
  input logic [COMPLETE_WIDTH-1:0][FULL_TAG_W-1:0] complete_tag,
  input logic [COMPLETE_WIDTH-1:0][63:0] complete_value,
  input logic [COMPLETE_WIDTH-1:0] complete_exception,
  input logic [COMPLETE_WIDTH-1:0][3:0] complete_exception_code,
  input logic [COMPLETE_WIDTH-1:0][63:0] complete_exception_value,

  output logic [WIDTH-1:0] retire_valid,
  input logic [WIDTH-1:0] retire_ready,
  output logic [WIDTH-1:0][FULL_TAG_W-1:0] retire_tag,
  output logic [WIDTH-1:0][63:0] retire_pc,
  output logic [WIDTH-1:0][4:0] retire_rd,
  output logic [WIDTH-1:0][6:0] retire_kind,
  output logic [WIDTH-1:0][6:0] retire_prd,
  output logic [WIDTH-1:0][6:0] retire_old_prd,
  output logic [WIDTH-1:0][63:0] retire_value,
  output logic [WIDTH-1:0] retire_exception,
  output logic [WIDTH-1:0][3:0] retire_exception_code,
  output logic [WIDTH-1:0][63:0] retire_exception_value,

  output logic full,
  output logic empty,
  output logic [$clog2(DEPTH+1)-1:0] occupancy
);
  logic [DEPTH-1:0] valid_q, done_q, exception_q;
  logic [DEPTH-1:0][GEN_W-1:0] generation_q;
  logic [DEPTH-1:0][3:0] exception_code_q;
  logic [DEPTH-1:0][63:0] exception_value_q;
  logic [DEPTH-1:0][63:0] pc_q;
  logic [DEPTH-1:0][4:0] rd_q;
  logic [DEPTH-1:0][6:0] kind_q;
  logic [DEPTH-1:0][6:0] prd_q;
  logic [DEPTH-1:0][6:0] old_prd_q;
  logic [DEPTH-1:0][63:0] value_q;
  logic [TAG_W-1:0] head_q, tail_q;
  logic [TAG_W:0] count_q;
  logic [TAG_W-1:0] alloc_idx [0:WIDTH-1];
  logic [WIDTH-1:0] alloc_fire, retire_fire;
  integer alloc_count, retire_count;
  logic [TAG_W:0] count_next;
  logic [TAG_W-1:0] recover_slot;
  logic [TAG_W:0] recover_keep_count;
  integer recover_position;
  integer i;

  function automatic logic [TAG_W-1:0] bump(input logic [TAG_W-1:0] ptr);
    if (ptr == TAG_W'(DEPTH-1)) bump = '0;
    else bump = ptr + 1'b1;
  endfunction

  always_comb begin
    full = (count_q == DEPTH);
    empty = (count_q == 0);
    occupancy = count_q;
    alloc_ready = '0;
    alloc_tag = '0;
    tag_query_found = 1'b0;
    recover_found = 1'b0;
    recover_slot = head_q;
    recover_keep_count = '0;
    recover_position = -1;

    // Full-tag lookup is independent from the recovery handshake so a branch
    // resolver can verify that its ROB entry is still live before restoring.
    begin : p_tag_query
      logic [TAG_W-1:0] query_slot;
      query_slot = head_q;
      for (int age = 0; age < DEPTH; age++) begin
        if (tag_query_valid && age < count_q && valid_q[query_slot] &&
            generation_q[query_slot] == tag_query_tag[FULL_TAG_W-1:TAG_W] &&
            query_slot == tag_query_tag[TAG_W-1:0])
          tag_query_found = 1'b1;
        query_slot = bump(query_slot);
      end
    end
    begin : p_recover_lookup
      logic [TAG_W-1:0] scan_slot;
      scan_slot = head_q;
      for (int age = 0; age < DEPTH; age++) begin
        if (recover_valid && age < count_q && valid_q[scan_slot] &&
            generation_q[scan_slot] == recover_tag[FULL_TAG_W-1:TAG_W] &&
            scan_slot == recover_tag[TAG_W-1:0]) begin
          recover_found = 1'b1;
          recover_slot = scan_slot;
          recover_position = age;
          recover_keep_count = (TAG_W+1)'(age + 1);
        end
        scan_slot = bump(scan_slot);
      end
    end
    alloc_idx = '{default:'0};
    alloc_fire = '0;
    alloc_count = 0;
    retire_count = 0;
    count_next = count_q;
    retire_valid = '0;
    retire_tag = '0;
    retire_pc = '0;
    retire_rd = '0;
    retire_kind = '0;
    retire_prd = '0;
    retire_old_prd = '0;
    retire_value = '0;
    retire_exception = '0;
    retire_exception_code = '0;
    retire_exception_value = '0;
    retire_fire = '0;

    // Conservative allocation: do not reuse slots being retired this cycle.
    for (int lane = 0; lane < WIDTH; lane++) begin
      if (!recover_valid && alloc_valid[lane] &&
          ((lane == 0) || !alloc_valid[0] || alloc_fire[0]) &&
          (count_q + ((lane != 0 && alloc_fire[0]) ? 1 : 0) < DEPTH)) begin
        alloc_ready[lane] = 1'b1;
        alloc_idx[lane] = ((lane == 0) || !alloc_fire[0]) ? tail_q : bump(tail_q);
        alloc_tag[lane] = {generation_q[alloc_idx[lane]] + GEN_W'(1), alloc_idx[lane]};
        alloc_fire[lane] = 1'b1;
        alloc_count = alloc_count + 1;
      end
    end

    // Only the oldest completed entries may retire; second retirement depends
    // on the first slot also being valid, done and accepted.
    if (!recover_valid && count_q != 0 && valid_q[head_q] && done_q[head_q]) begin
      retire_valid[0] = 1'b1;
      retire_tag[0] = {generation_q[head_q], head_q};
      retire_pc[0] = pc_q[head_q];
      retire_rd[0] = rd_q[head_q];
      retire_kind[0] = kind_q[head_q];
      retire_prd[0] = prd_q[head_q];
      retire_old_prd[0] = old_prd_q[head_q];
      retire_value[0] = value_q[head_q];
      retire_exception[0] = exception_q[head_q];
      retire_exception_code[0] = exception_code_q[head_q];
      retire_exception_value[0] = exception_value_q[head_q];
      retire_fire[0] = retire_ready[0];
      if (retire_fire[0]) retire_count = retire_count + 1;
    end
    // A head exception is a precise architectural boundary: retire the
    // faulting instruction alone. No younger instruction may retire beside it.
    if (!recover_valid && WIDTH > 1 && count_q > 1 && retire_fire[0] &&
        !exception_q[head_q]) begin
      if (valid_q[bump(head_q)] && done_q[bump(head_q)]) begin
        retire_valid[1] = 1'b1;
        retire_tag[1] = {generation_q[bump(head_q)], bump(head_q)};
        retire_pc[1] = pc_q[bump(head_q)];
        retire_rd[1] = rd_q[bump(head_q)];
        retire_kind[1] = kind_q[bump(head_q)];
        retire_prd[1] = prd_q[bump(head_q)];
        retire_old_prd[1] = old_prd_q[bump(head_q)];
        retire_value[1] = value_q[bump(head_q)];
        retire_exception[1] = exception_q[bump(head_q)];
        retire_exception_code[1] = exception_code_q[bump(head_q)];
        retire_exception_value[1] = exception_value_q[bump(head_q)];
        retire_fire[1] = retire_ready[1];
        if (retire_fire[1]) retire_count = retire_count + 1;
      end
    end
    count_next = count_q + (TAG_W+1)'(alloc_count) - (TAG_W+1)'(retire_count);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      done_q <= '0;
      exception_q <= '0;
      generation_q <= '0;
      head_q <= '0;
      tail_q <= '0;
      count_q <= '0;
      for (i=0; i<DEPTH; i++) begin
        pc_q[i] <= '0;
        rd_q[i] <= '0;
        kind_q[i] <= '0;
        prd_q[i] <= '0;
        old_prd_q[i] <= '0;
        value_q[i] = '0;
        exception_code_q[i] <= '0;
        exception_value_q[i] = '0;
      end
    end else if (flush) begin
      valid_q <= '0;
      done_q <= '0;
      exception_q <= '0;
      head_q <= '0;
      tail_q <= '0;
      count_q <= '0;
      for (i=0; i<DEPTH; i++)
        generation_q[i] <= generation_q[i] + GEN_W'(1);
    end else if (recover_valid) begin
      // Freeze allocation/retirement for the recovery cycle. Preserve every
      // older entry and the resolved branch; invalidate only younger entries.
      if (recover_found) begin
        // Completions for surviving older entries and the branch itself remain valid.
        for (int c=0; c<COMPLETE_WIDTH; c++) begin
          if (complete_valid[c]) begin
            for (int s=0; s<DEPTH; s++) begin
              if (valid_q[s] &&
                  complete_tag[c][TAG_W-1:0] == TAG_W'(s) &&
                  complete_tag[c][FULL_TAG_W-1:TAG_W] == generation_q[s]) begin
                done_q[s] <= 1'b1;
                value_q[s] = complete_value[c];
                exception_q[s] <= complete_exception[c];
                exception_code_q[s] <= complete_exception[c] ? complete_exception_code[c] : 4'd0;
                exception_value_q[s] = complete_exception[c] ? complete_exception_value[c] : 64'd0;
              end
            end
          end
        end
        begin : p_kill_younger
          logic [TAG_W-1:0] scan_slot;
          scan_slot = head_q;
          for (int age = 0; age < DEPTH; age++) begin
            if (age < count_q && age > recover_position) begin
              valid_q[scan_slot] <= 1'b0;
              done_q[scan_slot] <= 1'b0;
              exception_q[scan_slot] <= 1'b0;
              generation_q[scan_slot] <= generation_q[scan_slot] + GEN_W'(1);
            end
            scan_slot = bump(scan_slot);
          end
        end
        tail_q <= bump(recover_slot);
        count_q <= recover_keep_count;
      end
      // If the tag is stale, hold state and report recover_found=0. A controller
      // must surface this as a recovery protocol error rather than guessing.
    end else begin
      // Completion matches slot index and the full epoch field to reject stale results.
      // Epoch wraps after 2**GEN_W allocations per slot; long-latency units must
      // still cancel pre-flush requests or use a wider externally agreed tag.
      for (int c=0; c<COMPLETE_WIDTH; c++) begin
        if (complete_valid[c]) begin
          for (int s=0; s<DEPTH; s++) begin
            if (valid_q[s] &&
                complete_tag[c][TAG_W-1:0] == TAG_W'(s) &&
                complete_tag[c][FULL_TAG_W-1:TAG_W] == generation_q[s]) begin
              done_q[s] <= 1'b1;
              value_q[s] = complete_value[c];
              exception_q[s] <= complete_exception[c];
              exception_code_q[s] <= complete_exception[c] ? complete_exception_code[c] : 4'd0;
              exception_value_q[s] = complete_exception[c] ? complete_exception_value[c] : 64'd0;
            end
          end
        end
      end

      for (int a=0; a<WIDTH; a++) begin
        if (alloc_fire[a]) begin
          valid_q[alloc_idx[a]] <= 1'b1;
          done_q[alloc_idx[a]] <= alloc_exception[a];
          exception_q[alloc_idx[a]] <= alloc_exception[a];
          exception_code_q[alloc_idx[a]] <= alloc_exception[a] ? alloc_exception_code[a] : 4'd0;
          exception_value_q[alloc_idx[a]] <= alloc_exception[a] ? alloc_exception_value[a] : 64'd0;
          pc_q[alloc_idx[a]] <= alloc_pc[a];
          rd_q[alloc_idx[a]] <= alloc_rd[a];
          kind_q[alloc_idx[a]] <= alloc_kind[a];
          prd_q[alloc_idx[a]] <= alloc_prd[a];
          old_prd_q[alloc_idx[a]] <= alloc_old_prd[a];
          value_q[alloc_idx[a]] <= '0;
          generation_q[alloc_idx[a]] <= generation_q[alloc_idx[a]] + GEN_W'(1);
        end
      end

      if (retire_fire[0]) begin
        valid_q[head_q] <= 1'b0;
        done_q[head_q] <= 1'b0;
      end
      if (retire_fire[1]) begin
        valid_q[bump(head_q)] <= 1'b0;
        done_q[bump(head_q)] <= 1'b0;
      end

      count_q <= count_next;

      if (retire_fire[0]) head_q <= bump(head_q);
      if (retire_fire[1]) head_q <= bump(bump(head_q));
      if (alloc_fire[1]) tail_q <= bump(bump(tail_q));
      else if (alloc_fire[0]) tail_q <= bump(tail_q);
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (DEPTH < 4) $error("ROB DEPTH must be >= 4");
    if (GEN_W < 16) $error("ROB generation field must be at least 16 bits");
    if (WIDTH != 2) $error("Initial ROB implementation requires WIDTH=2");
    if (FULL_TAG_W != TAG_W + GEN_W) $error("ROB full tag width mismatch");
  end
`endif
endmodule
