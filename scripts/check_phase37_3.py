#!/usr/bin/env python3
from pathlib import Path
R = Path(__file__).resolve().parents[1]
checks = {
    "adapter accepts branch recovery sequence": "input logic recover_valid" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text() and "input logic [SEQ_W-1:0] recover_seq" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text(),
    "recovery forwarded through cache subsystem": ".clk, .rst_n, .flush_all, .recover_valid, .recover_seq" in (R/'rtl/memory/mx64_lsu_cache_subsystem.sv').read_text(),
    "recovery forwarded through LSU pipeline": ".clk, .rst_n, .flush_all, .recover_valid, .recover_seq" in (R/'rtl/memory/mx64_lsu_pipeline.sv').read_text(),
    "store ordering entries selectively pruned": "seq_younger(seq_q[r], recover_seq)" in (R/'rtl/memory/memory_ordering_unit.sv').read_text(),
    "store physical references selectively released": "seq_younger(store_seq_q[i], recover_seq)" in (R/'rtl/memory/lsu_reference_lifecycle.sv').read_text(),
    "load response identity retained and killed": "load_killed_q[s] <= 1'b1" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text(),
    "committed stores excluded from selective deletion": "!store_committed_q[s]" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text(),
    "response consumed during recovery": "if (cache_rsp_valid && cache_rsp_ready && !cache_rsp_is_store)" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text(),
    "trap flush remains separate": "if (flush_all) valid_d = '0" in (R/'rtl/memory/memory_ordering_unit.sv').read_text(),
    "limitations documented": "No HDL compiler" in (R/'docs/PHASE37_3_LSU_SELECTIVE_RECOVERY.md').read_text(),
}
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"SUMMARY: {sum(checks.values())}/{len(checks)}")
raise SystemExit(0 if all(checks.values()) else 1)
