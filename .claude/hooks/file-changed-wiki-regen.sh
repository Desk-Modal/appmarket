#!/usr/bin/env bash
# F157 Layer 4 FileChanged hook: queue wiki regen when SDK manifest or specs change.
# Doesn't run regen synchronously (too slow for hook timeout); just sets a flag.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

QUEUE="${CWD}/.session-state/wiki-regen.queue"
mkdir -p "${CWD}/.session-state"

input=$(cat 2>/dev/null || echo '{}')
path=$(printf '%s' "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file_path','?'))" 2>/dev/null || echo "?")
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

case "$path" in
  *plugin.toml|*sdk*/package.json|specs/*/spec.md)
    echo "[${ts}] ${path}" >> "$QUEUE"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "F157: wiki regen queued for ${path}. Run scripts/wiki-gen-*.sh at next checkpoint."
  }
}
EOF
    ;;
  *)
    # Not a watched path; pass
    ;;
esac
exit 0
