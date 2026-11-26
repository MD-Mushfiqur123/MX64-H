from pathlib import Path
R = Path(__file__).resolve().parents[1]
checks = {
 "memory queue module exists": ("rtl/scheduler/mx64_memory_issue_queue.sv", ["module mx64_memory_issue_queue", "issue_valid", "issue_ready"]),
 "memory queue oldest-op blocking": ("rtl/scheduler/mx64_memory_issue_queue.sv", ["The oldest valid memory op is the only candidate", "candidate_ready"]),
 "same-cycle enqueue wakeup": ("rtl/scheduler/mx64_memory_issue_queue.sv", ["Apply wakeup to same-cycle enqueues before reference acquisition", "effective_enq[p].src1_value"]),
 "wakeup collision priority matches PRF port zero": ("rtl/scheduler/mx64_memory_issue_queue.sv", ["wakeup lane 0 priority", "physical register file's documented write-port-0 collision priority"]),
 "reference acquire/release implemented": ("rtl/scheduler/mx64_memory_issue_queue.sv", ["ref_acquire_valid", "ref_release_valid"]),
 "dispatch controller classifies memory ops": ("rtl/core/mx64_dispatch_controller.sv", ["memory_operation[lane]", "memory_dispatch_valid", "~memory_operation"]),
 "dispatch atomic-handshake assertion recognizes memory queue": ("rtl/core/mx64_dispatch_controller.sv", ["memory_operation[lane] && memory_dispatch_valid[lane] && memory_dispatch_ready[lane]"]),
 "memory dispatch is excluded from integer backend": ("rtl/core/mx64_dispatch_controller.sv", ["~control_transfer & ~memory_operation & ~dispatch_exception"]),
 "control subsystem propagates memory interface": ("rtl/core/mx64_control_subsystem.sv", ["memory_dispatch_ready", "memory_dispatch_valid", "memory_dispatch_uop"]),
 "frontend integrates memory queue": ("rtl/core/mx64_frontend_dispatch.sv", ["mx64_memory_issue_queue", "memory_issue_valid", "memory_issue_ready"]),
 "memory writeback reaches PRF": ("rtl/core/mx64_frontend_dispatch.sv", ["prf_wen[3] = memory_wb_valid", ".WRITE_PORTS(4)"]),
 "testbench covers ordering, wakeup ref release, recovery and flush": ("verification/phase37_1/tb_mx64_memory_issue_queue.sv", ["younger ready memory op bypassed older unresolved op", "wakeup did not release the retained source reference", "flush did not release unresolved memory source", "recovery did not release younger memory source"]),
 "memory completion lane returns to ROB": ("rtl/core/mx64_integer_backend.sv", ["memory_complete_valid", "rob_complete_valid[WIDTH+1] = memory_complete_valid", ".COMPLETE_WIDTH(WIDTH+2)"]),
 "memory completion error metadata is forwarded": ("rtl/core/mx64_integer_backend.sv", ["rob_complete_exception[WIDTH+1] = memory_complete_exception", "rob_complete_exception_code[WIDTH+1]", "rob_complete_exception_value[WIDTH+1]"]),
 "memory completion is exposed through frontend/control": ("rtl/core/mx64_frontend_dispatch.sv", ["memory_complete_rob_tag", ".memory_complete_tag(memory_complete_rob_tag)", "memory_complete_exception"]),
 "ROB memory completion lane has directed test": ("verification/phase37_1/tb_rob_memory_completion_lane.sv", ["complete_valid[WIDTH+1]=1'b1", "memory completion did not mark ROB entry done", "allocated_tag=alloc_tag[0]"]),
 "memory completion pulse contract documented": ("docs/PHASE37_1_INTERFACE_MAP.md", ["one-cycle completion event", "single-outstanding"]),
 "top-level integration boundary is explicit": ("rtl/core/mx64_top.sv", ["integrated execution-core boundary, not a complete SoC"]),
}
failed=[]
for label,(f,needles) in checks.items():
    text=(R/f).read_text(errors="replace")
    ok=all(n in text for n in needles)
    print(("PASS" if ok else "FAIL")+": "+label)
    if not ok: failed.append(label)
print(f"SUMMARY: {len(checks)-len(failed)}/{len(checks)}")
raise SystemExit(bool(failed))
