# Commercial PDK Integration Contract

Version: 1.0-draft

## Status

The project has selected **commercial foundry PDK** as a category, but no foundry, process, PDK release, standard-cell library, SRAM compiler, voltage corner or signoff deck has been selected. Therefore the repository is technology-agnostic. No foundry-specific RTL or physical constraints are fabricated here.

## Required inputs from foundry / authorized design partner

1. PDK name and revision; process option and metal stack.
2. Standard-cell Liberty files for all required PVT corners.
3. LEF abstracts and technology LEF.
4. Verilog simulation models and cell functional models.
5. SRAM compiler and generated memory macros for L1/L2 arrays, or approved memory implementation strategy.
6. SRAM timing/power models and physical abstracts.
7. RC extraction technology files.
8. DRC, LVS, antenna, density and latch-up rules/decks.
9. ESD, IO and pad-ring library if a standalone chip is planned.
10. Multi-voltage and power-intent requirements, if applicable.
11. Foundry-approved signoff tools and runsets.
12. Package, bump/bonding and IO requirements.

## Required project decisions

- Target process and process option.
- Operating voltage range and temperature range.
- Target clock frequency and clock uncertainty.
- Core utilization and floorplan constraints.
- SRAM macro compiler options, number of ports and banking.
- IO protocol and chip boundary.
- Reset, test, scan, MBIST and JTAG strategy.
- Power domains, isolation and retention.
- ESD and package strategy.
- Signoff ownership and tapeout checklist.

## Synthesis policy

- Keep generic RTL independent of foundry cell names.
- Use explicit technology mapping only in a PDK-specific layer.
- Infer memories only when the synthesis flow maps them to approved macros or an explicitly accepted standard-cell implementation.
- Review all inferred latches and black boxes.
- Preserve synthesis logs, constraints, mapped netlists and reports with source revision hashes.

## Physical design gates

1. Floorplan and macro placement review.
2. Power grid planning and IR-drop analysis.
3. Placement congestion review.
4. CTS skew/latency review.
5. Setup and hold STA at all required corners.
6. Signal integrity/crosstalk analysis as required by node.
7. DRC and LVS clean under foundry runsets.
8. Antenna and density checks.
9. Power analysis and EM/IR checks.
10. Formal equivalence between RTL and mapped netlist where supported.
11. GDS/OASIS stream-out integrity and final signoff approval.

A generated GDS file is not by itself proof of tapeout readiness.
