#!/usr/bin/env bash
#
# SessionStart hook: ensure codebase-memory-mcp is up to date.
#
# Runs a non-blocking background self-update against the workspace-
# vendored CBM binary at ${CLAUDE_PROJECT_DIR}/tools/codebase-memory-mcp.
# If the binary is missing the hook exits 0 — the next
# scripts/setup.sh or scripts/setup.sh --config-only run bootstraps it
# via scripts/install-codebase-memory-mcp.sh. This hook never blocks
# the session.
#
# Resolution order for the workspace root:
#   1. $CLAUDE_PROJECT_DIR (injected by Claude Code).
#   2. Walk up from $PWD looking for scripts/setup.sh + mise.toml
#      (same pattern as drift-check.sh).
#   3. Walk up from this script's own directory.
#
# Guarded to fire once per Claude Code process (PPID = Claude PID).

MARKER="/tmp/cbm-update-$PPID"
[ -f "$MARKER" ] && exit 0
: > "$MARKER"
find /tmp -maxdepth 1 -name 'cbm-update-*' -mtime +1 -delete 2>/dev/null

locate_workspace() {
    local d="${1:-$PWD}"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -f "$d/scripts/setup.sh" ] && [ -f "$d/mise.toml" ]; then
            echo "$d"
            return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}

WORKSPACE=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && \
   [ -f "$CLAUDE_PROJECT_DIR/scripts/setup.sh" ] && \
   [ -f "$CLAUDE_PROJECT_DIR/mise.toml" ]; then
    WORKSPACE="$CLAUDE_PROJECT_DIR"
fi
if [ -z "$WORKSPACE" ]; then
    WORKSPACE=$(locate_workspace "$PWD") || \
        WORKSPACE=$(locate_workspace "$(cd "$(dirname "$0")" && pwd)") || exit 0
fi

BIN="$WORKSPACE/tools/codebase-memory-mcp"
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) BIN="$WORKSPACE/tools/codebase-memory-mcp.exe" ;;
esac

if [ -x "$BIN" ]; then
    ( "$BIN" update -y >/tmp/cbm-update.log 2>&1 & disown ) 2>/dev/null || true
fi

exit 0
