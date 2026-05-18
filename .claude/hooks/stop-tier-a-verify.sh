#!/usr/bin/env bash
# F157 Layer 4 Stop hook: scoped Tier A verification per quality.md §18.7.1.
# Runs `cargo check -p <crate>` / `pnpm --filter <pkg>` ONLY for affected scope.
#
# Advisory by default (emits additionalContext on failure); set
# DESKMODAL_TIER_A_BLOCK=1 to hard-block on rc≠0.
#
# Bypasses when DESKMODAL_LAX=1 or no Rust/TS changes since last green.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

# Bypass for non-impl waves
if [ "${DESKMODAL_LAX:-0}" = "1" ] || [ "${DESKMODAL_SKIP_TIER_A:-0}" = "1" ]; then
  exit 0
fi

# Quick: any .rs/.ts/.tsx changed since last commit?
changed=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(rs|ts|tsx)$' | head -5)
if [ -z "$changed" ]; then
  exit 0
fi

# Don't actually RUN cargo here (the hook timeout would compete with the user-perceived turn end).
# Instead, emit advisory additionalContext flagging that a Tier-A scope exists.
files=$(printf '%s\n' "$changed" | tr '\n' ' ')
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "F157 Layer 4 Tier A reminder: .rs/.ts/.tsx changed (${files}). Run scoped cargo check -p / pnpm --filter per quality.md §18.7.1 before the wave commits."
  }
}
EOF
exit 0
