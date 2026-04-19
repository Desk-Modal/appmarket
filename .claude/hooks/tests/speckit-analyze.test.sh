#!/usr/bin/env bash
#
# Regression tests for scripts/speckit-analyze-all.sh
#
# Creates scratch fixtures under a temp workspace and asserts each
# check behaves as documented. Exits 0 on all-pass, 1 on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ANALYZE="$ROOT_DIR/scripts/speckit-analyze-all.sh"

[ -x "$ANALYZE" ] || { echo "FAIL: speckit-analyze-all.sh missing"; exit 1; }

PASS=0
FAIL=0

mk_workspace() {
    local dir
    dir=$(mktemp -d)
    mkdir -p "$dir/specs" "$dir/.specify/memory"
    # seed a filled constitution
    cat > "$dir/.specify/memory/constitution.md" <<'EOF'
# Test Constitution
Version: 1.0.0 | Ratified: 2026-01-01 | Last Amended: 2026-01-01
EOF
    echo "$dir"
}

mk_feature() {
    local dir="$1"
    local name="$2"
    mkdir -p "$dir/specs/$name"
    cat > "$dir/specs/$name/spec.md" <<'EOF'
# Feature — test
## User Stories
### US1 (P1)
Acceptance: it works.
EOF
    echo "$dir/specs/$name"
}

run_analyze() {
    # Run from a scratch workspace by shadowing ROOT_DIR via cwd + script's
    # own relative resolution. The script uses SCRIPT_DIR/.. so we copy it
    # into the scratch workspace's scripts/ dir.
    local ws="$1"; shift
    mkdir -p "$ws/scripts"
    cp "$ANALYZE" "$ws/scripts/speckit-analyze-all.sh"
    chmod +x "$ws/scripts/speckit-analyze-all.sh"
    (cd "$ws" && bash scripts/speckit-analyze-all.sh "$@")
}

assert_pass() {
    local name="$1"; local rc="$2"
    if [ "$rc" = 0 ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (exit $rc)"
        FAIL=$((FAIL + 1))
    fi
}

assert_block() {
    local name="$1"; local rc="$2"
    if [ "$rc" = 1 ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected exit 1, got $rc)"
        FAIL=$((FAIL + 1))
    fi
}

# Case 1: clean workspace (filled constitution, feature with only spec.md) → PASS
ws=$(mk_workspace)
mk_feature "$ws" "001-clean" >/dev/null
run_analyze "$ws" >/dev/null 2>&1
assert_pass "case 1 — clean workspace" $?
rm -rf "$ws"

# Case 2: constitution has placeholders → BLOCK
ws=$(mk_workspace)
cat > "$ws/.specify/memory/constitution.md" <<'EOF'
# [PROJECT_NAME] Constitution
### [PRINCIPLE_1_NAME]
[PRINCIPLE_1_DESCRIPTION]
EOF
mk_feature "$ws" "001-any" >/dev/null
run_analyze "$ws" >/dev/null 2>&1
assert_block "case 2 — constitution placeholders" $?
rm -rf "$ws"

# Case 3: spec.md newer than tasks.md → BLOCK
ws=$(mk_workspace)
fdir=$(mk_feature "$ws" "002-stale-tasks")
cat > "$fdir/tasks.md" <<'EOF'
# Tasks
- [ ] T1 {persona: rust-systems-architect, reviewers: qa-architect}
EOF
# Make tasks.md older than spec.md
touch -t 202001010000 "$fdir/tasks.md"
run_analyze "$ws" >/dev/null 2>&1
assert_block "case 3 — tasks.md older than spec.md" $?
rm -rf "$ws"

# Case 4: tasks.md row missing persona: → BLOCK
ws=$(mk_workspace)
fdir=$(mk_feature "$ws" "003-no-persona")
cat > "$fdir/tasks.md" <<'EOF'
# Tasks
- [ ] T1 implement the thing
EOF
run_analyze "$ws" >/dev/null 2>&1
assert_block "case 4 — tasks.md row missing persona:" $?
rm -rf "$ws"

# Case 5: tasks.md row missing reviewers: → BLOCK
ws=$(mk_workspace)
fdir=$(mk_feature "$ws" "004-no-reviewer")
cat > "$fdir/tasks.md" <<'EOF'
# Tasks
- [ ] T1 implement {persona: rust-systems-architect}
EOF
run_analyze "$ws" >/dev/null 2>&1
assert_block "case 5 — tasks.md row missing reviewers:" $?
rm -rf "$ws"

# Case 6: spec.md with template placeholders → BLOCK
ws=$(mk_workspace)
mkdir -p "$ws/specs/005-unfilled"
cat > "$ws/specs/005-unfilled/spec.md" <<'EOF'
# Feature Specification: [FEATURE NAME]
Created: [DATE]
Branch: [###-feature-name]
EOF
run_analyze "$ws" >/dev/null 2>&1
assert_block "case 6 — spec.md template placeholders" $?
rm -rf "$ws"

# Case 7: --feature filter → scope analysis to one dir
ws=$(mk_workspace)
mk_feature "$ws" "001-clean" >/dev/null
fdir=$(mk_feature "$ws" "002-broken")
cat > "$fdir/tasks.md" <<'EOF'
- [ ] T1 thing with no annotations
EOF
# Filter to clean dir only → PASS even though 002 is broken
run_analyze "$ws" --feature 001-clean >/dev/null 2>&1
assert_pass "case 7 — --feature filter scopes analysis" $?
rm -rf "$ws"

# Case 8: --format json emits valid JSON
ws=$(mk_workspace)
mk_feature "$ws" "001-clean" >/dev/null
out=$(run_analyze "$ws" --format json 2>/dev/null)
if printf '%s' "$out" | python3 -c 'import sys, json; json.load(sys.stdin)' 2>/dev/null; then
    echo "PASS: case 8 — --format json is valid JSON"
    PASS=$((PASS + 1))
else
    echo "FAIL: case 8 — --format json rejected by json.load"
    FAIL=$((FAIL + 1))
fi
rm -rf "$ws"

echo ""
echo "speckit-analyze: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
