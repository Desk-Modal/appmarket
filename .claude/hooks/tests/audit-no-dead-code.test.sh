#!/usr/bin/env bash
# Regression test for scripts/audit-no-dead-code.sh (G-AUDIT-46).
# Pins: (1) no platform/ → SKIP rc=0; (2) clean → rc=0; (3) dead_code +
# unused_imports → rc=1 + FAIL header; (4) allowlist marker silences → rc=0.
# Current-HEAD baseline is exercised by local-ci.sh --fast itself.
set -u
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/audit-no-dead-code.sh"
[ -r "$GATE" ] || { echo "FAIL: $GATE not found" >&2; exit 1; }
chmod +x "$GATE" 2>/dev/null || true
PASS=0; FAIL=0
p() { printf "  ok:   %s\n" "$1"; PASS=$((PASS+1)); }
f() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL+1)); }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLAUDE_PROJECT_DIR="$1" bash "$1/scripts/audit-no-dead-code.sh" 2>&1; }
fixture() {
    mkdir -p "$1/platform/src" "$1/scripts"
    printf '[package]\nname="audit-fix"\nversion="0.0.0"\nedition="2021"\n[lib]\npath="src/lib.rs"\n' > "$1/platform/Cargo.toml"
    printf '%s' "$2" > "$1/platform/src/lib.rs"
    cp "$GATE" "$1/scripts/audit-no-dead-code.sh"
}
mkdir -p "$tmp/empty/scripts"; cp "$GATE" "$tmp/empty/scripts/audit-no-dead-code.sh"
out=$(run "$tmp/empty"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q SKIP; } && p "missing platform/ → SKIP" || f "skip" "rc=$rc $out"
command -v cargo >/dev/null 2>&1 || { echo "  skip: cargo missing" >&2; printf "\nPassed: %d  Failed: %d\n" "$PASS" "$FAIL"; [ "$FAIL" = 0 ]; exit $?; }
fixture "$tmp/clean" 'pub fn used() -> u32 { 42 }
'
out=$(run "$tmp/clean"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "clean → rc=0" || f "clean" "rc=$rc $out"
fixture "$tmp/dirty" 'use std::collections::HashMap;
fn dead_priv() -> u32 { 0 }
pub fn alive() -> u32 { 1 }
'
out=$(run "$tmp/dirty"); rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -qE "FAIL: [0-9]+ violations"; } && p "dirty → rc=1 + FAIL" || f "dirty" "rc=$rc $out"
fixture "$tmp/allow" '#[allow(unused_imports)] // audit:allow-dead-code: test
use std::collections::HashMap;
#[allow(dead_code)] // audit:allow-dead-code: test
fn dead_priv() -> u32 { 0 }
pub fn alive() -> u32 { 1 }
'
out=$(run "$tmp/allow"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "allowlist → rc=0" || f "allowlist" "rc=$rc $out"
printf "\nPassed: %d  Failed: %d\n" "$PASS" "$FAIL"; [ "$FAIL" = 0 ]
