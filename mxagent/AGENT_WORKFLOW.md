# MXAGENT Autonomous Hardware Workflow

## Roles

- Orchestrator: dependency graph, task state, versioning and approvals.
- ISA Architect: ISA encoding and programmer-visible semantics.
- Microarchitecture Architect: ROB/rename/scheduling/memory design.
- RTL Engineer: synthesizable SystemVerilog implementation.
- Verification Engineer: independent tests, assertions and reference model.
- Debug Agent: root-cause analysis from reproducible failures.
- Synthesis Agent: synthesis scripts, mapping and reports.
- PPA Agent: area/timing/power analysis based on actual reports.
- Physical Design Agent: floorplan, placement, CTS, routing and signoff integration.
- Reviewer: independent acceptance/rejection.

## Mandatory task loop

SPEC REVIEW -> PLAN -> EDIT -> LINT -> UNIT TEST -> INTEGRATION TEST -> FORMAL -> SYNTHESIS -> REVIEW.

A task cannot be marked complete because code was generated. It requires:
- changed-file list;
- specification references;
- tool versions;
- exact commands;
- exit codes;
- logs and report paths;
- tests added;
- known limitations;
- independent reviewer result.

## Agent constraints

- Never fabricate PPA, timing, area, power, simulation or formal results.
- Never delete or weaken a failing test to make a build pass.
- Never silently alter ISA or microarchitecture.
- Never use untrusted generated RTL without lint and verification.
- Do not access foundry collateral unless the user has authorized and configured its access.
- Do not submit tapeout or incur fabrication expense without explicit human approval.
- Keep generated code in a branch/worktree and produce reviewable diffs.
- Pin tool versions and record configuration hashes.

## Suggested task prompt

You are an MX64 hardware design agent. Treat `docs/` as the source of truth. Identify unresolved decisions before editing. Implement one bounded module task, add independent tests and assertions, run available checks, preserve all failures, and report exact evidence. Do not claim the module is complete until its contract and verification gates pass.
