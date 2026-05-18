#!/usr/bin/env bash
# F157 Layer 4 PreCompact hook: dump session state before context compaction.
# Per discipline.md §26 — handoff IS the solution to context pressure.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

mkdir -p "${CWD}/.session-state/handoffs"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ts_safe=$(echo "$ts" | tr ':' '-')

# Active feature
feature="unknown"
[ -f "${CWD}/.session-state/active-feature" ] && feature=$(head -1 "${CWD}/.session-state/active-feature" | tr -d '\n' || echo unknown)

# Dump key state to a pre-compact snapshot
SNAP="${CWD}/.session-state/handoffs/pre-compact-${ts_safe}.md"
{
  echo "# Pre-compact snapshot — ${ts}"
  echo ""
  echo "## Active feature: ${feature}"
  echo ""
  echo "## Git state"
  git -C "$CWD" status --short 2>/dev/null | head -20
  echo ""
  echo "## Recent commits"
  git -C "$CWD" log --oneline -10 2>/dev/null
  echo ""
  echo "## In-flight subagents"
  if [ -f "${CWD}/.session-state/subagent-log.md" ]; then
    grep '^- IN-FLIGHT' "${CWD}/.session-state/subagent-log.md" 2>/dev/null | tail -10
  fi
  echo ""
  echo "## Mesh state"
  if [ -x "${CWD}/scripts/session-mesh/check-concurrency.sh" ]; then
    bash "${CWD}/scripts/session-mesh/check-concurrency.sh" 2>&1
  fi
} > "$SNAP" 2>/dev/null

# Release mesh claim BEFORE compaction (other sessions can pick up if we don't return)
if [ -x "${CWD}/scripts/session-mesh/release-write-set.sh" ]; then
  bash "${CWD}/scripts/session-mesh/release-write-set.sh" >/dev/null 2>&1 || true
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "F157 PreCompact: snapshot at ${SNAP}; mesh claim released. Restore via PostCompact hook."
  }
}
EOF
exit 0
