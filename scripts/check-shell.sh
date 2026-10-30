#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/picters"
bash -n "$ROOT/scripts/test-picters-cli.sh"
bash -n "$ROOT/scripts/check-shell.sh"
sh -n "$ROOT/ci_core_rs/src/thermalctl.sh"
sh -n "$ROOT/ci_core_rs/src/chargingctl.sh"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/picters" "$ROOT/scripts/test-picters-cli.sh" "$ROOT/scripts/check-shell.sh"
else
  echo "shellcheck not found; bash -n checks passed."
fi
