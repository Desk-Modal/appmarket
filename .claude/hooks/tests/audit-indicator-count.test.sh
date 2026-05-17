#!/usr/bin/env bash
# Regression test for scripts/audit-indicator-count.sh (S-IND-01).
# Cases: clean (count ≥ 100), count-too-low fixture (count < 100), empty registry fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"
AUDIT="$ROOT_DIR/scripts/audit-indicator-count.sh"
[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok:   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2" >&2; }
tmp=$(mktemp -d -t audit-indcount.XXXXXX); trap 'rm -rf "$tmp"' EXIT
DIR="$tmp/plugins/tradesurface/packages/indicators/src"; mkdir -p "$DIR"

# Case 1: clean — fixture with 100 fake registrations (exactly the floor).
{
    echo "// fixture"
    echo "export function registerAllIndicators(registry) {"
    for i in $(seq 1 100); do
        echo "  registry.register({ id: \"ind${i}\" }, fn);"
    done
    echo "}"
} > "$DIR/registry.ts"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "0" ] && echo "$out" | grep -q "100 indicators registered"; } \
  && pass "fixture at floor (100) accepted" || fail "case 1" "rc=$rc out=$out"

# Case 2: count-too-low fixture (50 < 100).
{
    echo "// fixture"
    echo "export function registerAllIndicators(registry) {"
    for i in $(seq 1 50); do
        echo "  registry.register({ id: \"ind${i}\" }, fn);"
    done
    echo "}"
} > "$DIR/registry.ts"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "1" ] && echo "$out" | grep -q "50 indicators registered"; } \
  && pass "below floor (50<100) rejected" || fail "case 2" "rc=$rc out=$out"

# Case 3: empty registry — zero registrations fails.
{
    echo "// empty"
    echo "export function registerAllIndicators(registry) {"
    echo "}"
} > "$DIR/registry.ts"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "1" ] && echo "$out" | grep -q "0 indicators registered"; } \
  && pass "empty registry rejected" || fail "case 3" "rc=$rc out=$out"

# Case 4: allowlist marker bypasses the floor.
{
    echo "// audit:allow-indicator-count: pack-extraction in progress — see specs/NNN"
    echo "export function registerAllIndicators(registry) {"
    echo "  registry.register({ id: \"only-one\" }, fn);"
    echo "}"
} > "$DIR/registry.ts"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "0" ] && echo "$out" | grep -q "BYPASS"; } \
  && pass "allowlist marker honoured" || fail "case 4" "rc=$rc out=$out"

# Case 5: missing registry — skip cleanly.
rm "$DIR/registry.ts"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "0" ] && echo "$out" | grep -q "SKIP"; } \
  && pass "missing registry skipped" || fail "case 5" "rc=$rc out=$out"

# Case 6: real workspace HEAD passes (current count ≥ 100).
out=$(bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "current HEAD passes" || fail "case 6" "expected rc=0, got rc=$rc out=$out"

echo ""
echo "audit-indicator-count.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
