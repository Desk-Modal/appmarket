#!/usr/bin/env bash
# F157 Layer 4 PostCompact hook: re-inject handoff + mesh-findings after compaction.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

# Find most recent handoff
HANDOFF=""
if [ -d "${CWD}/.session-state/handoffs" ]; then
  HANDOFF=$(ls -t "${CWD}/.session-state/handoffs"/*.md 2>/dev/null | head -1)
fi

# Active feature
feature="unknown"
[ -f "${CWD}/.session-state/active-feature" ] && feature=$(head -1 "${CWD}/.session-state/active-feature" | tr -d '\n' || echo unknown)

# Last 24h findings from the mesh
findings=""
if [ -x "${CWD}/scripts/session-mesh/list-findings.sh" ]; then
  findings=$(bash "${CWD}/scripts/session-mesh/list-findings.sh" --since 24 2>/dev/null | head -10)
fi

ctx="F157 PostCompact: active=${feature}"
[ -n "$HANDOFF" ] && ctx="${ctx}; handoff=${HANDOFF}"
[ -n "$findings" ] && ctx="${ctx}; mesh findings:\n${findings}"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": "${ctx}"
  }
}
EOF
exit 0
