# Synthesis Entry Point

Technology-independent synthesis is not yet configured because the RTL is scaffold-only and no commercial PDK is selected.

Before synthesis:
1. Complete RTL.
2. Select target top and parameters.
3. Select supported Yosys version or commercial synthesis tool.
4. Provide standard-cell Liberty/LEF and memory macro views.
5. Define clock, IO delays, false/multicycle paths and operating corners.
6. Review inferred memories, latches, black boxes and arithmetic mapping.

Never use placeholder PDK files for signoff.
