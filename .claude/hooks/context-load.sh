#!/usr/bin/env bash
# SessionStart hook — loads persistent context so the user never re-pastes.
# Lean replacement for the 4 hooks removed in commit 1ee0210.
#
# Prints (when useful):
#   - Active handoff (.session-state/handoff.md or per-feature handoff)
#   - Current branch
#   - Latest gate state (.prod-check/status.json if present)
#   - Active feature (from .session-state/active-feature if present)
#
# Silent on clean state. Fast (<50ms). No network, no grep, no MCP calls.

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE="$ROOT/.session-state"

print_section() {
    [ -z "$2" ] && return
    printf '\n▸ %s\n%s\n' "$1" "$2"
}

# 0. Mesh bootstrap — the durable resume contract (anti-scrap; 2026-06-10).
# A fresh/cleared session re-adopts every standing approach from these
# three files BEFORE dispatching anything. Ledger NEXT row surfaced inline
# so the next unit of work is visible without a read.
if [ -f "$ROOT/specs/SOTA-MASTER/SESSION-BOOTSTRAP.md" ]; then
    next_row=$(grep -m1 '^| 1 | S-' "$ROOT/specs/SOTA-MASTER/DELIVERY-LEDGER.md" 2>/dev/null | cut -c1-160)
    print_section "mesh bootstrap (READ FIRST)" "specs/SOTA-MASTER/SESSION-BOOTSTRAP.md → DELIVERY-LEDGER.md + PROGRESS-TRACKER.md before ANY dispatch${next_row:+
ledger next: $next_row}"
fi

# 1. Active feature
if [ -f "$STATE/active-feature" ]; then
    feature=$(cat "$STATE/active-feature")
    print_section "active feature" "$feature"
fi

# 2. Branch
branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$branch" ]; then
    ahead=$(git -C "$ROOT" rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0)
    behind=$(git -C "$ROOT" rev-list --count "HEAD..origin/main" 2>/dev/null || echo 0)
    dirty=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    status="branch=$branch  ahead=$ahead  behind=$behind  dirty=$dirty"
    print_section "git" "$status"
fi

# 3. Gate state (per-domain or workspace)
for st in "$ROOT/.prod-check/status.json" "$ROOT/.prod-check/platform/status.json"; do
    [ -f "$st" ] || continue
    summary=$(python3 -c "
import json, sys
try:
    s=json.load(open('$st'))
    p=s.get('pass',0); f=s.get('fail',0); b=s.get('blocked',0)
    fails=[r.get('name','') for r in s.get('results',[]) if r.get('state')=='FAIL']
    print(f'pass={p} fail={f} blocked={b}', end='')
    if fails: print(' | failing:', ', '.join(fails), end='')
except: sys.exit(0)
" 2>/dev/null)
    [ -n "$summary" ] && print_section "gate state ($(basename $(dirname $st)))" "$summary"
done

# 4. lodestar (code graph) presence — the engine auto-indexes on MCP connect and a
#    native filesystem watcher keeps the graph fresh, so there is no manual
#    index_repository nudge. Just flag if the binary is missing so /mcp isn't empty.
if ! command -v lodestar >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/lodestar" ]; then
    print_section "lodestar" "code-graph MCP not on PATH — install: curl -fsSL https://raw.githubusercontent.com/soarsa/lodestar/main/install.sh | bash"
fi

# 5. Active handoff — show path + last 2 entries of "What this iteration closed"
for hf in "$STATE/handoffs/tile-experience-sota.md" "$STATE/handoff.md"; do
    [ -f "$hf" ] || continue
    # Surface handoff path + most recent iteration entry (single line)
    latest=$(grep -E '^\| 20[0-9]{2}-' "$hf" 2>/dev/null | tail -1)
    [ -z "$latest" ] && latest=$(head -1 "$hf" 2>/dev/null | tr -d '#' | sed 's/^ *//')
    print_section "handoff: $hf" "$latest"
    break
done

exit 0
