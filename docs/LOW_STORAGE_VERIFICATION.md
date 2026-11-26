# MX64-H verification without WSL or local tool installation

The project does not require WSL, a local Linux VM, Docker, or a local HDL toolchain
for its first compile/lint pass. The workflow `.github/workflows/rtl-verification.yml`
runs on a disposable GitHub-hosted Ubuntu runner and installs Verilator there.

## What runs remotely

1. Python repository/RTL contract checks (`make check`).
2. Software regression tests (`make test`).
3. Example ELF and boot-image build (`make boot-image`).
4. Verilator lint/elaboration of `mx64_top` using every RTL SystemVerilog source.

The runner is temporary. Tool installation and build products do not consume the
user's local disk. The workflow uses `ubuntu-24.04`; GitHub documents standard
hosted runners for public repositories as free and unlimited. Private repositories
use the account's included Actions compute allowance and may incur charges after
that allowance is exhausted. Check repository visibility and billing before enabling
repeated workflows.

## How to run it

1. Upload/commit this project to its GitHub repository, including the new workflow
   and `scripts/run_rtl_lint.sh`.
2. Open the repository's **Actions** tab.
3. Select **MX64-H RTL verification (cloud)**.
4. Choose **Run workflow** or push a commit / open a pull request.
5. Read the first failing step and preserve its log. A red run is useful evidence;
   do not label it a pass.

## Scope and limitations

- Verilator lint/elaboration is not a substitute for a cycle-accurate event-driven
  simulation. It does not prove functional correctness.
- This workflow does not claim that the current RTL passes. The first run is intended
  to discover actual compile/elaboration errors and warnings.
- No local software or WSL installation is required. The source still needs to be
  present in a GitHub repository for the hosted runner to check it out.
- Do not add `-Wno-fatal` as a permanent policy without reviewing warnings. It allows
  the initial baseline to report warnings while still failing on hard errors.
