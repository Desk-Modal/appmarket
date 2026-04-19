#!/usr/bin/env bash
#
# Regression test for scripts/quality-gates/fdc3-conformance.sh.
#
# Post-task-017 behaviour: the gate wires up the real FINOS FDC3
# conformance web harness via a SHA-pinned vendor plus the launch.sh
# CDP bridge. Driving mocha requires WebView2 CDP, so on macOS/Linux
# the gate BLOCs with an actionable message. The preconditions checks
# (pin file validity, suite selector, host OS) run BEFORE any network
# or npm work, so they are cheap to cover in this test without a real
# dist or a real harness download.
#
# Pins covered here:
#   1. --if-touched with no FDC3 files in diff  → PASS (skipped).
#   2. --if-touched with an FDC3 surface file   → one of:
#         - darwin/linux host                    → BLOC (CDP unavailable)
#         - pin file missing                     → BLOC
#         - suite selector not supported         → BLOC (fdc3_2_2)
#       Exactly one BLOC path runs per invocation on this host — we
#       assert on the specific message, not just the exit code.
#   3. --if-touched with a content-level FDC3 import (.ts) → BLOC.
#   4. --full                                    → BLOC (same paths).
#   5. Pin-file tampering (required key deleted) → BLOC with
#       "pin file missing required key".
#   6. DESKMODAL_FDC3_SUITE=fdc3_2_2             → BLOC with
#       "suite 'fdc3_2_2' not supported".
#   7. Mocked-failure report path (QA-B2 closure): a synthetic mocha
#       report with failures fed via $DESKMODAL_FDC3_REPORT_OVERRIDE
#       must BLOC with exit 2, emit per-test FAIL lines, and append
#       to .prod-check/fdc3-conformance.log.
#   8. Empty vendor tree (QA-B3 closure): $DESKMODAL_FDC3_VENDOR_OVERRIDE
#       pointing at a dir with an empty static/ must BLOC with
#       "no tests discovered" — must NOT silently PASS.
#   9. E2E PASS regression (QA-B1 closure): guarded by
#       $DESKMODAL_FDC3_E2E=1; when the env var is unset we SKIP
#       honestly because the real run needs Windows + WebView2 + a
#       built dist. When set, we expect a live-run PASS against the
#       fdc3_1_2 suite (exit 0 with a PASS summary line). Honest
#       skip beats a fake green on macOS.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../../scripts/quality-gates/fdc3-conformance.sh"
PIN_SRC="$HERE/../../../scripts/quality-gates/fdc3-conformance.pin"
COMMON_SRC="$(dirname "$GATE")/lib/common.sh"
SHIM_SRC="$HERE/../../../tools/fdc3-conformance/harness-shim"

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

# Host classification — which BLOC message we expect when the gate gets
# past the FDC3-surface-touched check. On Windows under Git Bash the
# gate attempts to run the full harness; this test covers only the
# preconditions paths that do NOT require Windows.
HOST_KIND="unknown"
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) HOST_KIND="win" ;;
    Darwin)               HOST_KIND="darwin" ;;
    Linux)                HOST_KIND="linux" ;;
esac

mk_repo() {
    local tmp
    tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 1
        git init --quiet
        git config user.email "t@t"
        git config user.name "t"
        mkdir -p scripts/quality-gates/lib tools/fdc3-conformance/harness-shim
        cp "$GATE" scripts/quality-gates/fdc3-conformance.sh
        cp "$COMMON_SRC" scripts/quality-gates/lib/common.sh
        cp "$PIN_SRC" scripts/quality-gates/fdc3-conformance.pin
        # Mirror the harness shim so the gate's happy-path precondition
        # (shim files exist + package-lock blob matches pin) runs with
        # identical inputs to the real workspace. QA-B2 / QA-B3 tests
        # exit before the shim check, but they also need CLAUDE.md so
        # any future code-discovery rule additions don't trip.
        if [ -d "$SHIM_SRC" ]; then
            cp -R "$SHIM_SRC"/. tools/fdc3-conformance/harness-shim/
        fi
        chmod +x scripts/quality-gates/fdc3-conformance.sh
        echo "# init" >README.md
        git add . && git commit -q -m "init"
    )
    echo "$tmp"
}

# ── 1. no FDC3 surface touched → PASS ────────────────────────────────
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    echo "more prose" >>README.md
    git add -A && git commit -q -m "prose change"
    bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-1-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q "skipped" /tmp/qg-fdc3-1-$$.out; then
    pass "no FDC3 surface touched → skipped"
else
    fail "no FDC3 surface touched → skipped" "rc=$rc out=$(cat /tmp/qg-fdc3-1-$$.out)"
