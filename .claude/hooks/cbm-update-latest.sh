#!/usr/bin/env bash
#
# SessionStart hook: ensure codebase-memory-mcp is up to date.
#
# Runs a non-blocking background update so session startup is not delayed.
# If the binary is missing, the next `scripts/setup.sh` run will bootstrap
# it — this hook never fails the session.
#
# Guard: once per Claude Code process (PPID).

MARKER="/tmp/cbm-update-$PPID"
[ -f "$MARKER" ] && exit 0
: > "$MARKER"
find /tmp -maxdepth 1 -name 'cbm-update-*' -mtime +1 -delete 2>/dev/null

BIN="${HOME}/.local/bin/codebase-memory-mcp"
if [ -x "$BIN" ]; then
    # Detach; writes to /tmp/cbm-update.log. Never blocks the session.
    ( "$BIN" update -y >/tmp/cbm-update.log 2>&1 & disown ) 2>/dev/null || true
fi

exit 0
