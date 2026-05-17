#!/usr/bin/env bash
# Regression test for scripts/audit-legacy-rip-sweep.sh (G-AUDIT-50).
# Cases: (1) clean → rc=0; (2) V2 filename → rc=1; (3) legacyMode id →
# rc=1; (4) allowlist marker silences violation → rc=0.
set -u
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/audit-legacy-rip-sweep.sh"
[ -r "$GATE" ] || { echo "FAIL: $GATE not found" >&2; exit 1; }
chmod +x "$GATE" 2>/dev/null || true
PASS=0; FAIL=0
p() { printf "  ok:   %s\n" "$1"; PASS=$((PASS+1)); }
f() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL+1)); }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLAUDE_PROJECT_DIR="$1" bash "$GATE" 2>&1; }

# (1) clean tree → rc=0
mkdir -p "$tmp/clean/src"
printf 'pub fn alive() {}\n' > "$tmp/clean/src/lib.rs"
out=$(run "$tmp/clean"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "clean → rc=0" || f "clean" "rc=$rc $out"

# (2) V2 filename → rc=1
mkdir -p "$tmp/v2/src"
printf 'export const X = 1;\n' > "$tmp/v2/src/OrderBookV2.tsx"
out=$(run "$tmp/v2"); rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -q "V2 filenames"; } && p "V2 filename → rc=1" || f "v2" "rc=$rc $out"

# (3) legacyMode identifier → rc=1
mkdir -p "$tmp/legacy/src"
printf 'export const legacyMode = true;\n' > "$tmp/legacy/src/feature.ts"
out=$(run "$tmp/legacy"); rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -q "legacy identifiers"; } && p "legacyMode → rc=1" || f "legacy" "rc=$rc $out"

# (4) allowlist marker silences both → rc=0
mkdir -p "$tmp/allow/src"
printf '// audit:allow-v2 leading comment\nexport const X = 1;\n' > "$tmp/allow/src/OrderBookV2.tsx"
printf 'export const legacyMode = true; // audit:allow-legacy: pinned compat\n' > "$tmp/allow/src/feature.ts"
out=$(run "$tmp/allow"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "allowlist → rc=0" || f "allow" "rc=$rc $out"

printf "\nPassed: %d  Failed: %d\n" "$PASS" "$FAIL"; [ "$FAIL" = 0 ]
