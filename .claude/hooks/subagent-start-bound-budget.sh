#!/usr/bin/env bash
# F157 Layer 4 SubagentStart hook: enforce per-session concurrent-agent cap.
# Per feedback_api_load_concurrent_agents (3-cap empirical) + F157 Layer 12.
#
# Blocks new subagent dispatch when in-flight count ≥ MAX_AGENTS_PER_SESSION.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

MAX_AGENTS="${DESKMODAL_MAX_CONCURRENT_AGENTS_PER_SESSION:-3}"
LOG_FILE="${CWD}/.session-state/subagent-log.md"
mkdir -p "${CWD}/.session-state"
touch "$LOG_FILE"

# Read JSON input from stdin
input=$(cat)
agent_type=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_type','unknown'))" 2>/dev/null || echo unknown)
agent_id=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_id','unknown'))" 2>/dev/null || echo unknown)
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Count in-flight (IN-FLIGHT markers not yet matched by STOP)
in_flight=$(grep -c '^- IN-FLIGHT' "$LOG_FILE" 2>/dev/null || echo 0)

if [ "$in_flight" -ge "$MAX_AGENTS" ]; then
  cat <<EOF
{
  "decision": "block",
  "reason": "F157 Layer 12 cost-control: ${in_flight} agent(s) already in flight (cap ${MAX_AGENTS}). Wait for one to return before dispatching '${agent_type}'."
}
EOF
  exit 2
fi

# Log dispatch
echo "- IN-FLIGHT [${ts}] agent_id=${agent_id} type=${agent_type}" >> "$LOG_FILE"

# Allow + log
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "F157: in-flight=${in_flight}/${MAX_AGENTS} after dispatching ${agent_type}"
  }
}
EOF
exit 0
