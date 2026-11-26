// MX64-H Phase 37.2: memory-issue to LSU/cache transaction adapter.
//
// The adapter retains full ROB identity and physical destination metadata for
// every accepted load. Stores are retained until in-order ROB retirement
// authorizes the matching LSU store-queue entry to become externally visible.
// Address translation is intentionally external: req_paddr is supplied for
// the currently presented memory UOP and must correspond to req_vaddr.
module mx64_lsu_rob_adapter #(
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

  input logic issue_valid,
  output logic issue_ready,
  input mx64_pkg::issue_uop_t issue_uop,
  input logic [PADDR_W-1:0] issue_paddr,

  // ROB retirement candidate. retire_kind[3] is the store bit used by the
  // current dispatch-controller ROB kind encoding.
  input logic [1:0] retire_valid,
  input logic [1:0][mx64_pkg::ROB_TAG_W-1:0] retire_tag,
  input logic [1:0][6:0] retire_kind,
  output logic [1:0] retire_store_ready,

  // Single-cycle memory completion lane into the ROB.
  output logic memory_complete_valid,
  output logic [mx64_pkg::ROB_TAG_W-1:0] memory_complete_tag,
  output logic [63:0] memory_complete_value,
  output logic memory_complete_exception,
  output logic [3:0] memory_complete_exception_code,
  output logic [63:0] memory_complete_exception_value,

  // Successful load writeback. It is asserted with matching ROB completion.
  output logic memory_wb_valid,
  output logic [PHYS_W-1:0] memory_wb_tag,
  output logic [63:0] memory_wb_data,

  // Post-retirement committed-store failure is not a precise ROB exception.
  output logic committed_store_error_valid,
  output logic [mx64_pkg::ROB_TAG_W-1:0] committed_store_error_tag,
  output logic [PADDR_W-1:0] committed_store_error_paddr,

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

  output logic [SLOT_W:0] live_loads,
  output logic [SLOT_W:0] live_stores,

  // Physical-register lifetime events mirrored to the core-wide reference tracker.
  output logic ref_load_alloc_valid,
  output logic [PHYS_W-1:0] ref_load_base_tag,
  output logic ref_load_done_valid,
  output logic [SLOT_W-1:0] ref_load_done_slot,
  output logic ref_store_alloc_valid,
  output logic [PHYS_W-1:0] ref_store_base_tag,
  output logic [PHYS_W-1:0] ref_store_data_tag,
  output logic [SEQ_W-1:0] ref_store_alloc_seq,
  output logic ref_store_done_valid,
  output logic [SLOT_W-1:0] ref_store_done_slot
);
  import mx64_pkg::*;

  localparam int COUNT_W = $clog2(LSU_DEPTH+1);
  logic req_is_store, req_signed;
  logic [2:0] req_size_log2;
  logic [63:0] req_immediate;
  logic [63:0] req_store_data;
  logic req_fault_valid, req_ready;
  logic subsystem_fault_valid;
  logic [63:0] req_effective_addr, subsystem_effective_addr;
  logic [7:0] req_byte_mask, subsystem_byte_mask;
  logic load_order_blocked;
  logic [7:0] load_forward_mask;
  logic [63:0] load_forward_data;
  logic load_forward_complete;
  logic [SLOT_W-1:0] accepted_lifecycle_slot, accepted_store_order_slot;

  logic load_done_valid, store_done_valid;
  logic [SLOT_W-1:0] load_done_slot, store_done_slot;
  logic load_replay_valid, store_replay_valid;
  logic [SLOT_W-1:0] load_replay_slot, store_replay_slot;
  logic store_commit_valid, store_commit_ready;
  logic [SLOT_W-1:0] store_commit_order_slot, store_commit_lifecycle_slot;
  logic [PADDR_W-1:0] store_commit_paddr;
  logic [63:0] store_commit_data;
  logic [7:0] store_commit_byte_enable;
  logic [1:0] store_commit_size;
  logic cache_rsp_valid, cache_rsp_ready, cache_rsp_is_store, cache_rsp_error;
  logic [SLOT_W-1:0] cache_rsp_lifecycle_slot;
  logic [63:0] cache_rsp_rdata;
  logic store_error_valid, store_error_ready;
  logic [SLOT_W-1:0] store_error_lifecycle_slot;

  logic [LSU_DEPTH-1:0] load_valid_q, load_killed_q, store_valid_q, store_committed_q;
  logic [LSU_DEPTH-1:0] recover_store_mask;
  logic [LSU_DEPTH-1:0][ROB_TAG_W-1:0] load_rob_tag_q, store_rob_tag_q;
  logic [LSU_DEPTH-1:0][PHYS_W-1:0] load_dst_tag_q;
  logic [LSU_DEPTH-1:0][63:0] load_vaddr_q;
  logic [LSU_DEPTH-1:0][SEQ_W-1:0] load_seq_q, store_seq_q;
  logic [LSU_DEPTH-1:0] load_writes_dst_q;
  logic [LSU_DEPTH-1:0][PADDR_W-1:0] store_paddr_q;
  logic [LSU_DEPTH-1:0][63:0] store_data_q;
  logic [LSU_DEPTH-1:0][7:0] store_be_q;
  logic [LSU_DEPTH-1:0][1:0] store_size_q;
  logic [LSU_DEPTH-1:0][SLOT_W-1:0] store_order_slot_q;
  logic [COUNT_W-1:0] load_count_q, store_count_q;
  logic store_match0, store_match1;
  logic [SLOT_W-1:0] store_match_slot0, store_match_slot1;
  logic issue_decode_valid;
  logic [3:0] opcode_major, opcode_minor;
  logic [3:0] completion_code;

  function automatic logic seq_younger(input logic [SEQ_W-1:0] a, input logic [SEQ_W-1:0] b);
    seq_younger = $signed(a - b) > 0;
  endfunction

  // MXISA-64 draft opcode mapping from MXISA64_OPCODE_TABLE.csv.
  // Loads: major 0x06, minor 0..6 = LB,LBU,LH,LHU,LW,LWU,LD.
  // Stores: major 0x07, minor 0..3 = SB,SH,SW,SD.
  always_comb begin
    opcode_major = issue_uop.instruction[31:26];
    opcode_minor = issue_uop.instruction[15:12];
    req_is_store = issue_uop.is_store;
    req_signed = 1'b0;
    req_size_log2 = 3'd0;
    req_immediate = issue_uop.immediate;
    req_store_data = issue_uop.src2_value;
    issue_decode_valid = 1'b0;
    if (issue_uop.is_load && opcode_major == 6'h06) begin
      issue_decode_valid = 1'b1;
      case (opcode_minor)
        4'd0: begin req_size_log2=3'd0; req_signed=1'b1; end // LB
        4'd1: begin req_size_log2=3'd0; req_signed=1'b0; end // LBU
        4'd2: begin req_size_log2=3'd1; req_signed=1'b1; end // LH
        4'd3: begin req_size_log2=3'd1; req_signed=1'b0; end // LHU
        4'd4: begin req_size_log2=3'd2; req_signed=1'b1; end // LW
        4'd5: begin req_size_log2=3'd2; req_signed=1'b0; end // LWU
        4'd6: begin req_size_log2=3'd3; req_signed=1'b0; end // LD
        default: issue_decode_valid=1'b0;
      endcase
    end else if (issue_uop.is_store && opcode_major == 6'h07) begin
      issue_decode_valid = 1'b1;
      case (opcode_minor)
        4'd0: req_size_log2=3'd0; // SB
        4'd1: req_size_log2=3'd1; // SH
        4'd2: req_size_log2=3'd2; // SW
        4'd3: req_size_log2=3'd3; // SD
        default: issue_decode_valid=1'b0;
      endcase
    end
  end

  // Precheck alignment independently of cache readiness. A malformed/misaligned
  // operation must trap even while the blocking cache port is occupied.
  assign req_effective_addr = issue_uop.src1_value + req_immediate;
  assign req_fault_valid = issue_valid && issue_decode_valid &&
      ((req_effective_addr & ((64'd1 << req_size_log2) - 64'd1)) != 64'd0);
  assign req_byte_mask = subsystem_byte_mask;

  // This initial adapter accepts one UOP at a time. A malformed/reserved
  // memory encoding is completed as an illegal instruction without touching LSU.
  assign issue_ready = issue_valid && !recover_valid && !cache_rsp_valid && !store_commit_valid &&
                       !(|store_committed_q) &&
                       (!issue_decode_valid || req_fault_valid || req_ready);
  assign load_replay_valid = 1'b0;
  assign load_replay_slot = '0;
  assign store_replay_valid = 1'b0;
  assign store_replay_slot = '0;
  assign load_done_valid = cache_rsp_valid && cache_rsp_ready &&
                           !cache_rsp_is_store;
  assign load_done_slot = cache_rsp_lifecycle_slot;
  assign store_done_valid = cache_rsp_valid && cache_rsp_ready &&
                            cache_rsp_is_store;
  assign store_done_slot = cache_rsp_lifecycle_slot;
  assign store_error_ready = 1'b1;
  assign cache_rsp_ready = 1'b1;
  assign committed_store_error_valid = store_error_valid;
  assign committed_store_error_tag = store_rob_tag_q[store_error_lifecycle_slot];
  assign committed_store_error_paddr = store_paddr_q[store_error_lifecycle_slot];

  // Find a retiring store by full ROB tag. Slot identity is not enough because
  // the ROB slot is reused with a new generation.
  always_comb begin
    recover_store_mask = '0;
    for (int r=0; r<LSU_DEPTH; r++) recover_store_mask[r] = seq_younger(store_seq_q[r], recover_seq);
    store_match0 = 1'b0;
    store_match1 = 1'b0;
    store_match_slot0 = '0;
    store_match_slot1 = '0;
    for (int s=0; s<LSU_DEPTH; s++) begin
      if (store_valid_q[s] && store_rob_tag_q[s] == retire_tag[0]) begin
        store_match0 = 1'b1;
        store_match_slot0 = SLOT_W'(s);
      end
      if (store_valid_q[s] && store_rob_tag_q[s] == retire_tag[1]) begin
        store_match1 = 1'b1;
        store_match_slot1 = SLOT_W'(s);
      end
    end
    retire_store_ready = '1;
    store_commit_valid = 1'b0;
    store_commit_order_slot = '0;
    store_commit_lifecycle_slot = '0;
    store_commit_paddr = '0;
    store_commit_data = '0;
    store_commit_byte_enable = '0;
    store_commit_size = '0;
    if (retire_valid[0] && retire_kind[0][3]) begin
      retire_store_ready[0] = store_match0 && store_commit_ready;
      if (store_match0) begin
        store_commit_valid = 1'b1;
        store_commit_order_slot = store_order_slot_q[store_match_slot0];
        store_commit_lifecycle_slot = store_match_slot0;
        store_commit_paddr = store_paddr_q[store_match_slot0];
        store_commit_data = store_data_q[store_match_slot0];
        store_commit_byte_enable = store_be_q[store_match_slot0];
        store_commit_size = store_size_q[store_match_slot0];
      end
    end
    // The current LSU has one store-commit port. Never retire a second-lane
    // store until it becomes lane 0 and can own that port.
    if (retire_valid[1] && retire_kind[1][3])
      retire_store_ready[1] = 1'b0;
    if (recover_valid) begin
      retire_store_ready = '0;
      store_commit_valid = 1'b0;
    end
  end

  mx64_lsu_cache_subsystem #(
    .LSU_DEPTH(LSU_DEPTH), .PADDR_W(PADDR_W), .ADDR_W(ADDR_W),
    .DATA_W(DATA_W), .SEQ_W(SEQ_W), .PHYS_W(PHYS_W),
    .SLOT_W(SLOT_W), .LINE_BYTES(LINE_BYTES), .CACHE_SETS(CACHE_SETS)
  ) u_lsu_cache_subsystem (
    .clk, .rst_n, .flush_all, .recover_valid, .recover_seq,
    .req_valid(issue_valid && !recover_valid && issue_decode_valid && !req_fault_valid),
    .req_ready, .req_is_store, .req_base_value(issue_uop.src1_value),
    .req_immediate, .req_size_log2, .req_signed, .req_seq(issue_uop.seq_num),
    .req_store_data, .req_base_phys_tag(issue_uop.src1_tag),
    .req_store_data_phys_tag(issue_uop.src2_tag), .req_paddr(issue_paddr),
    .req_fault_valid(subsystem_fault_valid), .req_effective_addr(subsystem_effective_addr), .req_byte_mask(subsystem_byte_mask),
    .load_order_blocked, .load_forward_mask, .load_forward_data,
    .load_forward_complete, .accepted_lifecycle_slot, .accepted_store_order_slot,
    .load_done_valid, .load_done_slot, .load_replay_valid, .load_replay_slot,
    .store_done_valid, .store_done_slot, .store_replay_valid, .store_replay_slot,
    .store_commit_valid, .store_commit_ready, .store_commit_order_slot,
    .store_commit_lifecycle_slot, .store_commit_paddr, .store_commit_data,
    .store_commit_byte_enable, .store_commit_size,
    .cache_rsp_valid, .cache_rsp_ready, .cache_rsp_is_store,
    .cache_rsp_lifecycle_slot, .cache_rsp_rdata, .cache_rsp_error,
    .store_error_valid, .store_error_ready, .store_error_lifecycle_slot,
    .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
    .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid, .mem_rsp_ready,
    .mem_rsp_rdata, .mem_rsp_error, .invalidate_all,
    .ref_acquire_valid(), .ref_acquire_tag(), .ref_release_valid(),
    .ref_release_tag(), .outstanding_lsu_refs(), .store_order_occupancy()
  );

  // Current single-outstanding cache contract. The response slot is stable
  // until consumed; load metadata is looked up by lifecycle slot and checked
  // against its valid bit before producing a completion.
  always_comb begin
    memory_complete_valid = 1'b0;
    memory_complete_tag = '0;
    memory_complete_value = '0;
    memory_complete_exception = 1'b0;
    memory_complete_exception_code = '0;
    memory_complete_exception_value = '0;
    memory_wb_valid = 1'b0;
    memory_wb_tag = '0;
    memory_wb_data = '0;
    if (cache_rsp_valid && !cache_rsp_is_store) begin
      memory_complete_valid = load_valid_q[cache_rsp_lifecycle_slot] && !load_killed_q[cache_rsp_lifecycle_slot];
      memory_complete_tag = load_rob_tag_q[cache_rsp_lifecycle_slot];
      memory_complete_value = cache_rsp_rdata;
      memory_complete_exception = cache_rsp_error;
      memory_complete_exception_code = cache_rsp_error ? EXC_LOAD_FAULT : EXC_NONE;
      memory_complete_exception_value = cache_rsp_error ? load_vaddr_q[cache_rsp_lifecycle_slot] : 64'd0;
      memory_wb_valid = memory_complete_valid && !cache_rsp_error &&
                        load_writes_dst_q[cache_rsp_lifecycle_slot];
      memory_wb_tag = load_dst_tag_q[cache_rsp_lifecycle_slot];
      memory_wb_data = cache_rsp_rdata;
    end
    // Accepted stores become ROB-complete while remaining buffered until retirement.
    if (issue_valid && issue_ready && issue_decode_valid && req_is_store && !req_fault_valid) begin
      memory_complete_valid = 1'b1;
      memory_complete_tag = issue_uop.rob_tag;
      memory_complete_value = '0;
    end
    // Address-generation faults are reported directly against the issuing UOP.
    if (issue_valid && issue_ready && issue_decode_valid && req_fault_valid) begin
      memory_complete_valid = 1'b1;
      memory_complete_tag = issue_uop.rob_tag;
      memory_complete_value = '0;
      memory_complete_exception = 1'b1;
      memory_complete_exception_code = req_is_store ? EXC_STORE_MISALIGNED : EXC_LOAD_MISALIGNED;
      memory_complete_exception_value = req_effective_addr;
      memory_wb_valid = 1'b0;
    end
    if (issue_valid && issue_ready && !issue_decode_valid) begin
      memory_complete_valid = 1'b1;
      memory_complete_tag = issue_uop.rob_tag;
      memory_complete_exception = 1'b1;
      memory_complete_exception_code = EXC_ILLEGAL;
      memory_complete_exception_value = {32'd0, issue_uop.instruction};
      memory_wb_valid = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_valid_q <= '0;
      load_killed_q <= '0;
      store_valid_q <= '0;
      store_committed_q <= '0;
      load_count_q <= '0;
      store_count_q <= '0;
      for (int s=0; s<LSU_DEPTH; s++) begin
        load_rob_tag_q[s] <= '0;
        load_dst_tag_q[s] <= '0;
        load_vaddr_q[s] <= '0;
        load_seq_q[s] <= '0; store_seq_q[s] <= '0;
        load_writes_dst_q[s] <= 1'b0;
        store_rob_tag_q[s] <= '0;
        store_paddr_q[s] <= '0;
        store_data_q[s] <= '0;
        store_be_q[s] <= '0;
        store_size_q[s] <= '0;
        store_order_slot_q[s] <= '0;
      end
    end else if (flush_all) begin
      // A cache transaction already accepted cannot be canceled at this
      // boundary. Retain its slot identity, but suppress stale ROB completion.
      load_killed_q <= load_killed_q | load_valid_q;
      // A store already authorized at ROB retirement is irrevocable. Preserve
      // its response identity across younger speculative flushes.
      store_valid_q <= store_valid_q & store_committed_q;
      store_committed_q <= store_committed_q;
      load_count_q <= COUNT_W'($countones(load_valid_q));
      store_count_q <= COUNT_W'($countones(store_valid_q & store_committed_q));
    end else if (recover_valid) begin
      for (int s=0; s<LSU_DEPTH; s++) begin
        if (load_valid_q[s] && seq_younger(load_seq_q[s], recover_seq)) load_killed_q[s] <= 1'b1;
        if (store_valid_q[s] && !store_committed_q[s] && seq_younger(store_seq_q[s], recover_seq)) begin
          store_valid_q[s] <= 1'b0;
          store_committed_q[s] <= 1'b0;
        end
      end
      store_count_q <= store_count_q
        - COUNT_W'($countones(store_valid_q & ~store_committed_q & recover_store_mask))
        - COUNT_W'(cache_rsp_valid && cache_rsp_ready && cache_rsp_is_store);
      if (cache_rsp_valid && cache_rsp_ready && !cache_rsp_is_store) begin
        load_valid_q[cache_rsp_lifecycle_slot] <= 1'b0;
        load_killed_q[cache_rsp_lifecycle_slot] <= 1'b0;
        if (load_count_q != 0) load_count_q <= load_count_q - COUNT_W'(1);
      end
      if (cache_rsp_valid && cache_rsp_ready && cache_rsp_is_store) begin
        store_valid_q[cache_rsp_lifecycle_slot] <= 1'b0;
        store_committed_q[cache_rsp_lifecycle_slot] <= 1'b0;
      end
    end else begin
      if (issue_valid && issue_ready && issue_decode_valid && !req_is_store && !req_fault_valid) begin
        load_valid_q[accepted_lifecycle_slot] <= 1'b1;
        load_killed_q[accepted_lifecycle_slot] <= 1'b0;
        load_rob_tag_q[accepted_lifecycle_slot] <= issue_uop.rob_tag;
        load_dst_tag_q[accepted_lifecycle_slot] <= issue_uop.dst_tag;
        load_vaddr_q[accepted_lifecycle_slot] <= req_effective_addr;
        load_seq_q[accepted_lifecycle_slot] <= issue_uop.seq_num;
        load_writes_dst_q[accepted_lifecycle_slot] <= issue_uop.writes_dst;
        load_count_q <= load_count_q + COUNT_W'(1);
      end
      if (issue_valid && issue_ready && issue_decode_valid && req_is_store && !req_fault_valid) begin
        store_valid_q[accepted_lifecycle_slot] <= 1'b1;
        store_rob_tag_q[accepted_lifecycle_slot] <= issue_uop.rob_tag;
        store_paddr_q[accepted_lifecycle_slot] <= issue_paddr;
        store_data_q[accepted_lifecycle_slot] <= issue_uop.src2_value;
        store_be_q[accepted_lifecycle_slot] <= req_byte_mask;
        store_size_q[accepted_lifecycle_slot] <= req_size_log2[1:0];
        store_order_slot_q[accepted_lifecycle_slot] <= accepted_store_order_slot;
        store_seq_q[accepted_lifecycle_slot] <= issue_uop.seq_num;
        store_committed_q[accepted_lifecycle_slot] <= 1'b0;
        store_count_q <= store_count_q + COUNT_W'(1);
      end
      if (cache_rsp_valid && cache_rsp_ready && !cache_rsp_is_store) begin
        load_valid_q[cache_rsp_lifecycle_slot] <= 1'b0;
        load_killed_q[cache_rsp_lifecycle_slot] <= 1'b0;
        if (load_count_q != 0) load_count_q <= load_count_q - COUNT_W'(1);
      end
      if (store_commit_valid && store_commit_ready)
        store_committed_q[store_commit_lifecycle_slot] <= 1'b1;
      if (cache_rsp_valid && cache_rsp_ready && cache_rsp_is_store) begin
        store_valid_q[cache_rsp_lifecycle_slot] <= 1'b0;
        store_committed_q[cache_rsp_lifecycle_slot] <= 1'b0;
        if (store_count_q != 0) store_count_q <= store_count_q - COUNT_W'(1);
      end
    end
  end

  assign live_loads = COUNT_W'(load_count_q);
  assign live_stores = COUNT_W'(store_count_q);

  // Mirror exactly the accepted allocation/completion events. The core-side
  // lifecycle tracker uses the same queue depth and sees these events once.
  assign ref_load_alloc_valid = issue_valid && issue_ready && issue_decode_valid &&
                                !req_is_store && !req_fault_valid;
  assign ref_load_base_tag = issue_uop.src1_tag[PHYS_W-1:0];
  assign ref_load_done_valid = load_done_valid;
  assign ref_load_done_slot = load_done_slot;
  assign ref_store_alloc_valid = issue_valid && issue_ready && issue_decode_valid &&
                                 req_is_store && !req_fault_valid;
  assign ref_store_base_tag = issue_uop.src1_tag[PHYS_W-1:0];
  assign ref_store_data_tag = issue_uop.src2_tag[PHYS_W-1:0];
  assign ref_store_alloc_seq = issue_uop.seq_num;
  assign ref_store_done_valid = store_done_valid;
  assign ref_store_done_slot = store_done_slot;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n && !flush_all) begin
    if (memory_wb_valid)
      assert (memory_complete_valid && !memory_complete_exception)
        else $error("Load PRF writeback must match successful ROB completion");
    if (cache_rsp_valid && !cache_rsp_is_store)
      assert (load_valid_q[cache_rsp_lifecycle_slot])
        else $error("Load response has no retained full-ROB identity");
    if (cache_rsp_valid && cache_rsp_is_store)
      assert (store_valid_q[cache_rsp_lifecycle_slot] && store_committed_q[cache_rsp_lifecycle_slot])
        else $error("Store response has no retained full-ROB identity");
    if (store_commit_valid && store_commit_ready)
      assert (store_match0 && retire_valid[0] && retire_kind[0][3])
        else $error("Store commit must be authorized by matching head retirement");
  end
`endif
endmodule
