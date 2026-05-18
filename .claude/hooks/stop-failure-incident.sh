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
  echo "- Check mesh findings for related incidents"
  echo "- Per architecture.md §28.7, SendMessage to any stuck agent"
} > "$INCIDENT" 2>/dev/null

# Share to the mesh so other sessions learn
if [ -x "${CWD}/scripts/session-mesh/share-finding.sh" ]; then
  bash "${CWD}/scripts/session-mesh/share-finding.sh" \
    "stop-failure-incident-${sha}" \
    "Turn ended with API error at ${ts}; see ${INCIDENT}" \
    "$INCIDENT" \
    "this-program" >/dev/null 2>&1 || true
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "StopFailure",
    "additionalContext": "F157 StopFailure: incident recorded at ${INCIDENT}; finding shared to mesh."
  }
}
EOF
exit 0
