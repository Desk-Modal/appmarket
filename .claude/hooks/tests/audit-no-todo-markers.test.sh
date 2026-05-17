#!/usr/bin/env bash
# Regression test for scripts/audit-no-todo-markers.sh (G-AUDIT-49).
# Pins: (1) clean tree → rc=0; (2) TODO/FIXME/HACK/XXX in shipped .rs → rc=1;
# (3) same-line audit:allow-todo marker silences → rc=0; (4) hit under exempt
# path (tests/, fixtures/, dist/) → rc=0.
set -u
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/audit-no-todo-markers.sh"
[ -r "$GATE" ] || { echo "FAIL: $GATE not found" >&2; exit 1; }
chmod +x "$GATE" 2>/dev/null || true
PASS=0; FAIL=0
p() { printf "  ok:   %s\n" "$1"; PASS=$((PASS+1)); }
f() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL+1)); }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLAUDE_PROJECT_DIR="$1" bash "$GATE" 2>&1; }

# 1. Clean — no markers anywhere.
mkdir -p "$tmp/clean/platform/src"
printf 'pub fn used() -> u32 { 42 }\n' > "$tmp/clean/platform/src/lib.rs"
out=$(run "$tmp/clean"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "clean → rc=0" || f "clean" "rc=$rc out=$out"

# 2. Dirty — TODO/FIXME in shipped .rs.
mkdir -p "$tmp/dirty/platform/src"
printf '// TODO: rewrite this\npub fn x() {}\n// FIXME: leaks\npub fn y() {}\n' > "$tmp/dirty/platform/src/lib.rs"
out=$(run "$tmp/dirty"); rc=$?
{ [ "$rc" = 1 ] && echo "$out" | grep -qE "FAIL: [0-9]+"; } && p "dirty → rc=1 + FAIL" || f "dirty" "rc=$rc out=$out"

# 3. Allowlisted — same-line marker silences.
mkdir -p "$tmp/allow/platform/src"
printf '// TODO: defer to v2 // audit:allow-todo: tracked in F140 spec\npub fn x() {}\n' > "$tmp/allow/platform/src/lib.rs"
out=$(run "$tmp/allow"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "allowlist → rc=0" || f "allowlist" "rc=$rc out=$out"

# 4. Path-exempt — hit under tests/ is silently ignored.
mkdir -p "$tmp/exempt/platform/tests"
printf '// TODO: this is a test fixture\npub fn t() {}\n' > "$tmp/exempt/platform/tests/fix.rs"
out=$(run "$tmp/exempt"); rc=$?
{ [ "$rc" = 0 ] && echo "$out" | grep -q OK; } && p "exempt path → rc=0" || f "exempt" "rc=$rc out=$out"

printf "\nPassed: %d  Failed: %d\n" "$PASS" "$FAIL"; [ "$FAIL" = 0 ]
