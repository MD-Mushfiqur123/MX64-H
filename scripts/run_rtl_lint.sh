#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: Verilator is required on the runner." >&2
  exit 127
fi
FILELIST="$(mktemp)"
trap 'rm -f "$FILELIST"' EXIT
printf '%s\n' rtl/common/mx64_config_pkg.sv rtl/common/mx64_pkg.sv rtl/common/mx64_if.sv > "$FILELIST"
while IFS= read -r file; do
  case "$file" in
    rtl/common/mx64_config_pkg.sv|rtl/common/mx64_pkg.sv|rtl/common/mx64_if.sv) ;;
    *) printf '%s\n' "$file" >> "$FILELIST" ;;
  esac
done < <(find rtl -type f -name '*.sv' | LC_ALL=C sort)
verilator --version
verilator --lint-only --timing --top-module mx64_top -Wall -Wno-fatal -f "$FILELIST"
