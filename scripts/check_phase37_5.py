#!/usr/bin/env python3
"""Static interface checks for Phase 37.5 core integration. Not HDL elaboration."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
top = (root / 'rtl/core/mx64_top.sv').read_text()
adapter = (root / 'rtl/memory/mx64_lsu_rob_adapter.sv').read_text()
checks = {
    'top instantiates frontend dispatch': 'mx64_frontend_dispatch #' in top and 'u_frontend_dispatch' in top,
    'top instantiates LSU ROB adapter': 'mx64_lsu_rob_adapter #' in top and 'u_lsu_rob_adapter' in top,
    'memory issue handshake connected': '.issue_valid(memory_issue_valid)' in top and '.issue_ready(memory_issue_ready)' in top,
    'memory completion returns to ROB': '.memory_complete_valid' in top and '.memory_complete_tag' in top,
    'load PRF writeback connected': '.memory_wb_valid' in top and '.memory_wb_tag' in top and '.memory_wb_data' in top,
    'store retirement gate connected': '.retire_gate_ready(retire_store_ready)' in top and '.retire_store_ready' in top,
    'branch recovery sequence connected': '.recover_seq(recovery_seq_debug)' in top,
    'trap flush distinct from branch recovery': '.flush_all(trap_valid)' in top and '.recover_valid(branch_resolve_valid' in top,
    'LSU ref allocation/completion mirrored': 'ref_load_alloc_valid' in top and 'ref_store_done_valid' in top,
    'adapter exposes load lifecycle events': 'output logic ref_load_alloc_valid' in adapter and 'output logic ref_load_done_valid' in adapter,
    'adapter exposes store lifecycle events': 'output logic ref_store_alloc_valid' in adapter and 'output logic ref_store_done_valid' in adapter,
    'identity mapping limitation documented': 'Identity translation is explicit' in top,
    'no empty shell TODO remains': 'TODO(MX64-RTL-001)' not in top and 'This shell is not a functional CPU' not in top,
}
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'SUMMARY: {sum(checks.values())}/{len(checks)}')
raise SystemExit(0 if all(checks.values()) else 1)
