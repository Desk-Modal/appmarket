#!/usr/bin/env bash
#
# PreToolUse gate for Grep/Glob/Read: nudge Claude toward
# codebase-memory-mcp for code discovery.
#
# Exemptions (never blocked, never counted):
#   - Read of non-code files (markdown, JSON, YAML, TOML, lockfiles,
#     .env, logs, images, Dockerfile, Makefile, CODEOWNERS, LICENSE).
#   - Read of anything under .session-state/, .prod-check/, memory/.
#   - Any Read whose path can't be parsed (fail-open — better than
#     deadlocking on a payload shape we don't recognise).
#
# For code Reads and for every Grep/Glob:
#   - First call per session: BLOCK with an instructional stderr
#     message (forces a retry via CBM tools).
#   - 10th / 20th / 30th call: non-blocking reminder.
#   - 40th call: handoff threshold reminder.
#   - Otherwise pass silently.
#
# PPID = Claude Code process PID, unique per session. The gate dir is
# scoped to PPID so sessions do not interfere and clean up after a day.

# --- Payload resolution ---------------------------------------------------
# Hook API delivers JSON on stdin; older harnesses used env vars. Read
# stdin first, fall back to env. Fail-open if neither yields usable data.
PAYLOAD_JSON=""
if [ ! -t 0 ]; then
    PAYLOAD_JSON=$(cat 2>/dev/null || true)
fi
[ -z "$PAYLOAD_JSON" ] && [ -n "${CLAUDE_TOOL_INPUT:-}" ] && \
    PAYLOAD_JSON="$CLAUDE_TOOL_INPUT"

TOOL_NAME=""
FILE_PATH=""
if [ -n "$PAYLOAD_JSON" ] && command -v python3 >/dev/null 2>&1; then
    PARSED=$(printf '%s' "$PAYLOAD_JSON" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    print(); sys.exit(0)
ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}
name = d.get("tool_name", "") or ""
fp = ti.get("file_path", "") if isinstance(ti, dict) else ""
print(f"{name}\t{fp}")
' 2>/dev/null)
    TOOL_NAME="${PARSED%%$'\t'*}"
    FILE_PATH="${PARSED#*$'\t'}"
fi
[ -z "$TOOL_NAME" ] && TOOL_NAME="${CLAUDE_TOOL_NAME:-}"

# --- Exemption: Read of non-code content ----------------------------------
is_noncode_path() {
    case "$1" in
        *.md|*.MD|*.markdown|*.mdx)                     return 0 ;;
        *.json|*.jsonc|*.json5)                          return 0 ;;
        *.yml|*.yaml)                                    return 0 ;;
        *.toml)                                          return 0 ;;
        *.txt|*.csv|*.tsv|*.log)                         return 0 ;;
        *.ini|*.cfg|*.conf|*.properties)                 return 0 ;;
        *.env|*.env.*)                                   return 0 ;;
        *.lock|*.lockb|*.sum)                            return 0 ;;
        *.xml|*.html|*.htm|*.svg)                        return 0 ;;
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.ico)     return 0 ;;
        */Dockerfile|*/Dockerfile.*|Dockerfile)          return 0 ;;
        */.gitignore|*/.gitattributes|*/.editorconfig)   return 0 ;;
        */Makefile|*/makefile|Makefile|makefile)         return 0 ;;
        */CODEOWNERS|*/LICENSE|*/LICENSE.*)              return 0 ;;
        */.session-state/*|*/.prod-check/*)              return 0 ;;
        */memory/*|*/MEMORY.md)                          return 0 ;;
        */.claude/rules/*|*/.claude/hooks/*)             return 0 ;;
        */.claude/settings*.json|*/.mcp.json)            return 0 ;;
        */specs/personas/*|*/specs/tasks/*)              return 0 ;;
    esac
    return 1
}

if [ "$TOOL_NAME" = "Read" ] && [ -n "$FILE_PATH" ] && is_noncode_path "$FILE_PATH"; then
    exit 0
fi

# --- Counter logic --------------------------------------------------------
# Per-session counter state. PPID = Claude Code process PID, unique per
# session. CBM_GATE_DIR env override exists solely so the regression
# test in tests/ can pin the gate dir across subshells — production
# runs never set it.
GATE_DIR="${CBM_GATE_DIR:-/tmp/cbm-gate-$PPID}"
mkdir -p "$GATE_DIR" 2>/dev/null
find /tmp -maxdepth 1 -name 'cbm-gate-*' -mtime +1 -exec rm -rf {} \; 2>/dev/null

COUNTER_FILE="$GATE_DIR/counter"

if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE")
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"
else
    echo "1" > "$COUNTER_FILE"
    cat >&2 << 'MSG'
BLOCKED: Use codebase-memory-mcp tools FIRST for code discovery:
  search_graph(name_pattern="...") — find functions/classes/modules
  trace_path(function_name="...", direction="both") — call chains
  get_code_snippet(qualified_name="...") — read source via graph
  detect_changes() — map git diff to affected symbols
  get_architecture() — codebase structure overview

Non-code paths (markdown, JSON, YAML, TOML, lockfiles, logs, .env,
Dockerfile, Makefile, .session-state/, .prod-check/, memory/,
.claude/rules/, .claude/hooks/, specs/personas/, specs/tasks/) are
exempt — Read them directly. This block fires only for code files.

If this IS a code file, retry via CBM.
If this is a non-code path the hook misclassified, retry Read —
the counter is now 1 so you won't be blocked again.
MSG
    exit 2
fi

case $COUNT in
    10|20|30)
        cat >&2 << MSG
REMINDER ($COUNT Grep/Read calls this session):
  - Structural questions should use CBM first: search_graph / trace_path / get_code_snippet (~500 tokens vs ~80K).
  - If this is $COUNT calls on one problem, dispatch an Agent sub-persona per \`.claude/rules/context-discipline.md\` §6 instead of continuing inline.
  - If the session has made durable progress, write a fresh \`.session-state/handoff.md\` before context pressure forces a /clear.
MSG
        ;;
    40)
        cat >&2 << 'MSG'
THRESHOLD (40 Grep/Read calls): context-discipline handoff threshold reached.
Required next action per `.claude/rules/context-discipline.md` §1/§3:
  1. Write `.session-state/handoff.md` now.
  2. If still stuck on the same problem, dispatch an Agent sub-persona.
  3. Do not continue inline without a handoff — you risk losing durable context.
MSG
        ;;
esac

exit 0
