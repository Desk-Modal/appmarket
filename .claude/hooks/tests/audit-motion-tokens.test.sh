#!/usr/bin/env bash
# Regression test for scripts/audit-motion-tokens.sh (G-AUDIT-43).
# Cases: literal ease/linear/duration fire; --ts-* + --deskmodal-* tokens pass;
# 0ms reduced-motion exempt; allowlist marker suppresses; word-boundary on
# --deskmodal-ease-spring; comment-only lines ignored.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$(cd "$HERE/../../.." && pwd)/scripts/audit-motion-tokens.sh"
[ -x "$GATE" ] || { echo "FAIL: $GATE not executable" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL+1)); }

tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' EXIT
D="$tmpdir/fake/platform/apps/deskmodal-agent/src/c"
mkdir -p "$D" "$tmpdir/fake/plugins/tradesurface/apps"

# write a single fixture, run, assert. expect_rc 0|1; expect_substr can be empty.
case_check() {
    local name="$1" expect_rc="$2" expect_substr="$3" body="$4"
    rm -f "$D"/*.module.css
    printf '%b\n' "$body" > "$D/X.module.css"
    local out rc
    out=$(CLAUDE_PROJECT_DIR="$tmpdir/fake" bash "$GATE" 2>&1); rc=$?
    if [ "$rc" -eq "$expect_rc" ] && { [ -z "$expect_substr" ] || echo "$out" | grep -q "$expect_substr"; }; then
        pass "$name"
    else fail "$name" "rc=$rc out=$out"; fi
}

case_check "literal ease fires"          1 'literal easing keyword' '.x { transition: opacity 200ms ease; }'
case_check "literal linear fires"        1 'literal easing keyword' '.x { transition: opacity var(--ts-motion-duration-fast) linear; }'
case_check "literal duration fires"      1 'literal duration'       '.x { transition-duration: 150ms; }'
case_check "--ts-* tokens pass"          0 ''                       '.x { transition: opacity var(--ts-motion-duration-fast) var(--ts-easing-standard); }'
case_check "--deskmodal-* tokens pass"   0 ''                       '.x { transition: opacity var(--deskmodal-duration-fast) var(--deskmodal-ease-spring); }'
case_check "0ms reduced-motion exempt"   0 ''                       '@media (prefers-reduced-motion: reduce) { .x { transition: 0ms; } }'
case_check "allowlist marker suppresses" 0 ''                       '.x { transition: opacity 200ms ease; /* audit:allow-motion-tokens: pinned */ }'
case_check "ease-spring no FP"           0 ''                       '.x { transition-timing-function: var(--deskmodal-ease-spring); transition-duration: var(--deskmodal-duration-fast); }'
case_check "comment-only line ignored"   0 ''                       '/* transition: opacity 200ms ease — note */\n.x { transition: opacity var(--ts-motion-duration-fast) var(--ts-easing-standard); }'

echo; printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
