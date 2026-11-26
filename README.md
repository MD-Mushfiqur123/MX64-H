# MXISA-64 / MX64-H

**Status:** Architecture baseline v1.0-draft; RTL integration is experimental and not verified.
**Target:** 64-bit, 2-wide superscalar, out-of-order CPU with private L1 I/D caches and a shared-L2 interface.

MX64-H is a custom ISA and CPU project. It is not x86-64 or RISC-V compatible.

## Scope and current limitations

- New 64-bit ISA, assembler/linker prototype, ELF64 tooling and boot-image packer.
- RTL blocks for frontend, rename/PRF, ROB, integer execution, issue queues, memory ordering and LSU integration.
- Phase 37.5 adds an integrated execution-core boundary. Branch execution and memory interfaces remain external.
- Address translation is identity-mapped in this phase; there is no implemented MMU/TLB.
- This is not a complete SoC, verified CPU, tapeout-ready design, or foundry-qualified implementation.
- Simulation, formal verification, synthesis, timing closure and physical signoff are outstanding.

## Repository layout

- `rtl/` — SystemVerilog packages and RTL blocks.
- `tools/mx64/` — assembler, ISA model, ELF and boot-image tools.
- `software/` — example programs and runtime/tooling inputs.
- `verification/` — testbenches, contracts and audit notes.
- `docs/` — ISA, microarchitecture, memory-system and integration specifications.
- `scripts/` — static checks and build helpers.
- `.github/workflows/` — cloud CI workflows.

## Local software checks

```sh
make check
make test
make boot-image
```

These validate software tooling, static RTL contracts and example image generation. They do **not** establish that SystemVerilog compiles or that the CPU works.

## Cloud RTL lint

GitHub Actions workflow `MX64-H RTL verification (cloud)` installs Verilator on a hosted Ubuntu runner and attempts top-level lint/elaboration. The first workflow run is the authoritative source of lint diagnostics. A lint pass is not a substitute for simulation, formal verification or synthesis.

See `docs/LOW_STORAGE_VERIFICATION.md` for the low-storage workflow.

## Architecture decisions

Before full implementation, freeze the unresolved decisions in `docs/OPEN_DECISIONS.md`, including privilege/VM semantics, interrupt/debug behavior, external bus protocol, cache coherence and multicore memory consistency.
