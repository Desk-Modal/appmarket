#!/usr/bin/env bash
#
# Regression test for scripts/quality-gates/non-blocking.sh.
#
# Pins:
#   1. Empty scope (no changed Rust files) → PASS exit 0.
#   2. Added file under apps/ with `Mutex` → FAIL exit 1.
#   3. Added file under apps/ with approved primitive (ArcSwap) → PASS.
#   4. Match inside a comment is ignored.
#   5. Match inside a /tests/ directory is ignored.
#
# Each test case uses a throwaway fake workspace in /tmp so we don't
# mutate the real repo's git history. The gate script is invoked with
# --full and a per-test ROOT_DIR override (via cd into the fake
# workspace) because the gate uses its SCRIPT_DIR + ../../ to anchor
# ROOT_DIR — we pass --diff-only against the fake repo's initial
# commit to get diff-only semantics.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../../scripts/quality-gates/non-blocking.sh"

PASS=0
FAIL=0
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }

mk_fake_repo() {
    local tmp
    tmp=$(mktemp -d)
    (
        cd "$tmp" || exit 1
        git init --quiet
        git config user.email "t@t"
        git config user.name "t"
        mkdir -p myws/apps myws/crates
        cat >myws/Cargo.toml <<'TOML'
[workspace]
members = []
TOML
        # Baseline file so diff has something to compare against.
        echo "fn ok() {}" >myws/apps/hello.rs
        git add .
        git commit -q -m "init"
    )
    echo "$tmp"
}

# ---------------------------------------------------------------
# 1. Empty scope in --diff-only mode → PASS
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    # Symlink a fake scripts/quality-gates tree so the gate's SCRIPT_DIR
    # resolves into this fake repo.
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q "PASS"; then
        echo "__ok"
    else
        echo "__fail rc=$rc out=$out"
    fi
) > /tmp/qg-nb-1-$$.out
line=$(tail -1 /tmp/qg-nb-1-$$.out)
if [ "$line" = "__ok" ]; then pass "empty diff passes"; else fail "empty diff passes" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-1-$$.out

# ---------------------------------------------------------------
# 2. Added Mutex in apps/ → FAIL
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/bad.rs <<'RS'
use std::sync::Mutex;
fn bad() { let m = Mutex::new(0); drop(m); }
RS
    git add myws/apps/bad.rs && git commit -q -m "introduce lock"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 1 ] && echo "$out" | grep -q "FAIL"; then
        echo "__ok"
    else
        echo "__fail rc=$rc out=$out"
    fi
) > /tmp/qg-nb-2-$$.out
line=$(tail -1 /tmp/qg-nb-2-$$.out)
if [ "$line" = "__ok" ]; then pass "Mutex in apps/ fails"; else fail "Mutex in apps/ fails" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-2-$$.out

# ---------------------------------------------------------------
# 3. Added ArcSwap / DashMap → PASS (no banned tokens)
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/good.rs <<'RS'
use arc_swap::ArcSwap;
fn good() { let _ = ArcSwap::new(std::sync::Arc::new(0u8)); }
RS
    git add myws/apps/good.rs && git commit -q -m "use ArcSwap"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then echo "__ok"; else echo "__fail rc=$rc out=$out"; fi
) > /tmp/qg-nb-3-$$.out
line=$(tail -1 /tmp/qg-nb-3-$$.out)
if [ "$line" = "__ok" ]; then pass "ArcSwap passes"; else fail "ArcSwap passes" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-3-$$.out

# ---------------------------------------------------------------
# 4. Comment-only mention of Mutex → PASS
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/comment.rs <<'RS'
// We deliberately don't use Mutex / RwLock here.
fn ok() {}
RS
    git add myws/apps/comment.rs && git commit -q -m "doc comment"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then echo "__ok"; else echo "__fail rc=$rc out=$out"; fi
) > /tmp/qg-nb-4-$$.out
line=$(tail -1 /tmp/qg-nb-4-$$.out)
if [ "$line" = "__ok" ]; then pass "comment-only mention passes"; else fail "comment-only mention passes" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-4-$$.out

