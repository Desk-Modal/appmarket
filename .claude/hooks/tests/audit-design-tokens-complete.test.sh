#!/usr/bin/env bash
#
# Regression test for scripts/audit-design-tokens-complete.sh (G-AUDIT-42).
#
# Pins:
#   1. Current workspace state (post-F131-W4) — all 9 required tokens
#      declared, `--ts-shadow-md` allowlisted multi-rung — audit exits 0.
#      (Pre-W4 this case asserted rc=1; W4 landed the tokens and the
#      assertion now pins the green state to detect regression.)
#   2. Synthetic compliant tokens dir — 9 required tokens present once,
#      `--ts-shadow-md` declared once — audit exits 0.
#   3. Allowlist marker `/* audit:allow-token:<name>:<reason> */` suppresses
#      the FAIL for that token even when count==0.
#   4. Missing tokens dir → exit 0 (SKIP, not FAIL — keeps the gate
#      portable into stripped trees).
#
# Exit 0 if every case passes; exit 1 with summary on any miss.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"
GATE="$ROOT_DIR/scripts/audit-design-tokens-complete.sh"

if [ ! -x "$GATE" ]; then
    chmod +x "$GATE" 2>/dev/null || true
fi
if [ ! -r "$GATE" ]; then
    echo "FAIL: $GATE not found" >&2
    exit 1
fi

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Case 1: current workspace — post-F131-W4, all 9 required tokens declared,
# --ts-shadow-md allowlisted multi-rung. Audit must PASS (rc=0). Pins the
# green state so a future regression that drops one of the 9 tokens (or
# strips the shadow-md allowlist marker) flips this case red.
out=$(bash "$GATE" 2>&1)
rc=$?
miss_count=$(echo "$out" | grep -c 'FAIL — ' || true)
if [ "$rc" -eq 0 ] && [ "$miss_count" -eq 0 ] \
   && echo "$out" | grep -q "9 required + 1 single-source tokens compliant"; then
    pass "current workspace (post-F131-W4) → rc=0 (token completion locked in)"
else
    fail "current workspace post-W4 state" "expected rc=0 with 0 misses; got rc=$rc misses=$miss_count out=$out"
fi

# Case 2: synthetic compliant workspace — every required token declared
# once, --ts-shadow-md declared once. Audit must PASS.
fake="$tmpdir/compliant"
mkdir -p "$fake/plugins/tradesurface/packages/ui-components/src/tokens"
mkdir -p "$fake/scripts"
echo "# CLAUDE.md" > "$fake/CLAUDE.md"
cp "$GATE" "$fake/scripts/audit-design-tokens-complete.sh"
chmod +x "$fake/scripts/audit-design-tokens-complete.sh"
cat > "$fake/plugins/tradesurface/packages/ui-components/src/tokens/brand.css" <<'CSS'
:root {
    --ts-font-19px: 1.1875rem;
    --ts-glass-blur-14: 14px;
    --ts-glass-blur-20: 20px;
    --ts-glass-saturate: 180%;
    --ts-text-inverted: #ffffff;
    --ts-surface-overlay-scrim: rgba(0,0,0,0.5);
    --ts-space-1px: 1px;
    --ts-accent-success: oklch(0.7 0.18 145);
    --ts-accent-danger: oklch(0.6 0.22 25);
    --ts-shadow-md: 0 2px 8px rgba(0,0,0,0.12);
}
CSS
CLAUDE_PROJECT_DIR="$fake" out=$(CLAUDE_PROJECT_DIR="$fake" bash "$fake/scripts/audit-design-tokens-complete.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "9 required + 1 single-source tokens compliant"; then
    pass "synthetic compliant workspace → rc=0"
else
    fail "synthetic compliant workspace" "rc=$rc out=$out"
fi

# Case 3: allowlist marker suppresses missing-token FAIL.
fake_allow="$tmpdir/allow"
mkdir -p "$fake_allow/plugins/tradesurface/packages/ui-components/src/tokens"
mkdir -p "$fake_allow/scripts"
echo "# CLAUDE.md" > "$fake_allow/CLAUDE.md"
cp "$GATE" "$fake_allow/scripts/audit-design-tokens-complete.sh"
chmod +x "$fake_allow/scripts/audit-design-tokens-complete.sh"
# Declare 8 of 9, allowlist the 9th. Declare --ts-shadow-md once.
cat > "$fake_allow/plugins/tradesurface/packages/ui-components/src/tokens/brand.css" <<'CSS'
:root {
    --ts-font-19px: 1.1875rem;
    --ts-glass-blur-14: 14px;
    --ts-glass-blur-20: 20px;
    --ts-glass-saturate: 180%;
    --ts-text-inverted: #ffffff;
    --ts-surface-overlay-scrim: rgba(0,0,0,0.5);
    --ts-space-1px: 1px;
    --ts-accent-success: oklch(0.7 0.18 145);
    /* audit:allow-token:--ts-accent-danger:status-token covers this; will land in F131-W4 */
    --ts-shadow-md: 0 2px 8px rgba(0,0,0,0.12);
}
CSS
out=$(CLAUDE_PROJECT_DIR="$fake_allow" bash "$fake_allow/scripts/audit-design-tokens-complete.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "allowlisted"; then
    pass "allowlist marker /* audit:allow-token:--ts-accent-danger:... */ suppresses FAIL"
else
    fail "allowlist marker suppression" "rc=$rc out=$out"
fi

# Case 4: missing tokens dir → SKIP (rc=0).
fake_empty="$tmpdir/empty"
mkdir -p "$fake_empty/scripts"
echo "# CLAUDE.md" > "$fake_empty/CLAUDE.md"
cp "$GATE" "$fake_empty/scripts/audit-design-tokens-complete.sh"
chmod +x "$fake_empty/scripts/audit-design-tokens-complete.sh"
out=$(CLAUDE_PROJECT_DIR="$fake_empty" bash "$fake_empty/scripts/audit-design-tokens-complete.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "SKIP"; then
    pass "missing tokens dir → rc=0 (SKIP)"
else
    fail "missing tokens dir" "rc=$rc out=$out"
fi

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
