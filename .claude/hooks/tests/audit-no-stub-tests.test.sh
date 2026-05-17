#!/usr/bin/env bash
# Regression test for scripts/audit-no-stub-tests.sh (G-AUDIT-47).
# Cases: 11 pub_fn / 0 tests → FAIL; 11/3 → PASS; 5/0 → PASS; allowlist → PASS.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$(cd "$HERE/../../.." && pwd)/scripts/audit-no-stub-tests.sh"
[ -x "$AUDIT" ] || { echo "FAIL: $AUDIT not executable" >&2; exit 1; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok:   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2" >&2; }
tmp=$(mktemp -d -t audit-no-stub.XXXXXX); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/platform/crates/fake-crate/src"
printf '[package]\nname = "fake-crate"\nversion = "0.0.0"\n' >"$tmp/platform/crates/fake-crate/Cargo.toml"

write_lib() {
    local n="$1" m="$2" header="${3:-}" i=1 j=1
    : >"$tmp/platform/crates/fake-crate/src/lib.rs"
    [ -n "$header" ] && echo "$header" >>"$tmp/platform/crates/fake-crate/src/lib.rs"
    while [ "$i" -le "$n" ]; do echo "pub fn fn_$i() {}" >>"$tmp/platform/crates/fake-crate/src/lib.rs"; i=$((i + 1)); done
    if [ "$m" -gt 0 ]; then
        { echo "#[cfg(test)]"; echo "mod tests {"; } >>"$tmp/platform/crates/fake-crate/src/lib.rs"
        while [ "$j" -le "$m" ]; do
            { echo "    #[test]"; echo "    fn test_$j() {}"; } >>"$tmp/platform/crates/fake-crate/src/lib.rs"
            j=$((j + 1))
        done
        echo "}" >>"$tmp/platform/crates/fake-crate/src/lib.rs"
    fi
}

write_lib 11 0
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
{ [ "$rc" = "1" ] && echo "$out" | grep -q 'fake-crate'; } && pass "11 pub_fn + 0 tests rejected" || fail "case 1" "rc=$rc out=$out"

write_lib 11 3
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "11 pub_fn + 3 tests accepted" || fail "case 2" "rc=$rc out=$out"

write_lib 5 0
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "5 pub_fn (under threshold) accepted" || fail "case 3" "rc=$rc out=$out"

write_lib 11 0 "// audit:allow-no-stub-tests: macro-emitted surface"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$AUDIT" 2>&1); rc=$?
[ "$rc" = "0" ] && pass "allowlist marker honoured" || fail "case 4" "rc=$rc out=$out"

echo ""
echo "audit-no-stub-tests.test: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