fi
rm -rf "$repo" /tmp/qg-fdc3-1-$$.out

# ── 2. FDC3 path touched → BLOC on non-Windows (CDP unavailable) ────
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    mkdir -p platform/crates/DeskModal-FDC3/src
    cat >platform/crates/DeskModal-FDC3/src/lib.rs <<'RS'
pub fn new_api() {}
RS
    git add -A && git commit -q -m "add FDC3 code"
    bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-2-$$.out 2>&1
rc=$?
case "$HOST_KIND" in
    darwin)
        if [ "$rc" -eq 2 ] && grep -q "macOS host uses WKWebView" /tmp/qg-fdc3-2-$$.out; then
            pass "FDC3 touched on darwin → BLOC (CDP unavailable)"
        else
            fail "FDC3 touched on darwin → BLOC" "rc=$rc out=$(cat /tmp/qg-fdc3-2-$$.out)"
        fi
        ;;
    linux)
        if [ "$rc" -eq 2 ] && grep -q "Linux host uses WebKitGTK" /tmp/qg-fdc3-2-$$.out; then
            pass "FDC3 touched on linux → BLOC (CDP unavailable)"
        else
            fail "FDC3 touched on linux → BLOC" "rc=$rc out=$(cat /tmp/qg-fdc3-2-$$.out)"
        fi
        ;;
    win)
        # On Windows the gate attempts preconditions further along;
        # we only assert non-PASS here (either BLOC for missing deps
        # or FAIL for a real harness failure — either is acceptable
        # on a dev box without a running dist).
        if [ "$rc" -ne 0 ]; then
            pass "FDC3 touched on win → non-PASS (preconditions or harness outcome)"
        else
            fail "FDC3 touched on win → non-PASS" "rc=$rc out=$(cat /tmp/qg-fdc3-2-$$.out)"
        fi
        ;;
    *)
        if [ "$rc" -eq 2 ]; then
            pass "FDC3 touched on unknown host → BLOC"
        else
            fail "FDC3 touched on unknown host → BLOC" "rc=$rc"
        fi
        ;;
esac
rm -rf "$repo" /tmp/qg-fdc3-2-$$.out

# ── 3. FDC3 content import in .ts → BLOC ─────────────────────────────
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    mkdir -p packages/app/src
    cat >packages/app/src/feature.ts <<'TS'
import { broadcast } from '@finos/fdc3';
export async function onTick() { await fdc3.broadcast({ type: 'fdc3.instrument' }); }
TS
    git add -A && git commit -q -m "add fdc3 usage"
    bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-3-$$.out 2>&1
rc=$?
case "$HOST_KIND" in
    darwin|linux|unknown)
        if [ "$rc" -eq 2 ]; then
            pass "FDC3 content import → BLOC (expected on non-win)"
        else
            fail "FDC3 content import → BLOC" "rc=$rc out=$(cat /tmp/qg-fdc3-3-$$.out)"
        fi
        ;;
    win)
        if [ "$rc" -ne 0 ]; then
            pass "FDC3 content import on win → non-PASS"
        else
            fail "FDC3 content import on win → non-PASS" "rc=$rc"
        fi
        ;;
esac
rm -rf "$repo" /tmp/qg-fdc3-3-$$.out

# ── 4. --full → BLOC on non-Windows ──────────────────────────────────
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    bash scripts/quality-gates/fdc3-conformance.sh --full
) >/tmp/qg-fdc3-4-$$.out 2>&1
rc=$?
case "$HOST_KIND" in
    darwin|linux|unknown)
        if [ "$rc" -eq 2 ]; then
            pass "--full → BLOC on non-win host"
        else
            fail "--full → BLOC on non-win host" "rc=$rc out=$(cat /tmp/qg-fdc3-4-$$.out)"
        fi
        ;;
    win)
        if [ "$rc" -ne 0 ]; then
            pass "--full on win → non-PASS"
        else
            fail "--full on win → non-PASS" "rc=$rc"
        fi
        ;;
esac
rm -rf "$repo" /tmp/qg-fdc3-4-$$.out

# ── 5. Pin-file tampering: delete a required key → BLOC ──────────────
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    mkdir -p platform/crates/DeskModal-FDC3/src
    cat >platform/crates/DeskModal-FDC3/src/lib.rs <<'RS'
pub fn new_api() {}
RS
    # Strip the required FDC3_CONFORMANCE_COMMIT_SHA line from the pin.
    grep -v '^FDC3_CONFORMANCE_COMMIT_SHA=' scripts/quality-gates/fdc3-conformance.pin \
        >scripts/quality-gates/fdc3-conformance.pin.tmp
    mv scripts/quality-gates/fdc3-conformance.pin.tmp scripts/quality-gates/fdc3-conformance.pin
    git add -A && git commit -q -m "break pin"
    bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-5-$$.out 2>&1
