#!/usr/bin/env bash
# F157 Layer 4 SessionEnd hook: final handoff capture + release mesh claim.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ts_safe=$(echo "$ts" | tr ':' '-')

# Capture final state
mkdir -p "${CWD}/.session-state/handoffs"
SNAP="${CWD}/.session-state/handoffs/session-end-${ts_safe}.md"
{
  echo "# Session end — ${ts}"
  echo ""
  echo "## Git state"
  git -C "$CWD" status --short 2>/dev/null | head -20
  echo ""
  echo "## Final commits"
  git -C "$CWD" log --oneline -5 2>/dev/null
  echo ""
  echo "## Mesh state at exit"
  if [ -x "${CWD}/scripts/session-mesh/check-concurrency.sh" ]; then
    bash "${CWD}/scripts/session-mesh/check-concurrency.sh" 2>&1
  fi
} > "$SNAP" 2>/dev/null

# Release mesh claim
if [ -x "${CWD}/scripts/session-mesh/release-write-set.sh" ]; then
  bash "${CWD}/scripts/session-mesh/release-write-set.sh" >/dev/null 2>&1 || true
fi

exit 0
