#!/usr/bin/env bash
# F157 Layer 4 PostCompact hook: re-inject active feature + handoff after compaction.

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

ctx="PostCompact: active=${feature}"
[ -n "$HANDOFF" ] && ctx="${ctx}; handoff=${HANDOFF}"
# Cross-session findings live in lodestar committed-knowledge (knowledge_get) + native memory.

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": "${ctx}"
  }
}
EOF
exit 0
