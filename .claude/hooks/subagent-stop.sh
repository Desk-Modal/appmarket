#!/usr/bin/env bash
#
# SubagentStop hook — fires when a subagent (dispatched via the Agent
# tool) terminates. Anthropic-documented event per
# https://code.claude.com/docs/en/hooks .
#
# Purpose: give the main /loop a structured trail of parallel-dispatch
# fan-in, so Phase-3 review completion and Phase-6 integration can be
# audited. The main loop never blocks on this hook — it only reads
# the log after all expected SubagentStop events arrive.
#
# Non-blocking (always exits 0). Payload schema per Anthropic docs:
#   {
#     "session_id": "...",
#     "transcript_path": "...",
#     "cwd": "...",
#     "permission_mode": "...",
#     "hook_event_name": "SubagentStop",
#     "agent_id": "...",
#     "agent_type": "..."
#   }
#
# We persist: timestamp, agent_type, agent_id, cwd basename, and the
# last 60 chars of transcript_path (just enough to correlate with the
# parent wave). Append-only to
# $CLAUDE_PROJECT_DIR/.session-state/subagent-completions.log.

set -u

# Read JSON payload from stdin (Anthropic hook convention).
payload=$(cat 2>/dev/null || echo '{}')

# Extract fields without requiring jq — fall back to grep on the
# hottest fields so this hook is dependency-free. jq is used when
# available.
extract() {
    local key="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r ".$key // empty" 2>/dev/null
    else
        printf '%s' "$payload" \
          | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
          | head -1 \
          | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
    fi
}

agent_type=$(extract agent_type)
agent_id=$(extract agent_id)
session_id=$(extract session_id)
cwd=$(extract cwd)
transcript=$(extract transcript_path)

# Resolve workspace root (same walk-up pattern as drift-check.sh).
locate_workspace() {
    local d="${1:-$PWD}"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -f "$d/scripts/setup.sh" ] && [ -f "$d/mise.toml" ]; then
            echo "$d"
            return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}

WS=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && \
   [ -f "$CLAUDE_PROJECT_DIR/scripts/setup.sh" ] && \
   [ -f "$CLAUDE_PROJECT_DIR/mise.toml" ]; then
    WS="$CLAUDE_PROJECT_DIR"
fi
if [ -z "$WS" ]; then
    WS=$(locate_workspace "$PWD") || \
        WS=$(locate_workspace "$(cd "$(dirname "$0")" && pwd)") || exit 0
fi

LOG="$WS/.session-state/subagent-completions.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# cwd basename — "/tmp/dm-spec-T030" → "dm-spec-T030" tells the main
# loop which worktree this agent landed on.
cwd_short=$(basename "${cwd:-unknown}")

# Transcript tail — last 60 chars (typically the UUID) — just enough to
# correlate with Agent's return value to the main loop.
transcript_tail="${transcript: -60}"

iso=$(date -u +%FT%TZ)

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iso" \
    "${agent_type:-unknown}" \
    "${agent_id:-unknown}" \
    "${session_id:-unknown}" \
    "${cwd_short:-unknown}" \
    "${transcript_tail:-unknown}" \
    >> "$LOG" 2>/dev/null || true

exit 0
