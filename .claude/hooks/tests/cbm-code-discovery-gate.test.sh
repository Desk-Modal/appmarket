#!/usr/bin/env bash
#
# Regression test for cbm-code-discovery-gate.sh.
#
# Invariants this test pins:
#   1. Read of a non-code path (markdown, JSON, YAML, TOML, lockfile,
#      .env, Dockerfile, Makefile, .session-state/, .prod-check/,
#      memory/, .claude/rules/, .claude/hooks/, specs/personas/,
#      specs/tasks/, .claude/settings*.json, .mcp.json) always passes
#      silently and does NOT advance the counter.
#   2. First Read of a code path (.rs, .ts, …) returns exit 2 with the
#      block message, creating the counter at 1.
#   3. Subsequent Reads of code paths pass silently and advance the
#      counter monotonically.
#   4. Grep/Glob (no file_path in payload) always advance the counter.
#   5. Broken JSON payloads fail open (exit 0), so the hook never
#      deadlocks the agent on a payload shape it doesn't recognise.
#
# The hook keys its counter off $PPID. Every test case spawns its own
# subshell via bash -c, so each bash -c instance has a distinct PID —
# but the hook's PPID is the PID of *this* script, not the subshell.
# We clean the gate dir between logical groups to reset state.
#
# Exit status: 0 on pass, non-zero on any failure.

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../cbm-code-discovery-gate.sh"
# Pin gate dir via env override so it survives $(...) subshells. The
# hook's CBM_GATE_DIR knob exists only for this test; production uses
# $PPID-based paths.
GATE="/tmp/cbm-gate-test-$$"
export CBM_GATE_DIR="$GATE"

cleanup() { rm -rf "$GATE"; }
trap cleanup EXIT

PASS=0
FAIL=0
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }

call_hook() {
    local payload="$1"
    local stderr_file="$2"
    printf '%s' "$payload" | bash "$HOOK" 2>"$stderr_file"
    echo $?
}

counter_value() { cat "$GATE/counter" 2>/dev/null || echo ""; }

# --------------------------------------------------------------------
# Group 1 — non-code Reads are exempt
# --------------------------------------------------------------------
rm -rf "$GATE"
stderr=$(mktemp)

for path in \
    "/Users/x/proj/.claude/settings.json" \
    "/Users/x/proj/.mcp.json" \
    "/Users/x/proj/README.md" \
    "/Users/x/proj/memory/MEMORY.md" \
    "/Users/x/proj/.session-state/handoff.md" \
    "/Users/x/proj/.prod-check/status.json" \
    "/Users/x/proj/config/desk.toml" \
    "/Users/x/proj/docker-compose.yml" \
    "/Users/x/proj/pnpm-lock.yaml" \
    "/Users/x/proj/.env" \
    "/Users/x/proj/.env.local" \
    "/Users/x/proj/Dockerfile" \
    "/Users/x/proj/Makefile" \
    "/Users/x/proj/LICENSE" \
    "/Users/x/proj/specs/personas/rust.md" \
    "/Users/x/proj/.claude/rules/honesty.md" \
    "/Users/x/proj/.claude/hooks/foo.sh"
do
    rc=$(call_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$path\"}}" "$stderr")
    if [ "$rc" -eq 0 ] && [ ! -s "$stderr" ]; then
        pass "exempt: $(basename "$path")"
    else
        fail "exempt: $(basename "$path")" "rc=$rc stderr=$(cat "$stderr")"
    fi
done
if [ -z "$(counter_value)" ]; then
    pass "exempt reads never create counter"
else
    fail "exempt reads never create counter" "counter=$(counter_value)"
fi

# --------------------------------------------------------------------
# Group 2 — first code Read is blocked; retry passes
# --------------------------------------------------------------------
rm -rf "$GATE"

rc=$(call_hook '{"tool_name":"Read","tool_input":{"file_path":"/proj/src/main.rs"}}' "$stderr")
if [ "$rc" -eq 2 ] && grep -q "BLOCKED:" "$stderr"; then
    pass "first code Read is blocked"
else
    fail "first code Read is blocked" "rc=$rc"
fi
if [ "$(counter_value)" = "1" ]; then
    pass "block creates counter=1"
else
    fail "block creates counter=1" "counter=$(counter_value)"
fi

rc=$(call_hook '{"tool_name":"Read","tool_input":{"file_path":"/proj/src/main.rs"}}' "$stderr")
if [ "$rc" -eq 0 ]; then
    pass "retried code Read passes"
else
    fail "retried code Read passes" "rc=$rc"
fi
if [ "$(counter_value)" = "2" ]; then
    pass "retry increments counter to 2"
else
    fail "retry increments counter to 2" "counter=$(counter_value)"
fi

# --------------------------------------------------------------------
# Group 3 — non-code Read after first block does NOT advance counter
# --------------------------------------------------------------------
rc=$(call_hook '{"tool_name":"Read","tool_input":{"file_path":"/proj/CHANGELOG.md"}}' "$stderr")
if [ "$rc" -eq 0 ] && [ "$(counter_value)" = "2" ]; then
    pass "non-code Read does not advance counter"
else
    fail "non-code Read does not advance counter" "rc=$rc counter=$(counter_value)"
fi

# --------------------------------------------------------------------
# Group 4 — Grep/Glob (no file_path) always count
# --------------------------------------------------------------------
rc=$(call_hook '{"tool_name":"Grep","tool_input":{"pattern":"foo"}}' "$stderr")
if [ "$rc" -eq 0 ] && [ "$(counter_value)" = "3" ]; then
    pass "Grep advances counter"
else
    fail "Grep advances counter" "rc=$rc counter=$(counter_value)"
fi

rc=$(call_hook '{"tool_name":"Glob","tool_input":{"pattern":"**/*.rs"}}' "$stderr")
if [ "$rc" -eq 0 ] && [ "$(counter_value)" = "4" ]; then
    pass "Glob advances counter"
else
    fail "Glob advances counter" "rc=$rc counter=$(counter_value)"
fi

# --------------------------------------------------------------------
# Group 5 — broken JSON fails open
# --------------------------------------------------------------------
rc=$(call_hook 'not valid json at all' "$stderr")
if [ "$rc" -eq 0 ]; then
    pass "broken JSON fails open"
else
    fail "broken JSON fails open" "rc=$rc"
fi

# --------------------------------------------------------------------
# Group 6 — reminder fires at 10/20/30
# --------------------------------------------------------------------
rm -rf "$GATE"
# Prime counter to 9 so next Grep hits 10.
mkdir -p "$GATE" && echo 9 > "$GATE/counter"
rc=$(call_hook '{"tool_name":"Grep","tool_input":{"pattern":"foo"}}' "$stderr")
if [ "$rc" -eq 0 ] && grep -q "REMINDER (10" "$stderr"; then
    pass "reminder fires at 10th call"
else
    fail "reminder fires at 10th call" "rc=$rc stderr=$(cat "$stderr")"
fi

# Prime to 39 so next call hits 40.
echo 39 > "$GATE/counter"
rc=$(call_hook '{"tool_name":"Grep","tool_input":{"pattern":"foo"}}' "$stderr")
if [ "$rc" -eq 0 ] && grep -q "THRESHOLD (40" "$stderr"; then
    pass "handoff threshold fires at 40th call"
else
    fail "handoff threshold fires at 40th call" "rc=$rc stderr=$(cat "$stderr")"
fi

rm -f "$stderr"

# --------------------------------------------------------------------
echo
printf "Passed: %d    Failed: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
