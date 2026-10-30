#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PICTERS="$ROOT/picters"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export KOKUBAN_CONFIG="$tmpdir/config"

output="$(PICTERS_CORE=/bin/echo "$PICTERS" build mi17_sm8850 resukisu resukisu --no-bbg)"
assert_contains "$output" "local --project mi17_sm8850 --branch resukisu --variant resukisu"
assert_contains "$output" "--apply-bbg false"

output="$(PICTERS_CORE=/bin/echo "$PICTERS" plan mi17_sm8850 resukisu default --no-susfs --no-bbg)"
assert_contains "$output" "--dry-run"
assert_contains "$output" "--apply-susfs false"
assert_contains "$output" "--apply-bbg false"

"$PICTERS" config set apply_susfs false >/dev/null
output="$("$PICTERS" plan mi17_sm8850)"
assert_contains "$output" "apply_susfs: false"

"$PICTERS" preset set daily mi17_sm8850 resukisu resukisu --no-bbg >/dev/null
output="$("$PICTERS" run daily --offline --dry-run)"
assert_contains "$output" "apply_bbg: false"
assert_contains "$output" "offline: true"

echo "OK: Picters CLI wrapper tests passed."
