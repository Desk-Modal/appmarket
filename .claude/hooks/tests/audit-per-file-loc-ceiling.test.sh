#!/usr/bin/env bash
# Regression test for scripts/audit-per-file-loc-ceiling.sh (G-AUDIT-48).
# Pins: (1) clean → rc=0 + OK; (2) over-threshold → rc=1 + FAIL header;
# (3) allowlist marker silences → rc=0; (4) exempt-path silences → rc=0.
set -u
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/audit-per-file-loc-ceiling.sh"
[ -r "$GATE" ] || { echo "FAIL: $GATE not found" >&2; exit 1; }
chmod +x "$GATE" 2>/dev/null || true
PASS=0; FAIL=0
p() { printf "  ok:   %s\n" "$1"; PASS=$((PASS+1)); }
f() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL+1)); }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLAUDE_PROJECT_DIR="$1" bash "$GATE" 2>&1; }
big() { yes 'let x = 1;' | head -"$1"; }

# (1) clean — all files ≤ 300 LOC
mkdir -p "$tmp/clean/src"
big 250 > "$tmp/clean/src/small.ts"
out=$(run "$tmp/clean"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "clean → rc=0 + OK" || f "clean" "rc=$rc $out"

# (2) over-threshold — one .tsx file at 500 LOC
mkdir -p "$tmp/big/src"
big 500 > "$tmp/big/src/Huge.tsx"
out=$(run "$tmp/big"); rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -qE "FAIL: [0-9]+ of [0-9]+ files exceed"; } && p "over-threshold → rc=1 + FAIL" || f "over-threshold" "rc=$rc $out"

# (3) allowlist marker honoured (first 3 lines)
mkdir -p "$tmp/allow/src"
{ echo '// audit:allow-loc-ceiling: decomp-tracked under F131-W3'; big 500; } > "$tmp/allow/src/Huge.tsx"
out=$(run "$tmp/allow"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "allowlist → rc=0 + OK" || f "allowlist" "rc=$rc $out"

# (4) exempt-path silences (fixtures/, generated/, _test.rs, node_modules/)
mkdir -p "$tmp/exempt/fixtures" "$tmp/exempt/generated" "$tmp/exempt/src" "$tmp/exempt/node_modules/pkg"
big 500 > "$tmp/exempt/fixtures/big.ts"
big 500 > "$tmp/exempt/generated/big.tsx"
big 500 > "$tmp/exempt/src/big_test.rs"
big 500 > "$tmp/exempt/node_modules/pkg/big.ts"
out=$(run "$tmp/exempt"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "exempt-paths → rc=0 + OK" || f "exempt" "rc=$rc $out"

printf "\nPassed: %d  Failed: %d\n" "$PASS" "$FAIL"; [ "$FAIL" = 0 ]
