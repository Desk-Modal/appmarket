#!/usr/bin/env bash
# F157 Layer 4 TaskCreated hook: append task to .session-state/task-events.log
# (advisory; spec amendment happens explicitly via /deskmodal-spec-amend).

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

EVENTS="${CWD}/.session-state/task-events.log"
mkdir -p "${CWD}/.session-state"

input=$(cat 2>/dev/null || echo '{}')
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
subj=$(printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('subject','?'))" 2>/dev/null || echo "?")
echo "[${ts}] TaskCreated: ${subj}" >> "$EVENTS"

exit 0
