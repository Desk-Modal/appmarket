#!/usr/bin/env bash
# Regression test for scripts/audit-ui-components-consumption.sh (G-AUDIT-44).
#
# Cases:
#   1. Synthetic agent with package.json missing @deskmodal/ui-components → rc=1
#   2. Synthetic agent declaring SDK + ≥80% components importing it → rc=0
#   3. Synthetic agent declaring SDK + <80% importing it → rc=1
#   4. Per-file allowlist marker counts as consuming
#   5. Missing components dir → rc=0 (SKIP)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../../.." && pwd)"
GATE="$ROOT_DIR/scripts/audit-ui-components-consumption.sh"

if [ ! -x "$GATE" ]; then
    chmod +x "$GATE" 2>/dev/null || { echo "FAIL: $GATE is not executable" >&2; exit 1; }
fi

PASS=0; FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT

make_root() {
    local r="$1" comp_count="$2" import_count="$3" allow_count="$4" declare_dep="$5"
    local d="$r/platform/apps/deskmodal-agent/src/components"
    mkdir -p "$d"
    if [ "$declare_dep" = "yes" ]; then
        printf '{"name":"x","dependencies":{"@deskmodal/ui-components":"workspace:*"}}\n' \
            > "$r/platform/apps/deskmodal-agent/package.json"
    else
        printf '{"name":"x","dependencies":{}}\n' > "$r/platform/apps/deskmodal-agent/package.json"
    fi
    local i=0
    while [ "$i" -lt "$import_count" ]; do
        printf "import { Button } from '@deskmodal/ui-components';\nexport const C%d = () => null;\n" "$i" > "$d/C$i.tsx"
        i=$((i + 1))
    done
    local j=0
    while [ "$j" -lt "$allow_count" ]; do
        printf "// audit:allow-ui-components: legacy\nexport const A%d = () => null;\n" "$j" > "$d/A$j.tsx"
        j=$((j + 1))
    done
    local k=0
    local plain=$((comp_count - import_count - allow_count))
    while [ "$k" -lt "$plain" ]; do
        printf "export const P%d = () => null;\n" "$k" > "$d/P$k.tsx"
        k=$((k + 1))
    done
}

# Case 1: missing dep declaration.
r1="$tmpdir/r1"; make_root "$r1" 5 5 0 no
out=$(CLAUDE_PROJECT_DIR="$r1" bash "$GATE" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'does not declare @deskmodal/ui-components'; then
    pass "package.json missing @deskmodal/ui-components → rc=1"
else
    fail "missing dep" "rc=$rc out=$out"
fi

# Case 2: dep declared + 100% coverage.
r2="$tmpdir/r2"; make_root "$r2" 5 5 0 yes
out=$(CLAUDE_PROJECT_DIR="$r2" bash "$GATE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '5/5'; then
    pass "100% coverage → rc=0"
else
    fail "100% coverage" "rc=$rc out=$out"
fi

# Case 3: dep declared + 40% coverage (below 80%).
r3="$tmpdir/r3"; make_root "$r3" 5 2 0 yes
out=$(CLAUDE_PROJECT_DIR="$r3" bash "$GATE" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q '2/5 files = 40%'; then
    pass "40% coverage → rc=1 with file list"
else
    fail "below threshold" "rc=$rc out=$out"
fi

# Case 4: allowlist marker counts as consuming.
r4="$tmpdir/r4"; make_root "$r4" 5 3 2 yes
out=$(CLAUDE_PROJECT_DIR="$r4" bash "$GATE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '5/5'; then
    pass "allowlist marker counts as consuming → rc=0"
else
    fail "allowlist counting" "rc=$rc out=$out"
fi

# Case 5: missing components dir → SKIP rc=0.
r5="$tmpdir/r5"; mkdir -p "$r5/platform/apps/deskmodal-agent"
printf '{"dependencies":{}}\n' > "$r5/platform/apps/deskmodal-agent/package.json"
out=$(CLAUDE_PROJECT_DIR="$r5" bash "$GATE" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'SKIP'; then
    pass "missing components dir → rc=0 SKIP"
else
    fail "skip-missing-dir" "rc=$rc out=$out"
fi

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