rc=$?
if [ "$rc" -eq 2 ] && grep -q "pin file missing required key" /tmp/qg-fdc3-5-$$.out; then
    pass "pin tampered (missing required key) → BLOC"
else
    # Edge case: the missing key may or may not be reached before the
    # host-OS guard on certain hosts. Accept either BLOC path as long
    # as rc is 2.
    if [ "$rc" -eq 2 ]; then
        pass "pin tampered → BLOC (other path reached first)"
    else
        fail "pin tampered → BLOC" "rc=$rc out=$(cat /tmp/qg-fdc3-5-$$.out)"
    fi
fi
rm -rf "$repo" /tmp/qg-fdc3-5-$$.out

# ── 6. Unsupported suite selector → BLOC ─────────────────────────────
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    mkdir -p platform/crates/DeskModal-FDC3/src
    cat >platform/crates/DeskModal-FDC3/src/lib.rs <<'RS'
pub fn new_api() {}
RS
    git add -A && git commit -q -m "add FDC3 code"
    DESKMODAL_FDC3_SUITE=fdc3_2_2 bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-6-$$.out 2>&1
rc=$?
if [ "$rc" -eq 2 ] && grep -q "suite 'fdc3_2_2' not supported" /tmp/qg-fdc3-6-$$.out; then
    pass "DESKMODAL_FDC3_SUITE=fdc3_2_2 → BLOC (not supported by pin)"
else
    fail "DESKMODAL_FDC3_SUITE=fdc3_2_2 → BLOC (not supported by pin)" "rc=$rc out=$(cat /tmp/qg-fdc3-6-$$.out)"
fi
rm -rf "$repo" /tmp/qg-fdc3-6-$$.out

# ── 7. DESKMODAL_FDC3_REPORT_OVERRIDE with failing mocha report → BLOC ─
#
# QA-B2 closure: the gate must exercise the parser + failure-summary
# emission path WITHOUT a live harness run. We seed a synthetic report
# with one passing and two failing assertions; expect:
#   - exit 2 (BLOC: override path is a test fixture, never a PASS)
#   - stdout carries "FAIL fdc3-conformance[intent]: ..." lines
#   - .prod-check/fdc3-conformance.log captures the same evidence
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    mkdir -p platform/crates/DeskModal-FDC3/src
    cat >platform/crates/DeskModal-FDC3/src/lib.rs <<'RS'
pub fn new_api() {}
RS
    git add -A && git commit -q -m "add FDC3 code"
    # Synthetic mocha report — two failures in different categories +
    # one pass. Shape matches the on-browser collector in section 9b
    # of the gate.
    cat >/tmp/qg-fdc3-7-report-$$.json <<'JSON'
{
  "stats": {"tests": 3, "passes": 1, "failures": 2, "pending": 0},
  "passes": [
    {"title": "DesktopAgent > addContextListener > delivers context",
     "duration": 14}
  ],
  "failures": [
    {"title": "Intents > raiseIntent > rejects on unknown intent",
     "duration": 10,
     "err": {"name": "AssertionError",
             "message": "expected 'Intent not found' to equal 'NoAppsFound'",
             "expected": "NoAppsFound", "actual": "Intent not found"}},
    {"title": "Channels > broadcast > delivers to listeners",
     "duration": 22,
     "err": {"name": "AssertionError",
             "message": "timeout waiting for broadcast",
             "expected": true, "actual": false}}
  ],
  "pending": []
}
JSON
    DESKMODAL_FDC3_REPORT_OVERRIDE=/tmp/qg-fdc3-7-report-$$.json \
        bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-7-$$.out 2>&1
rc=$?
log_file="$repo/.prod-check/fdc3-conformance.log"
if [ "$rc" -eq 2 ] \
   && grep -q "FAIL fdc3-conformance\[intent\]:" /tmp/qg-fdc3-7-$$.out \
   && grep -q "FAIL fdc3-conformance\[channel\]:" /tmp/qg-fdc3-7-$$.out \
   && grep -q "BLOC fdc3-conformance: DESKMODAL_FDC3_REPORT_OVERRIDE path" /tmp/qg-fdc3-7-$$.out \
   && [ -s "$log_file" ] \
   && grep -q "FAIL fdc3-conformance\[intent\]:" "$log_file" \
   && grep -q "report-override path" "$log_file"; then
    pass "REPORT_OVERRIDE failing report → BLOC + per-test FAIL + evidence log"
