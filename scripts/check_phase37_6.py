#!/usr/bin/env python3
"""Static checks for low-storage cloud RTL verification bootstrap."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
workflow = (root / '.github/workflows/rtl-verification.yml').read_text()
runner = (root / 'scripts/run_rtl_lint.sh').read_text()
docs = (root / 'docs/LOW_STORAGE_VERIFICATION.md').read_text()
checks = {
    'hosted Ubuntu runner configured': 'runs-on: ubuntu-24.04' in workflow,
    'Verilator installed only on hosted runner': 'sudo apt-get install -y --no-install-recommends verilator' in workflow,
    'workflow has manual dispatch': 'workflow_dispatch:' in workflow,
    'software regression is included': 'run: make test' in workflow,
    'top-level lint step is included': 'bash scripts/run_rtl_lint.sh' in workflow,
    'top-level mx64_top selected': '--top-module mx64_top' in runner,
    'all RTL source discovery included': "find rtl -type f -name '*.sv'" in runner,
    'package ordering explicit': 'rtl/common/mx64_config_pkg.sv' in runner and 'rtl/common/mx64_pkg.sv' in runner,
    'no local WSL requirement documented': 'does not require WSL' in docs,
    'simulation limitation documented': 'not a substitute for a cycle-accurate' in docs,
}
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'SUMMARY: {sum(checks.values())}/{len(checks)}')
raise SystemExit(0 if all(checks.values()) else 1)
