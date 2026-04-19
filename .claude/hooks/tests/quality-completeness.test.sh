#!/usr/bin/env bash
#
# Regression test for scripts/quality-gates/completeness.sh.
#
# Pins:
#   1. Empty diff → PASS.
#   2. Added line with `// TODO: ...` in .rs → FAIL.
#   3. Added line with `unimplemented!()` in .rs → FAIL.
#   4. Added line with `console.log(...)` in .ts → FAIL.
#   5. TODO inside tests/ path → PASS (exempt).
#   6. Pre-existing TODO not modified → PASS (diff-only semantics).

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../../scripts/quality-gates/completeness.sh"

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
        mkdir -p apps crates tests
        mkdir -p scripts/quality-gates/lib
        cp "$GATE" scripts/quality-gates/completeness.sh
        cp "$(dirname "$GATE")/lib/common.sh" scripts/quality-gates/lib/common.sh
        chmod +x scripts/quality-gates/completeness.sh
        echo "fn hello() {}" >apps/main.rs
        git add . && git commit -q -m "init"
    )
    echo "$tmp"
}

run_case() {
    local desc="$1" expect_rc="$2" setup="$3"
    local repo
    repo=$(mk_repo)
    (
        cd "$repo" || exit 1
        eval "$setup"
        git add -A && git commit -q -m "case" 2>/dev/null || true
        bash scripts/quality-gates/completeness.sh --diff-only HEAD
    ) >/tmp/qg-comp-$$.out 2>&1
    local rc=$?
    if [ "$rc" -eq "$expect_rc" ]; then
        pass "$desc (rc=$rc)"
    else
        fail "$desc" "expected rc=$expect_rc got $rc; out=$(cat /tmp/qg-comp-$$.out)"
    fi
    rm -rf "$repo" /tmp/qg-comp-$$.out
}

# 1. empty diff → PASS (workdir clean after commit)
run_case "empty diff passes" 0 "echo"

# 2. TODO in added rs line
run_case "TODO in .rs fails" 1 '
cat >apps/todo.rs <<EOF
// TODO: handle the error case
fn incomplete() {}
EOF
'

# 3. unimplemented!() added
run_case "unimplemented!() fails" 1 '
cat >apps/impl.rs <<EOF
fn missing() -> u32 { unimplemented!() }
EOF
'

# 4. console.log() in .ts
run_case "console.log in .ts fails" 1 '
mkdir -p packages/foo/src
cat >packages/foo/src/bad.ts <<EOF
export function x() { console.log("debug"); }
EOF
'

# 5. TODO inside tests/ path → exempt, PASS
run_case "TODO in tests/ exempt" 0 '
cat >tests/integration.rs <<EOF
// TODO: rewrite this test
fn test() {}
EOF
'

# 6. Pre-existing TODO not in diff → PASS
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cat >apps/old.rs <<'EOF'
// TODO: old baseline
fn old() {}
EOF
    git add apps/old.rs && git commit -q -m "baseline with TODO"
    # Now make an unrelated commit.
    echo "fn other() {}" >apps/new.rs
    git add apps/new.rs && git commit -q -m "unrelated add"
    bash scripts/quality-gates/completeness.sh --diff-only HEAD
) >/tmp/qg-comp-6-$$.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "unchanged pre-existing TODO ignored"
else
    fail "unchanged pre-existing TODO ignored" "rc=$rc out=$(cat /tmp/qg-comp-6-$$.out)"
fi
rm -rf "$repo" /tmp/qg-comp-6-$$.out

# 7. B2 regression: `  debugger;` with leading whitespace in .ts file
#    must be flagged (previously the `^ *debugger;` regex never fired
#    because grep operates on `file:line:body` output).
run_case "debugger; with leading spaces in .ts fails (B2)" 1 '
mkdir -p packages/foo/src
cat >packages/foo/src/bad.ts <<EOF
export function x() {
  debugger;
  return 1;
}
EOF
'

# 8. A3: DESKMODAL_LAX bypass passes even on a violating diff,
#    writing an audit entry.
repo=$(mk_repo)
(
    cd "$repo" || exit 1
    cat >apps/lax.rs <<'EOF'
// TODO: fix later
fn x() {}
EOF
    git add apps/lax.rs && git commit -q -m "bad"
    out=$(DESKMODAL_LAX=1 bash scripts/quality-gates/completeness.sh --diff-only HEAD 2>&1)
    rc=$?
    log_ok=no
    [ -f .prod-check/lax-bypass.log ] && log_ok=yes
    if [ "$rc" -eq 0 ] && echo "$out" | grep -q "PASS" && [ "$log_ok" = yes ]; then
        echo "__ok"
    else
        echo "__fail rc=$rc log=$log_ok out=$out"
    fi
) > /tmp/qg-comp-8-$$.out
line=$(tail -1 /tmp/qg-comp-8-$$.out)
if [ "$line" = "__ok" ]; then pass "DESKMODAL_LAX bypass audited + PASS (A3)"; else fail "DESKMODAL_LAX bypass audited + PASS (A3)" "$line"; fi
rm -rf "$repo" /tmp/qg-comp-8-$$.out

echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
