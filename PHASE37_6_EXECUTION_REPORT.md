# MX64-H Phase 37.6 — Low-Storage Cloud RTL Verification Bootstrap

## User constraint
The developer machine has no WSL2 and insufficient free disk space for a local HDL
installation. This phase avoids installing WSL, Docker, Verilator, or a Linux VM locally.

## Implemented
- Added `.github/workflows/rtl-verification.yml` for a disposable GitHub-hosted Ubuntu
  runner.
- Workflow installs Verilator remotely and runs repository checks, software tests,
  boot-image build, and top-level `mx64_top` lint/elaboration.
- Added `scripts/run_rtl_lint.sh` with explicit package ordering and discovery of all
  remaining RTL SystemVerilog sources.
- Added `scripts/check_phase37_6.py` and a `make rtl-lint` target.
- Updated an obsolete Phase 37.1 static assertion: the former empty top shell has now
  been replaced by an explicitly scoped integrated execution-core boundary.
- Added `docs/LOW_STORAGE_VERIFICATION.md` with setup, usage, billing caveats, and scope.

## Local validation performed
- `bash -n scripts/run_rtl_lint.sh`: PASS.
- Workflow structural check: PASS.
- `scripts/check_repo.py`: PASS.
- `scripts/check_rtl_sources.py`: PASS.
- Historical Phase 37.1 through 37.5 static contracts: PASS after updating the stale
  Phase 37.1 expectation to match the current integrated top boundary.
- Phase 37.6 cloud-workflow contract: PASS.
- Python software regression suite: see `PHASE37_6_VALIDATION.txt`.
- No HDL tool is installed in this environment; Verilator was not executed here.

## Important status
This is a cloud-verification bootstrap, not evidence that the RTL compiles. The first
GitHub Actions run is required to obtain real Verilator diagnostics. Simulation,
formal verification, and synthesis remain outstanding.
