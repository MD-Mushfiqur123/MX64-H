# M3 Research Notes and Design Rationale

## Sources reviewed

1. Berkeley BOOM documentation, instruction fetch:
   https://docs.boom-core.org/en/latest/sections/instruction-fetch-stage.html
   Relevant concepts: superscalar fetch packets, fetch buffer, prediction metadata, frontend redirect after backend misprediction.

2. OpenHW CVA6 documentation, PC generation and branch prediction:
   https://docs.openhwfoundation.org/projects/cva6-user-manual/03_cva6_design/pcgen_stage.html
   Relevant concepts: BTB/BHT lookup, saturating counters, tag comparison to reduce aliasing, predictor update and PC redirect.

3. OpenHW CVA6 execution-stage documentation:
   https://docs.openhwfoundation.org/projects/cva6-user-manual/03_cva6_design/ex_stage.html
   Relevant concepts: branch resolution, LSU, DTLB, page-table walker, MMU arbitration, store buffering until commit, multiply/divide implementation.

4. OpenHW CVA6 overview and requirements:
   https://docs.openhwfoundation.org/projects/cva6-user-manual/01_cva6_user/Introduction.html
   https://docs.openhwfoundation.org/projects/cva6-user-manual/02_cva6_requirements/cva6_requirements_specification.html
   Relevant concepts: application-class core scope includes core pipeline, caches, optional MMU/FPU/PMP, CSR, counters and external bus interfaces.

5. RISC-V Privileged Architecture introduction:
   https://docs.riscv.org/reference/isa/priv/priv-intro.html
   Relevant concepts: machine/supervisor/user privilege layering, trap transitions and return. Used as conceptual reference, not as an MX64 compatibility claim.

## Applied MX64 choices

- Start with a small tagged BTB plus 2-bit direction counters, then evaluate gshare/global history after a working baseline exists.
- Preserve predictor state across ordinary pipeline flushes; redirect speculative fetch but train from resolved branches.
- Keep stores buffered until retirement so speculative execution cannot expose architectural memory side effects.
- Keep MMIO/non-idempotent accesses out of speculative paths.
- Treat CSR/trap behavior as an architectural contract, not an ad hoc control signal.
- Separate architecture-level requirements from the microarchitectural implementation so queue sizes and pipeline depth can change without changing ISA semantics.

## Limitations

The sources above describe other architectures. They are design references, not validation of MX64. The new MX64 modules are first RTL drafts and have not been compiled, simulated, formally checked, or synthesized in this environment.
