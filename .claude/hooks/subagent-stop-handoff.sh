#!/usr/bin/env bash
# F157 Layer 4 SubagentStop hook: capture subagent deliverable to handoff,
# unmark IN-FLIGHT, and optionally share a finding to the mesh.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

LOG_FILE="${CWD}/.session-state/subagent-log.md"
mkdir -p "${CWD}/.session-state"
touch "$LOG_FILE"

input=$(cat)
agent_id=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_id','unknown'))" 2>/dev/null || echo unknown)
agent_type=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('agent_type','unknown'))" 2>/dev/null || echo unknown)
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Best-effort extract first line of result (deliverable_path or summary)
result_preview=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    r = d.get('result','')
    if isinstance(r, dict):
        r = r.get('summary') or r.get('deliverable_path') or str(r)
    print(str(r)[:120].replace(chr(10),' '))
except Exception:
    print('')
" 2>/dev/null || echo "")

# Strike through the IN-FLIGHT line for this agent (mark STOPPED)
if grep -q "agent_id=${agent_id}" "$LOG_FILE"; then
  # Use sed-in-place portably (macOS + Linux)
  if sed --version >/dev/null 2>&1; then
    sed -i "s|^- IN-FLIGHT \(.*agent_id=${agent_id}.*\)|- STOPPED  \1|" "$LOG_FILE"
  else
    sed -i '' "s|^- IN-FLIGHT \(.*agent_id=${agent_id}.*\)|- STOPPED  \1|" "$LOG_FILE"
  fi
fi

echo "- STOPPED  [${ts}] agent_id=${agent_id} type=${agent_type} result='${result_preview}'" >> "$LOG_FILE"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "F157: subagent ${agent_type} (${agent_id}) returned. Result preview: ${result_preview}"
  }
}
EOF
exit 0
