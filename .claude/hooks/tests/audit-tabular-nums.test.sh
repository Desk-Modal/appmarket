#!/usr/bin/env bash
# Regression test for scripts/audit-tabular-nums.sh (G-AUDIT-12 + G-AUDIT-45).
# Cases: compliant pass, missing slashed-zero, missing both, allowlist, real HEAD fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-tabular-nums.sh"
[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok:   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2" >&2; }
tmp=$(mktemp -d -t audit-tabnum.XXXXXX); trap 'rm -rf "$tmp"' EXIT
DIR="$tmp/platform/apps/deskmodal-agent/src"; mkdir -p "$DIR" "$tmp/plugins/x/src"

# Case 1: compliant.
printf '.price { font-variant-numeric: tabular-nums slashed-zero; }\n' >"$DIR/a.module.css"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "compliant selector accepted" || fail "case 1" "rc=$rc out=$out"
rm "$DIR/a.module.css"

# Case 2: only tabular-nums (G-AUDIT-45 requires slashed-zero too).
printf '.pnl { font-variant-numeric: tabular-nums; }\n' >"$DIR/a.module.css"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "1" ] && echo "$out" | grep -q 'slashed-zero'; } && pass "tabular-nums alone rejected" || fail "case 2" "rc=$rc out=$out"

# Case 3: missing both.
printf '.volume { color: blue; }\n' >"$DIR/a.module.css"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "1" ] && echo "$out" | grep -q 'tabular-nums'; } && pass "missing both rejected" || fail "case 3" "rc=$rc out=$out"

# Case 4: allowlist marker on adjacent comment line suppresses.
printf '/* audit:allow-tabular-nums: decorative label */\n.volume { color: blue; }\n' >"$DIR/a.module.css"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "allowlist marker honoured" || fail "case 4" "rc=$rc out=$out"

# Case 5: real workspace HEAD currently passes (post-F131-W6 sweep). Pins
# the green state so a future numeric selector without tabular-nums +
# slashed-zero flips this case red.
out=$(bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "current HEAD passes as expected (post-F131-W6)" || fail "case 5" "expected rc=0, got rc=$rc out=$out"

echo ""
echo "audit-tabular-nums.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
