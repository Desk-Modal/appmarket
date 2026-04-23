#!/usr/bin/env bash
# SessionStart hook — auto-install any missing DeskModal plugins.
#
# Runs `scripts/install-plugins.sh --check` first (fast, no writes).
# If anything is missing, invokes the full installer once, then continues
# normally. Silent on steady state.
#
# Ensures every developer's first Claude Code session after `git clone`
# or `git pull` has the workspace's recommended plugins — no manual
# step required.

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INSTALLER="$ROOT/scripts/install-plugins.sh"

[ -x "$INSTALLER" ] || exit 0

# Quick check — if all plugins installed, silent exit.
if "$INSTALLER" --check >/dev/null 2>&1; then
    exit 0
fi

# Something missing. Emit a single line to stderr, then run the installer.
echo "▸ auto-installing missing Claude Code plugins (one-time bootstrap)..." >&2
"$INSTALLER" 2>&1 | sed 's/^/  /' >&2

exit 0
