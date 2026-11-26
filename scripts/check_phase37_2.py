from pathlib import Path
root = Path(__file__).resolve().parents[1]
checks = {
    "adapter declaration": ("rtl/memory/mx64_lsu_rob_adapter.sv", ["module mx64_lsu_rob_adapter", "endmodule"]),
    "load opcode map": ("rtl/memory/mx64_lsu_rob_adapter.sv", ["6'h06", "EXC_LOAD_MISALIGNED", "EXC_LOAD_FAULT"]),
    "store opcode map": ("rtl/memory/mx64_lsu_rob_adapter.sv", ["6'h07", "EXC_STORE_MISALIGNED", "store_commit_valid"]),
    "full ROB tag retention": ("rtl/memory/mx64_lsu_rob_adapter.sv", ["load_rob_tag_q", "store_rob_tag_q", "ROB_TAG_W"]),
    "load stale-response suppression": ("rtl/memory/mx64_lsu_rob_adapter.sv", ["load_killed_q", "!load_killed_q[cache_rsp_lifecycle_slot]"]),
    "committed-store flush retention": ("rtl/memory/mx64_lsu_rob_adapter.sv", ["store_valid_q & store_committed_q", "store_committed_q[store_commit_lifecycle_slot] <= 1'b1"]),
    "retirement gate in control": ("rtl/core/mx64_control_subsystem.sv", ["retire_gate_ready", ".normal_retire_ready(retire_gate_ready)"]),
    "retirement gate in frontend": ("rtl/core/mx64_frontend_dispatch.sv", ["retire_gate_ready", ".retire_gate_ready"]),
    "architecture limitations documented": ("docs/PHASE37_2_LSU_ROB_ADAPTER.md", ["Branch-mispredict recovery is not yet propagated", "not instantiated into `mx64_top`"]),
}
failed = []
for name, (rel, needles) in checks.items():
    text = (root / rel).read_text()
    ok = all(n in text for n in needles)
    print(("PASS" if ok else "FAIL") + ": " + name)
    if not ok:
        failed.append(name)
print(f"SUMMARY: {len(checks)-len(failed)}/{len(checks)}")
raise SystemExit(1 if failed else 0)
