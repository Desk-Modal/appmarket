#!/usr/bin/env bash
#
# SessionStart hook: remind Claude to use codebase-memory-mcp tools for
# code discovery instead of Grep/Read. Fires once per session.
#
# Shipped in-repo so every developer working on DeskModal gets the nudge
# via `.claude/settings.json` — no user-level Claude config required.

# Guard: fire once per Claude Code process (PPID = Claude PID).
MARKER="/tmp/cbm-reminder-$PPID"
[ -f "$MARKER" ] && exit 0
: > "$MARKER"
find /tmp -maxdepth 1 -name 'cbm-reminder-*' -mtime +1 -delete 2>/dev/null

cat << 'REMINDER'
## Code Discovery Protocol (MANDATORY)

You have a persistent knowledge graph of this codebase via codebase-memory-mcp.
It is ALWAYS faster and cheaper than Grep/Read for structural queries.

**ALWAYS use CBM tools FIRST:**
- `search_graph(name_pattern="...", label="Function|Class|Module")` — find symbols
- `trace_path(function_name="...", direction="both", depth=3)` — call chains & impact
- `get_code_snippet(qualified_name="...")` — read function source (~500 tokens vs ~80K)
- `detect_changes()` — map current git diff to affected symbols with blast radius
- `get_architecture(aspects=["packages","routes","hotspots"])` — structural overview
- `search_code(pattern="...")` — graph-augmented grep (faster, ranked results)

**Use Grep/Read ONLY for:** config files, YAML, TOML, markdown, string literals, non-code content.

**On session start:** Call `list_projects` to verify the index exists. If missing or stale, call `index_repository`.

**For subagents:** Include "Use codebase-memory-mcp search_graph/trace_path before reading files" in every Agent prompt.
REMINDER
