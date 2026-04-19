#!/usr/bin/env bash
#
# SessionStart hook — surfaces the active session handoff and current
# gate state so the resumed session starts with durable context instead
# of trying to reconstruct it from prior messages.
#
# Wired in .claude/settings.json under hooks.SessionStart.

set -u

ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HANDOFF="$ROOT_DIR/.session-state/handoff.md"
STATUS="$ROOT_DIR/.prod-check/status.json"
COUNTERS="$ROOT_DIR/.session-state/counters.json"

# Fresh session → reset the tool-budget counter so thresholds are
# per-session, not cumulative across the user's entire history. The
# `tool-budget.sh` hook initialises the file on its next call.
rm -f "$COUNTERS" 2>/dev/null

echo "## Session context discipline"
echo
echo "Per \`.claude/rules/context-discipline.md\`:"
echo "  - Read the handoff below BEFORE acting."
echo "  - Cite evidence for every claim."
echo "  - Re-verify the gate state — the handoff is a snapshot, not a guarantee."
echo "  - Write a fresh handoff before context pressure forces a /clear."
echo

if [ -f "$HANDOFF" ]; then
    echo "### Active handoff: \`.session-state/handoff.md\`"
    echo "\`\`\`markdown"
    cat "$HANDOFF"
    echo "\`\`\`"
else
    echo "No active handoff at \`.session-state/handoff.md\`."
    echo "Write one when context pressure builds or on stop-and-escalate."
fi

echo

if [ -f "$STATUS" ]; then
    echo "### Last gate snapshot: \`.prod-check/status.json\`"
    echo "\`\`\`json"
    cat "$STATUS"
    echo "\`\`\`"
    echo
    echo "Re-run \`.claude/scripts/optiscript-prod-check.sh\` before trusting this."
    echo
fi

echo "### Enforcement wired this session"
echo
echo "- \`PreToolUse:*\` → \`.claude/hooks/tool-budget.sh\` — blocks further work when 40 tool calls elapse without a fresh handoff, or when 40 Grep/Read calls elapse without any CBM call. Counters live in \`.session-state/counters.json\`."
echo "- \`PreToolUse:Grep|Glob|Read\` → \`.claude/hooks/cbm-code-discovery-gate.sh\` — blocks the first Grep/Read per session; escalates at 10/20/30/40."
echo "- \`Stop\` → \`.claude/hooks/handoff-nudge.sh\` — nudges to write a handoff if uncommitted work exists and the handoff is stale."
echo "- Bypass: \`export DESKMODAL_LAX=1\` (audit: the hooks print the bypass flag when active)."
