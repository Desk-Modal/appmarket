#!/usr/bin/env bash
#
# Regression test for scripts/quality-gates/brand-alignment.sh.
#
# Current behaviour (rework cycle 1 — see the gate header): the gate
# enforces a platform guard. Only Windows (WebView2) speaks full CDP
# on :9222; macOS (WKWebView) and Linux (WebKitGTK) do not. On
# non-Windows hosts the gate BLOCs immediately with a clear message,
# BEFORE the dist / brand.json presence checks. That's intentional —
# silent skipping would defeat the gate's purpose on the dev team's
# primary platforms.
#
# Pins:
#   1. --if-touched with no GUI files touched → PASS (skipped).
#   2. GUI touched on macOS/Linux → BLOCKED with "not yet supported
#      on <os>" message (platform-guard path).
#   2w. GUI touched on Windows, no dist → BLOCKED with "dist not built"
#      (dist-presence path — legacy assertion kept for Windows runs).
#   3. GUI touched, brand.json missing, on a Windows host → BLOCKED
#      with "brand.json" in the message.
#
# The happy-path (CDP launch + assertion run) lives in
# scripts/launch.sh --verify; covered end-to-end by local-ci --full
# on the real workspace, not this unit test.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../../scripts/quality-gates/brand-alignment.sh"
REAL_BRAND="$HERE/../../../scripts/cdp-assertions/brand.json"

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) HOST_IS_WINDOWS=1 ;;
    *)                    HOST_IS_WINDOWS=0 ;;
esac

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }
skip() { printf "  skip: %s — %s\n" "$1" "$2"; }

mk_repo() {
    local tmp
    tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 1
        git init --quiet
        git config user.email "t@t"
        git config user.name "t"
        mkdir -p scripts/quality-gates/lib scripts/cdp-assertions
        cp "$GATE" scripts/quality-gates/brand-alignment.sh
        cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
        chmod +x scripts/quality-gates/brand-alignment.sh
        echo "# init" >README.md
        git add . && git commit -q -m "init"
    )
    echo "$tmp"
}

# 1. no GUI surface touched → PASS
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cp "$REAL_BRAND" scripts/cdp-assertions/brand.json
    git add -A && git commit -q -m "add brand.json"
    echo "prose update" >>README.md
    git add README.md && git commit -q -m "prose"
    bash scripts/quality-gates/brand-alignment.sh --if-touched HEAD
) >/tmp/qg-brand-1-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q "skipped" /tmp/qg-brand-1-$$.out; then
    pass "no GUI surface touched → skipped"
else
    fail "no GUI surface touched → skipped" "rc=$rc out=$(cat /tmp/qg-brand-1-$$.out)"
fi
rm -rf "$repo" /tmp/qg-brand-1-$$.out

# 2. GUI touched, non-Windows → BLOCKED (platform guard)
if [ "$HOST_IS_WINDOWS" -eq 0 ]; then
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1
        cp "$REAL_BRAND" scripts/cdp-assertions/brand.json
        mkdir -p plugins/tradesurface/apps/chart/src
        cat >plugins/tradesurface/apps/chart/src/Price.tsx <<'TSX'
export function Price() { return <span data-ts-price>100.00</span>; }
TSX
        git add -A && git commit -q -m "gui change"
        bash scripts/quality-gates/brand-alignment.sh --if-touched HEAD
    ) >/tmp/qg-brand-2-$$.out 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -Eq "not yet supported on (darwin|linux)" /tmp/qg-brand-2-$$.out; then
        pass "GUI touched on non-Windows → BLOCKED (platform guard)"
    else
        fail "GUI touched on non-Windows → BLOCKED (platform guard)" "rc=$rc out=$(cat /tmp/qg-brand-2-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-brand-2-$$.out
else
    # 2w. On Windows the platform guard does not fire; the gate reaches
    # the dist-presence check and BLOCs there because no dist/ exists
    # in the throwaway repo.
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1
        cp "$REAL_BRAND" scripts/cdp-assertions/brand.json
        mkdir -p plugins/tradesurface/apps/chart/src
        cat >plugins/tradesurface/apps/chart/src/Price.tsx <<'TSX'
export function Price() { return <span data-ts-price>100.00</span>; }
TSX
        git add -A && git commit -q -m "gui change"
        bash scripts/quality-gates/brand-alignment.sh --if-touched HEAD
    ) >/tmp/qg-brand-2w-$$.out 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q "dist not built" /tmp/qg-brand-2w-$$.out; then
        pass "GUI touched on Windows, no dist → BLOCKED (dist missing)"
    else
        fail "GUI touched on Windows, no dist → BLOCKED (dist missing)" "rc=$rc out=$(cat /tmp/qg-brand-2w-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-brand-2w-$$.out
fi

# 3. brand.json missing → BLOCKED.
# On non-Windows the platform guard fires first, so this assertion
# can only be exercised on Windows. We skip cleanly elsewhere rather
# than pretend to test it.
if [ "$HOST_IS_WINDOWS" -eq 1 ]; then
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1
        mkdir -p plugins/tradesurface/apps/chart/src
        cat >plugins/tradesurface/apps/chart/src/Foo.tsx <<'TSX'
export function Foo() { return null; }
TSX
        git add -A && git commit -q -m "change"
        bash scripts/quality-gates/brand-alignment.sh --if-touched HEAD
    ) >/tmp/qg-brand-3-$$.out 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q "brand.json" /tmp/qg-brand-3-$$.out; then
        pass "brand.json missing → BLOCKED"
    else
        fail "brand.json missing → BLOCKED" "rc=$rc out=$(cat /tmp/qg-brand-3-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-brand-3-$$.out
else
    skip "brand.json missing → BLOCKED" "platform guard fires first on non-Windows; covered by test 2"
fi

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
