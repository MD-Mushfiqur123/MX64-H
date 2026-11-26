# Low-storage verification

This project can use GitHub-hosted Actions runners for HDL linting without installing WSL2, Docker or Verilator on the developer PC.

1. Push the project to GitHub.
2. Open the repository's Actions tab.
3. Select **MX64-H RTL verification (cloud)**.
4. Use **Run workflow**, or push a commit to trigger it automatically.
5. Inspect the Verilator log and download failure diagnostics if the job fails.

The hosted runner is temporary and uses GitHub Actions minutes. Check the account's current Actions limits and billing settings.

A successful Verilator lint/elaboration run is only a compile-time structural check. It is not cycle-accurate simulation, formal proof, synthesis, timing analysis or physical signoff. Do not claim functional correctness from lint alone.
