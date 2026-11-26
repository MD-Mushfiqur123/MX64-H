from pathlib import Path
R = Path(__file__).resolve().parents[1]
checks = {
    "branch mispredict drives LSU lifecycle recovery": "recover_valid(lsu_recover_valid)" in (R/'rtl/core/mx64_frontend_dispatch.sv').read_text() and "assign lsu_recover_valid = branch_resolve_valid && branch_resolve_ready && branch_mispredict" in (R/'rtl/core/mx64_frontend_dispatch.sv').read_text(),
    "LSU lifecycle receives store sequence": "input logic [31:0] lsu_store_alloc_seq" in (R/'rtl/core/mx64_frontend_dispatch.sv').read_text() and ".store_alloc_seq(lsu_store_alloc_seq)" in (R/'rtl/core/mx64_frontend_dispatch.sv').read_text(),
    "LSU lifecycle sequence comparison is wrap-safe": "seq_younger(store_seq_q[i], recover_seq)" in (R/'rtl/memory/lsu_reference_lifecycle.sv').read_text(),
    "memory ordering sequence comparison is wrap-safe": "seq_younger(seq_q[r], recover_seq)" in (R/'rtl/memory/memory_ordering_unit.sv').read_text() and "seq_older(seq_q[s], load_query_seq)" in (R/'rtl/memory/memory_ordering_unit.sv').read_text(),
    "adapter sequence comparison is wrap-safe": "seq_younger(load_seq_q[s], recover_seq)" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text() and "seq_younger(store_seq_q[s], recover_seq)" in (R/'rtl/memory/mx64_lsu_rob_adapter.sv').read_text(),
    "integer issue queue retains enqueue-side wakeup": "Capture a completion that coincides with enqueue" in (R/'rtl/scheduler/issue_queue.sv').read_text(),
    "rename checkpoint recovers RAT and free list": "restore_rat = rat_q[order_q[resolve_pos]]" in (R/'rtl/rename/branch_checkpoint_manager.sv').read_text() and "restore_free_bitmap = free_q[order_q[resolve_pos]]" in (R/'rtl/rename/branch_checkpoint_manager.sv').read_text(),
    "integer backend receives recovery sequence": ".recover_seq(checkpoint_recover_seq)" in (R/'rtl/core/mx64_dispatch_controller.sv').read_text(),
    "research decisions documented": (R/'docs/PHASE37_4_RESEARCH_AND_RECOVERY_HARDENING.md').exists(),
    "top integration limitations remain explicit": "not a complete SoC" in (R/'rtl/core/mx64_top.sv').read_text(),
}
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"SUMMARY: {sum(checks.values())}/{len(checks)}")
raise SystemExit(0 if all(checks.values()) else 1)
