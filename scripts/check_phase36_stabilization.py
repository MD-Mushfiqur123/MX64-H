#!/usr/bin/env python3
"""Static Phase-36 regression guards. These do NOT replace HDL simulation."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')

checks = {
    'IQ captures wakeup on accepted same-cycle enqueue': (
        'rtl/scheduler/issue_queue.sv',
        ['effective_enq_uop[p] = enq_uop[p];',
         'if (enq_valid[p] && enq_ready[p] && !flush && !recover_valid)',
         'ref_acquire_tag[2*p] = effective_enq_uop[p].src1_tag;',
         'entry_q[write_slot] <= effective_enq_uop[p];']),
    'IQ acquires references only for operands still unresolved after bypass': (
        'rtl/scheduler/issue_queue.sv',
        ['if (!effective_enq_uop[p].src1_ready)',
         'if (!effective_enq_uop[p].src2_ready)']),
    'Reference tracker restores architectural identity-map ownership on clear': (
        'rtl/rename/physical_register_reference_tracker.sv',
        ["reclaim_bitmap[r] = !clear_all", 'else if (clear_all)',
         'if (r < INIT_ARCH_REGS)', "reference_count[r] <= COUNT_W'(1);"]),
    'Cache latches invalidation received while busy': (
        'rtl/memory/cache_hierarchy.sv',
        ['logic invalidate_pending_q;',
         'if (invalidate_all && state_q != S_IDLE)',
         'invalidate_pending_q <= 1\'b1;',
         '(state_q == S_IDLE) && (invalidate_all || invalidate_pending_q)',
         '!invalidate_pending_q']),
    'Committed-store errors require platform sink acknowledgement': (
        'rtl/memory/mx64_lsu_cache_subsystem.sv',
        ['output logic store_error_valid,', 'input logic store_error_ready,',
         'output logic [SLOT_W-1:0] store_error_lifecycle_slot,',
         '(!store_error_valid || store_error_ready)',
         'Committed-store error was consumed before error-sink acknowledgement']),
    'Top-level remains explicitly non-functional (known blocker)': (
        'rtl/core/mx64_top.sv',
        ['TODO(MX64-RTL-001)', 'This shell is not a functional CPU']),
}

failed = []
for name, (rel, needles) in checks.items():
    src = read(rel)
    missing = [n for n in needles if n not in src]
    if missing:
        failed.append((name, missing))
        print(f'FAIL: {name}')
        for m in missing:
            print(f'  missing: {m}')
    else:
        print(f'PASS: {name}')

# Guard against accidentally representing a source-pattern audit as simulation.
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)} static checks passed')
print('LIMITATION: static source-pattern checks only; no HDL parse/compile/elaboration/simulation/formal/synthesis.')
sys.exit(1 if failed else 0)
