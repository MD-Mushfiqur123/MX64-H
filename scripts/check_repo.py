#!/usr/bin/env python3
"""Static repository structure checker; intentionally does not run HDL tools."""
from pathlib import Path
import csv
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
required = [
    "README.md", "docs/ARCHITECTURE_OVERVIEW.md", "docs/ISA_SPEC.md",
    "docs/MODULE_CONTRACTS.md", "docs/MEMORY_CACHE_SPEC.md",
    "docs/PDK_INTEGRATION.md", "docs/OPEN_DECISIONS.md",
    "verification/VERIFICATION_PLAN.md", "verification/TEST_MATRIX.md",
    "rtl/core/mx64_top.sv", "rtl/execution/branch_reference_lifecycle.sv", "mxagent/AGENT_WORKFLOW.md",
    "scripts/setup_and_run_windows.bat", "docs/REFERENCES.md",
    "verification/RTL_AUDIT_M2_4.md", "verification/RTL_AUDIT_M2_5.md",
    "scripts/check_rtl_sources.py",
    "docs/requirements/MX64H_SYSTEM_REQUIREMENTS.md",
    "docs/requirements/MX64H_REQUIREMENTS_TRACEABILITY.csv",
    "docs/isa/MXISA64_ISA_BASELINE.md", "docs/isa/MXISA64_OPCODE_TABLE.csv",
    "docs/isa/MXISA64_PRIVILEGED_PROFILE.md",
    "docs/architecture/MX64H_H0_H1_DECISIONS.md",
    "software/abi/MX64H_ABI_DRAFT.md",
    "software/toolchain/MX64H_TOOLCHAIN_ROADMAP.md",
    "tools/mx64/audit_isa.py", "tools/mx64/smoke_test.py", "tools/mx64/architecture_tests.py",
    "tools/mx64/assembler.py", "tools/mx64/assembler_tests.py",
    "tools/mx64/elf64.py",
    "software/runtime/README.md",
    "software/runtime/crt0_mx64h.s",
    "tools/mx64/abi_check.py",
    "software/examples/worker.s",
    "software/examples/main.s",
    "software/examples/memory.s",
    ".github/workflows/software.yml",
    "Makefile",
    "tools/mx64/mxbuild.py", "tools/mx64/mxas_obj.py", "tools/mx64/mxld.py", "tools/mx64/elf64_tests.py",
    "tools/mx64/boot_image.py", "tools/mx64/mxboot.py", "tools/mx64/boot_image_tests.py",
    "tools/mx64/platform_check.py", "tools/mx64/platform_tests.py",
    "tools/mx64/multisection_tests.py", "tools/mx64/load_image.py",
    "tools/mx64/load_image_tests.py",
    "docs/research/MX64H_RESEARCH_UPDATE_2026-11.md",
    "platforms/fpga/template.json", "platforms/asic/template.json",
    "docs/platform/PLATFORM_BOOT_CONTRACT.md",
]
missing = [p for p in required if not (ROOT / p).is_file()]
if missing:
    print("FAIL: missing files:")
    print("\n".join(missing))
    sys.exit(1)

for rel in ("config/mx64h_default.json", "platforms/fpga/template.json", "platforms/asic/template.json"):
    with (ROOT / rel).open(encoding="utf-8") as f:
        json.load(f)

for rel in ("docs/isa/MXISA64_OPCODE_TABLE.csv",
            "docs/requirements/MX64H_REQUIREMENTS_TRACEABILITY.csv"):
    with (ROOT / rel).open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
        if not rows:
            raise SystemExit(f"FAIL: empty CSV: {rel}")

markers = {
    "docs/ARCHITECTURE_OVERVIEW.md": ["out-of-order", "in-order", "48-bit"],
    "docs/PDK_INTEGRATION.md": ["commercial foundry", "DRC", "LVS"],
    "verification/VERIFICATION_PLAN.md": ["Differential testing", "Formal properties"],
    "docs/requirements/MX64H_SYSTEM_REQUIREMENTS.md": ["Gate H0", "Gate H4"],
}
for rel, needles in markers.items():
    content = (ROOT / rel).read_text(encoding="utf-8").lower()
    for needle in needles:
        if needle.lower() not in content:
            raise SystemExit(f"FAIL: {rel} missing marker {needle!r}")

print(f"PASS: repository structure and metadata checks ({len(required)} required files)")
print("NOTE: static checks only; no HDL compile, simulation, formal proof, or synthesis was run.")
