#!/usr/bin/env bash
#
# Regression test for scripts/quality-gates/sdk-surface-audit.sh.
#
# Pins:
#   1. --if-touched with no SDK files in diff → PASS (skipped).
#   2. --diff-only with SDK surface delta AND no compat-ladder.yml
#      present → PASS (WARN-class; task 014 creates the ladder).
#   3. --diff-only with SDK surface delta AND empty compat-ladder.yml
#      present → FAIL (surface delta without documentation).
#
# The gate prefers `cargo public-api` — we bypass it by ensuring the
# tool is not installed in the fake repo's PATH (it isn't globally on
# this machine in any case). The grep fallback is what we pin.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../../scripts/quality-gates/sdk-surface-audit.sh"

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

mk_repo() {
    local tmp
    tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 1
        git init --quiet
        git config user.email "t@t"
        git config user.name "t"
        mkdir -p scripts/quality-gates/lib
        mkdir -p platform/crates/deskmodal-service-sdk/src
        mkdir -p specs/schemas
        cp "$GATE" scripts/quality-gates/sdk-surface-audit.sh
        cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
        chmod +x scripts/quality-gates/sdk-surface-audit.sh
        cat >platform/crates/deskmodal-service-sdk/Cargo.toml <<'TOML'
[package]
name = "deskmodal-service-sdk"
version = "0.1.0"
edition = "2021"
TOML
        cat >platform/crates/deskmodal-service-sdk/src/lib.rs <<'RS'
pub fn existing() {}
RS
        git add . && git commit -q -m "init"
    )
    echo "$tmp"
}

# 1. if-touched with no SDK change
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    # Touch a non-SDK file.
    echo "unrelated" >README.md
    git add README.md && git commit -q -m "docs only"
    bash scripts/quality-gates/sdk-surface-audit.sh --if-touched HEAD
) >/tmp/qg-sdk-1-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q "skipped" /tmp/qg-sdk-1-$$.out; then
    pass "if-touched without SDK change skips"
else
    fail "if-touched without SDK change skips" "rc=$rc out=$(cat /tmp/qg-sdk-1-$$.out)"
fi
rm -rf "$repo" /tmp/qg-sdk-1-$$.out

# 2. SDK change WITHOUT compat-ladder.yml present → PASS
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cat >>platform/crates/deskmodal-service-sdk/src/lib.rs <<'RS'
pub fn new_export() {}
RS
    git add -A && git commit -q -m "add SDK export"
    bash scripts/quality-gates/sdk-surface-audit.sh --diff-only HEAD
) >/tmp/qg-sdk-2-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "SDK delta without ladder passes (WARN-class)"
else
    fail "SDK delta without ladder passes" "rc=$rc out=$(cat /tmp/qg-sdk-2-$$.out)"
fi
rm -rf "$repo" /tmp/qg-sdk-2-$$.out

# 3. SDK change WITH empty compat-ladder.yml → FAIL
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cat >specs/compat-ladder.yml <<'YML'
# Placeholder created for the regression test.
version: 1
entries: []
YML
    git add specs/compat-ladder.yml && git commit -q -m "empty ladder"
    cat >>platform/crates/deskmodal-service-sdk/src/lib.rs <<'RS'
pub fn new_export() {}
RS
    git add -A && git commit -q -m "add SDK export"
    bash scripts/quality-gates/sdk-surface-audit.sh --diff-only HEAD
) >/tmp/qg-sdk-3-$$.out 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
    pass "SDK delta with empty ladder fails"
else
    fail "SDK delta with empty ladder fails" "rc=$rc out=$(cat /tmp/qg-sdk-3-$$.out)"
fi
rm -rf "$repo" /tmp/qg-sdk-3-$$.out

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
