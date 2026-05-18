#!/usr/bin/env bash
# F157 Layer 4 TaskCompleted hook: log task completion + remind spec amend.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

EVENTS="${CWD}/.session-state/task-events.log"
mkdir -p "${CWD}/.session-state"

input=$(cat 2>/dev/null || echo '{}')
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
subj=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('subject','?'))" 2>/dev/null || echo "?")
echo "[${ts}] TaskCompleted: ${subj}" >> "$EVENTS"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "TaskCompleted",
    "additionalContext": "F157: task '${subj}' marked completed. Per architecture.md §21 spec hygiene, flip the spec.md §6 wave plan row to LANDED-<sha>-<date> in the SAME commit that flips the task."
  }
}
EOF
exit 0
