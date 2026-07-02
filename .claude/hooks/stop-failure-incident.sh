#!/usr/bin/env bash
# F157 Layer 4 StopFailure hook: record incident when a turn ends from API error.
# Per discipline.md §26 — state might be stale after API failure.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

mkdir -p "${CWD}/.session-state/incidents"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ts_safe=$(echo "$ts" | tr ':' '-')
sha=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || echo unknown)

input=$(cat 2>/dev/null || echo '{}')
INCIDENT="${CWD}/.session-state/incidents/${ts_safe}-${sha}.md"

{
  echo "# StopFailure incident — ${ts}"
  echo ""
  echo "## Git state"
  echo "- HEAD: ${sha}"
  git -C "$CWD" status --short 2>/dev/null | head -10
  echo ""
  echo "## Hook input"
  echo '```json'
  printf '%s\n' "$input"
  echo '```'
  echo ""
  echo "## Mitigation per F157 Layer 10"
  echo "- Re-verify by reading active spec + benchmark"
  echo "- Query lodestar knowledge_get for related verified findings/incidents"
  echo "- SendMessage to any stuck agent"
} > "$INCIDENT" 2>/dev/null

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "StopFailure",
    "additionalContext": "F157 StopFailure: incident recorded at ${INCIDENT}."
  }
}
EOF
exit 0