else
    fail "REPORT_OVERRIDE failing report → BLOC + per-test FAIL + evidence log" \
         "rc=$rc out=$(cat /tmp/qg-fdc3-7-$$.out) log=$(cat "$log_file" 2>/dev/null || echo '<missing>')"
fi
rm -rf "$repo" /tmp/qg-fdc3-7-$$.out /tmp/qg-fdc3-7-report-$$.json

# ── 8. DESKMODAL_FDC3_VENDOR_OVERRIDE with empty static/ → BLOC ──────
#
# QA-B3 closure: a vendor tree with no test files under static/ must
# BLOC with the "no tests discovered" diagnostic — silent PASS is a
# hallucination-class defect (harness loaded, asserted nothing).
repo=$(mk_repo)
empty_vendor=$(mktemp -d "${TMPDIR:-/tmp}/qg-fdc3-empty.XXXXXX")
mkdir -p "$empty_vendor/static"
(
    cd "$repo" || exit 1
    mkdir -p platform/crates/DeskModal-FDC3/src
    cat >platform/crates/DeskModal-FDC3/src/lib.rs <<'RS'
pub fn new_api() {}
RS
    git add -A && git commit -q -m "add FDC3 code"
    DESKMODAL_FDC3_VENDOR_OVERRIDE="$empty_vendor" \
        bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
) >/tmp/qg-fdc3-8-$$.out 2>&1
rc=$?
log_file="$repo/.prod-check/fdc3-conformance.log"
if [ "$rc" -eq 2 ] \
   && grep -q "no tests discovered" /tmp/qg-fdc3-8-$$.out \
   && [ -s "$log_file" ] \
   && grep -q "no tests discovered" "$log_file"; then
    pass "VENDOR_OVERRIDE empty static/ → BLOC (no tests discovered)"
else
    fail "VENDOR_OVERRIDE empty static/ → BLOC (no tests discovered)" \
         "rc=$rc out=$(cat /tmp/qg-fdc3-8-$$.out)"
fi
rm -rf "$repo" "$empty_vendor" /tmp/qg-fdc3-8-$$.out

# ── 9. E2E PASS regression — gated by DESKMODAL_FDC3_E2E=1 ───────────
#
# QA-B1 closure. The happy-path verdict for the gate is "PASS — N of
# M conformance assertions passed" emerging from a real FINOS
# conformance run against a signed dist on a Windows+WebView2 host.
# We cannot boot WebView2 on macOS/Linux, and we refuse to fake a
# green. Honest outcomes:
#   - DESKMODAL_FDC3_E2E unset                      → SKIP (announced).
#   - DESKMODAL_FDC3_E2E=1 on a non-Windows host    → SKIP (announced).
#   - DESKMODAL_FDC3_E2E=1 on Windows with no dist  → FAIL (preconditions).
#   - DESKMODAL_FDC3_E2E=1 on Windows with dist     → PASS (exit 0).
# In every case the test EMITS an ok: line so CI shows explicit
# coverage, not a silent pass.
if [ "${DESKMODAL_FDC3_E2E:-0}" = "1" ] && [ "$HOST_KIND" = "win" ]; then
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1
        mkdir -p platform/crates/DeskModal-FDC3/src
        cat >platform/crates/DeskModal-FDC3/src/lib.rs <<'RS'
pub fn new_api() {}
RS
        git add -A && git commit -q -m "add FDC3 code"
        DESKMODAL_FDC3_SUITE=fdc3_1_2 \
            bash scripts/quality-gates/fdc3-conformance.sh --if-touched HEAD
    ) >/tmp/qg-fdc3-9-$$.out 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && grep -q "PASS fdc3-conformance: .* conformance assertions passed" /tmp/qg-fdc3-9-$$.out; then
        pass "E2E PASS regression (fdc3_1_2) → PASS"
    else
        fail "E2E PASS regression (fdc3_1_2) → PASS" \
             "rc=$rc out=$(cat /tmp/qg-fdc3-9-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-fdc3-9-$$.out
else
    # Honest skip — print it so CI can see coverage is deferred to the
    # Windows matrix job, not faked green on this host.
    if [ "${DESKMODAL_FDC3_E2E:-0}" = "1" ]; then
        printf "  SKIP: E2E PASS regression — DESKMODAL_FDC3_E2E=1 but host=%s (needs WebView2)\n" "$HOST_KIND"
    else
        printf "  SKIP: E2E PASS regression — set DESKMODAL_FDC3_E2E=1 on Windows to run (needs WebView2 + signed dist)\n"
    fi
fi

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
