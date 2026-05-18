#!/usr/bin/env bash
# F157 Layer 4 InstructionsLoaded hook: audit-only log of rule/CLAUDE.md loads.
# Drift detection — surfaces which rule files were active per session.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$CWD" || exit 0

LOG="${CWD}/.session-state/instructions-loaded.log"
mkdir -p "${CWD}/.session-state"

input=$(cat 2>/dev/null || echo '{}')
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
path=$(printf '%s' "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file_path','?'))" 2>/dev/null || echo "?")
reason=$(printf '%s' "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('load_reason','?'))" 2>/dev/null || echo "?")

echo "[${ts}] ${reason} ${path}" >> "$LOG"
exit 0