# ---------------------------------------------------------------
# 5. Mutex inside /tests/ path → PASS
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib myws/apps/tests
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/tests/fixture.rs <<'RS'
use std::sync::Mutex;
fn test_fixture() { let _ = Mutex::new(0); }
RS
    git add myws/apps/tests/fixture.rs && git commit -q -m "test fixture"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then echo "__ok"; else echo "__fail rc=$rc out=$out"; fi
) > /tmp/qg-nb-5-$$.out
line=$(tail -1 /tmp/qg-nb-5-$$.out)
if [ "$line" = "__ok" ]; then pass "Mutex in tests/ passes"; else fail "Mutex in tests/ passes" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-5-$$.out

# ---------------------------------------------------------------
# 6. Mutex inside a string literal or trailing `// ...` comment →
#    PASS (B1 scrub fix).
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/strings.rs <<'RS'
// This file deliberately mentions Mutex in prose and in strings,
// which must NOT trigger the gate.
const DOC: &str = "See our Mutex policy"; // Replaces old Mutex path
fn ok() {
    let label = "use-an-RwLock-like-that";
    drop(label);
    let _ = 0; // Mutex here is a trailing comment
}
RS
    git add myws/apps/strings.rs && git commit -q -m "strings/comments"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q "PASS"; then
        echo "__ok"
    else
        echo "__fail rc=$rc out=$out"
    fi
) > /tmp/qg-nb-6-$$.out
line=$(tail -1 /tmp/qg-nb-6-$$.out)
if [ "$line" = "__ok" ]; then pass "Mutex in strings/comments passes (B1)"; else fail "Mutex in strings/comments passes (B1)" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-6-$$.out

# ---------------------------------------------------------------
# 7. Mutex inside #[cfg(test)] mod tests { ... } → PASS (B1 fix).
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/cfg_test.rs <<'RS'
fn good() {
    let _ = 0;
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;
    #[test]
    fn fixture_uses_mutex() {
        let _ = Mutex::new(0);
    }
}
RS
    git add myws/apps/cfg_test.rs && git commit -q -m "cfg(test) mod"
    out=$(bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q "PASS"; then
        echo "__ok"
    else
        echo "__fail rc=$rc out=$out"
    fi
) > /tmp/qg-nb-7-$$.out
line=$(tail -1 /tmp/qg-nb-7-$$.out)
if [ "$line" = "__ok" ]; then pass "Mutex inside #[cfg(test)] mod passes (B1)"; else fail "Mutex inside #[cfg(test)] mod passes (B1)" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-7-$$.out

# ---------------------------------------------------------------
# 8. DESKMODAL_LAX=1 honoured — even on an otherwise-failing diff
#    the gate returns PASS and records an audit entry (A3).
# ---------------------------------------------------------------
repo=$(mk_fake_repo)
(
    cd "$repo" || exit 1
    mkdir -p scripts/quality-gates/lib
    cp "$GATE" scripts/quality-gates/non-blocking.sh
    cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
    chmod +x scripts/quality-gates/non-blocking.sh
    git add scripts && git commit -q -m "add gate"
    cat >myws/apps/lax_target.rs <<'RS'
use std::sync::Mutex;
fn lax() { let _ = Mutex::new(0); }
RS
    git add myws/apps/lax_target.rs && git commit -q -m "introduce lock"
    out=$(DESKMODAL_LAX=1 bash scripts/quality-gates/non-blocking.sh --diff-only HEAD 2>&1)
    rc=$?
    log_exists=no
    [ -f .prod-check/lax-bypass.log ] && log_exists=yes
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q "PASS" && [ "$log_exists" = yes ]; then
        echo "__ok"
    else
        echo "__fail rc=$rc log=$log_exists out=$out"
    fi
) > /tmp/qg-nb-8-$$.out
line=$(tail -1 /tmp/qg-nb-8-$$.out)
if [ "$line" = "__ok" ]; then pass "DESKMODAL_LAX bypass audited + PASS (A3)"; else fail "DESKMODAL_LAX bypass audited + PASS (A3)" "$line"; fi
rm -rf "$repo" /tmp/qg-nb-8-$$.out

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
