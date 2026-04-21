#!/usr/bin/env bash
#
# Regression test for .claude/hooks/subagent-stop.sh.
#
# Invariants:
#   1. Hook exits 0 always (never blocks the main session).
#   2. Valid payload JSON → log entry appended with 6 tab-separated
#      fields (timestamp, agent_type, agent_id, session_id, cwd_short,
#      transcript_tail).
#   3. Missing fields default to "unknown" rather than erroring.
#   4. Malformed JSON → still exits 0, log entry with "unknown"s.
#   5. Workspace resolution prefers $CLAUDE_PROJECT_DIR; falls back to
#      walk-up from PWD.
#   6. Log file is append-only — two invocations produce two lines.

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../subagent-stop.sh"
[ -x "$HOOK" ] || { echo "hook missing or non-exec: $HOOK" >&2; exit 1; }

PASS=0
FAIL=0
fail() { printf "  FAIL: %s — %s\n" "$1" "$2" >&2; FAIL=$((FAIL + 1)); }
pass() { printf "  ok:   %s\n" "$1"; PASS=$((PASS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
WS="$TMP/ws"
mkdir -p "$WS/scripts" "$WS/.session-state"
: > "$WS/scripts/setup.sh"
: > "$WS/mise.toml"

LOG="$WS/.session-state/subagent-completions.log"

# --------- Case 1: valid payload → exit 0 + log entry ---------------
payload='{"session_id":"sess-abc","transcript_path":"/tmp/t/txn-deadbeef","cwd":"/tmp/dm-spec-T030","permission_mode":"default","hook_event_name":"SubagentStop","agent_id":"agent-xyz","agent_type":"qa-architect"}'
rc=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$WS" bash "$HOOK"; echo $?)
if [ "$rc" -eq 0 ]; then pass "valid-payload: exit 0"; \
else fail "valid-payload: exit 0" "rc=$rc"; fi
if [ -s "$LOG" ]; then
    line=$(head -1 "$LOG")
    # Count tabs: expect 5 (6 fields)
    tabcount=$(printf '%s' "$line" | tr -cd '\t' | wc -c | tr -d ' ')
    if [ "$tabcount" = "5" ]; then pass "valid-payload: 6-field TSV"; \
    else fail "valid-payload: 6-field TSV" "tabs=$tabcount line=$line"; fi
    if printf '%s' "$line" | grep -q 'qa-architect'; then
        pass "valid-payload: agent_type captured"
    else
        fail "valid-payload: agent_type captured" "line=$line"
    fi
    if printf '%s' "$line" | grep -q 'dm-spec-T030'; then
        pass "valid-payload: cwd basename captured"
    else
        fail "valid-payload: cwd basename captured" "line=$line"
    fi
else
    fail "valid-payload: log entry written" "no log file"
fi

# --------- Case 2: empty payload → exit 0 + log with "unknown"s -----
: > "$LOG"
rc=$(printf '' | CLAUDE_PROJECT_DIR="$WS" bash "$HOOK"; echo $?)
if [ "$rc" -eq 0 ]; then pass "empty-payload: exit 0"; \
else fail "empty-payload: exit 0" "rc=$rc"; fi
if [ -s "$LOG" ] && grep -q 'unknown' "$LOG"; then
    pass "empty-payload: 'unknown' fallback"
else
    fail "empty-payload: 'unknown' fallback" "log=$(cat "$LOG" 2>&1)"
fi

# --------- Case 3: malformed JSON → exit 0 + log entry with unknowns
: > "$LOG"
rc=$(printf '{ not json' | CLAUDE_PROJECT_DIR="$WS" bash "$HOOK"; echo $?)
if [ "$rc" -eq 0 ]; then pass "malformed-json: exit 0"; \
else fail "malformed-json: exit 0" "rc=$rc"; fi

# --------- Case 4: two invocations → two log lines -------------------
: > "$LOG"
printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$WS" bash "$HOOK" >/dev/null 2>&1
printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$WS" bash "$HOOK" >/dev/null 2>&1
lines=$(wc -l < "$LOG" | tr -d ' ')
if [ "$lines" = "2" ]; then pass "two-invocations: append-only"; \
else fail "two-invocations: append-only" "lines=$lines"; fi

# --------- Case 5: fallback workspace walk-up when CLAUDE_PROJECT_DIR unset
: > "$LOG"
rc=$(printf '%s' "$payload" | (cd "$WS" && CLAUDE_PROJECT_DIR= bash "$HOOK"); echo $?)
if [ "$rc" -eq 0 ]; then pass "walk-up: exit 0"; \
else fail "walk-up: exit 0" "rc=$rc"; fi
if [ -s "$LOG" ]; then pass "walk-up: log appended"; \
else fail "walk-up: log appended" "no log"; fi

echo ""
echo "subagent-stop.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
