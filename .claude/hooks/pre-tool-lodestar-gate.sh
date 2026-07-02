#!/usr/bin/env bash
# PreToolUse gate — enforce MCP-first discovery (core.md §3, "MCP first, always").
#
# Restores the discovery-order enforcement that core.md §3 claims exists ("Anti-patterns
# flagged by hooks"). The historical Grep|Glob|Read gate was dropped in commit 1ee02102
# ("drop noisy hooks") and never restored; this re-adds it, precisely scoped.
#
#   Grep/Glob targeting .rs/.ts/.tsx/.py  -> DENY  (use mcp__lodestar__search_graph / search_code)
#   Grep/Glob targeting wiki/**           -> DENY  (use mcp__wiki-mcp__wiki_search / wiki_get_page)
#   Read of a code file / wiki page       -> ADVISORY only (Read-before-Edit is legitimate;
#                                            prefer get_code_snippet / evidence_pack for understanding)
#
# Only fires when the call CLEARLY targets code/wiki (glob/type/path signal) — a bare
# repo-wide Grep with no code signal is allowed (conservative, low false-positive).
# Escape hatch: DESKMODAL_LAX=1 (audit-logged per quality.md §11).
set -euo pipefail

[ "${DESKMODAL_LAX:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0   # fail-open if jq missing (never break the session)

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

CODE_RE='\.(rs|ts|tsx|py)$'
CODE_GLOB_RE='\.(rs|ts|tsx|py)([,}[:space:]]|$)'

case "$tool" in
  Grep|Glob)
    path="$(printf '%s' "$input" | jq -r '.tool_input.path // empty')"
    glob="$(printf '%s' "$input" | jq -r '.tool_input.glob // empty')"
    typ="$(printf '%s' "$input" | jq -r '.tool_input.type // empty')"
    if printf '%s' "$glob" | grep -qE "$CODE_GLOB_RE" \
       || printf '%s' "$typ" | grep -qiE '^(rust|ts|tsx|typescript|py|python)$' \
       || printf '%s' "$path" | grep -qE "$CODE_RE"; then
      deny "lodestar-first (core.md §3): use mcp__lodestar__search_graph (find symbols) or mcp__lodestar__search_code (text in code) instead of Grep/Glob on .rs/.ts/.tsx/.py — ~21x fewer tokens, deterministic. Escape: DESKMODAL_LAX=1."
    fi
    if printf '%s' "$path" | grep -qE '(^|/)wiki/'; then
      deny "wiki-mcp-first (core.md §3): use mcp__wiki-mcp__wiki_search / wiki_get_page instead of Grep/Glob on wiki/**. Escape: DESKMODAL_LAX=1."
    fi
    ;;
  Read)
    fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    if printf '%s' "$fp" | grep -qE "$CODE_RE"; then
      echo "[lodestar-advisory] Reading a code file — for UNDERSTANDING prefer mcp__lodestar__get_code_snippet / evidence_pack (~21x fewer tokens). Read is fine for pre-edit context (core.md §3 / discipline.md §26)." >&2
    elif printf '%s' "$fp" | grep -qE '(^|/)wiki/'; then
      echo "[wiki-advisory] Reading wiki/** — prefer mcp__wiki-mcp__wiki_get_page (core.md §3)." >&2
    fi
    ;;
esac
exit 0
