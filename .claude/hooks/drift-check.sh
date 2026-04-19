#!/usr/bin/env bash
#
# SessionStart hook — detect when the workspace's committed developer
# environment has changed (typically after a `git pull`) and auto-apply
# the changes by re-running the idempotent `scripts/setup.sh --config-only`
# step. This keeps every developer's hooks, MCP configs, sub-repo
# scaffolding, and Claude Code rules in lockstep with the checked-in
# source of truth without requiring a manual run.
#
# Strategy:
#   1. Locate the workspace root by walking up from this script's dir (the
#      copy in a sub-repo is a few levels deeper; the workspace has
#      `scripts/setup.sh` and `mise.toml` at its root).
#   2. Hash the committed files that together define the "env contract":
#      scripts/setup.sh, scripts/install-codebase-memory-mcp.sh,
#      mise.toml, workspace .mcp.json + .claude/settings.json + .claude/hooks.
#   3. Compare to the last-applied hash stored in tools/.setup-sync-hash.
#   4. If they differ, run `scripts/setup.sh --config-only --quiet` and
#      update the stored hash. If the CBM binary is missing, prompt the
#      developer to run the full setup.
#   5. Never block the session. All output goes to stderr so Claude can
#      read it but the session proceeds regardless.
#
# Guarded to fire once per Claude Code process (PPID = Claude PID).

MARKER="/tmp/drift-check-$PPID"
[ -f "$MARKER" ] && exit 0
: > "$MARKER"
find /tmp -maxdepth 1 -name 'drift-check-*' -mtime +1 -delete 2>/dev/null

# Find workspace root: nearest ancestor containing scripts/setup.sh.
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
WORKSPACE=$(locate_workspace "$PWD") || \
    WORKSPACE=$(locate_workspace "$(cd "$(dirname "$0")" && pwd)") || exit 0

HASH_FILE="$WORKSPACE/tools/.setup-sync-hash"
mkdir -p "$WORKSPACE/tools"

# Portable sha256 — shasum on macOS, sha256sum on Linux/Git Bash.
sha_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
    sha_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    sha_cmd="shasum -a 256"
else
    # No hash tool available — skip drift detection silently.
    exit 0
fi

# Hash the env-contract files. Sort for determinism across runs.
current_hash=$(
    {
        [ -f "$WORKSPACE/scripts/setup.sh" ]                           && cat "$WORKSPACE/scripts/setup.sh"
        [ -f "$WORKSPACE/scripts/install-codebase-memory-mcp.sh" ]     && cat "$WORKSPACE/scripts/install-codebase-memory-mcp.sh"
        [ -f "$WORKSPACE/scripts/lib/generate_tradesurface_manifests.py" ] && cat "$WORKSPACE/scripts/lib/generate_tradesurface_manifests.py"
        [ -f "$WORKSPACE/mise.toml" ]                                  && cat "$WORKSPACE/mise.toml"
        [ -f "$WORKSPACE/.mcp.json" ]                                  && cat "$WORKSPACE/.mcp.json"
        [ -f "$WORKSPACE/.claude/settings.json" ]                      && cat "$WORKSPACE/.claude/settings.json"
        find "$WORKSPACE/.claude/hooks" -type f -name "*.sh" 2>/dev/null | sort | while read -r f; do cat "$f"; done
        find "$WORKSPACE/.claude/agents" -type f -name "*.md" 2>/dev/null | sort | while read -r f; do cat "$f"; done
        [ -f "$WORKSPACE/.specify/memory/constitution.md" ]             && cat "$WORKSPACE/.specify/memory/constitution.md"
    } | $sha_cmd | awk '{print $1}'
)

stored_hash=""
[ -f "$HASH_FILE" ] && stored_hash=$(cat "$HASH_FILE" 2>/dev/null || echo "")

if [ "$current_hash" = "$stored_hash" ] && [ -x "$WORKSPACE/tools/codebase-memory-mcp" ]; then
    # No drift and CBM binary present — nothing to do.
    exit 0
fi

# Drift detected (or first run, or missing binary). Run the idempotent
# config-only path and refresh the hash. Output goes to stderr so Claude
# Code can surface the message without treating it as tool output.
{
    echo ""
    if [ -z "$stored_hash" ]; then
        echo "[drift-check] first run in this workspace — bootstrapping Claude Code config…"
    elif [ ! -x "$WORKSPACE/tools/codebase-memory-mcp" ]; then
        echo "[drift-check] codebase-memory-mcp binary missing — installing…"
    else
        echo "[drift-check] workspace dev env changed since last session — applying updates…"
    fi
    echo "[drift-check] running scripts/setup.sh --config-only (safe, idempotent)"
} >&2

if "$WORKSPACE/scripts/setup.sh" --config-only --quiet >>"$WORKSPACE/tools/drift-check.log" 2>&1; then
    echo "$current_hash" > "$HASH_FILE"
    echo "[drift-check] applied — see tools/drift-check.log" >&2
else
    echo "[drift-check] WARN: setup.sh --config-only failed — see tools/drift-check.log" >&2
fi

exit 0
