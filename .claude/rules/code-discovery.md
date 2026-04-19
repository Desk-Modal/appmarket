# Code Discovery Rules (codebase-memory-mcp)

## Graph-First Discovery (MANDATORY — every code question)

Before using Grep, Glob, or Read to find code, ALWAYS check the indexed graph first. The graph has pre-computed function signatures, call chains, type relationships, and cross-file dependencies — Grep only has text.

### Primary Tools (use BEFORE Grep/Glob/Read)

| Tool | When to use | Example |
|------|------------|---------|
| `search_graph(project, query)` | Find functions, types, routes by keyword | `search_graph(project=<platform-project>, query="dispatch intent")` |
| `search_graph(project, name_pattern)` | Find by exact name regex | `search_graph(project=<platform-project>, name_pattern=".*Handler.*")` |
| `trace_path(project, from, to)` | Trace call chains between functions | `trace_path(project=<platform-project>, from="dispatch_loop", to="broadcast")` |
| `get_code_snippet(project, qualified_name)` | Read source by qualified name (faster than Read) | `get_code_snippet(project=<platform-project>, qualified_name="crate::state::DeskModalState")` |
| `get_architecture(project, aspects)` | High-level crate/module structure | `get_architecture(project=<platform-project>, aspects=["all"])` |
| `detect_changes(project)` | Map git diff to affected symbols with risk | `detect_changes(project=<platform-project>)` |
| `search_code(project, query)` | Full-text search within indexed files | `search_code(project=<platform-project>, query="actor pattern")` |
| `query_graph(project, query)` | Cypher-like structural queries | `query_graph(project=<platform-project>, query="MATCH (f:Function)-[:CALLS]->(g) RETURN f.name, g.name LIMIT 10")` |
| `manage_adr(project, mode)` | Read/update Architecture Decision Records | `manage_adr(project=<platform-project>, mode="get")` |
| `index_status(project)` | Check if index is healthy/stale | `index_status(project=<platform-project>)` |

### Fallback (ONLY when graph returns no results)
- `Grep` — text content search, config values, string literals
- `Glob` — find files by name pattern
- `Read` — read specific known files

## Indexed Projects

CBM derives the project name from the absolute repo path at index time, so
project names vary per developer (e.g. one machine has
`Users-alice-deskmodal-platform`, another has `home-bob-deskmodal-platform`).
**Never hardcode names** — always resolve via `list_projects()` at session
start.

`scripts/setup.sh` indexes these repos by default:

| Role | Workspace location | Contents |
|------|-------------------|----------|
| platform | `platform/` | DeskModal agent + 28 platform crates |
| tradesurface | `plugins/tradesurface/` | 10 web apps, TS packages, services |
| optiscript | `plugins/optiscript/` | OptiScript runtime + editor |
| plugin-tools | `plugin-tools/` | dmpkg signing / verify CLI |
| appmarket | `marketplace/appmarket/` | plugin marketplace registry |
| plugin-index | `marketplace/plugin-index/` | plugin discovery index |
| core-server-api | `core-server-api/` | backend control plane |

**If a project shows as stale or missing**, re-index from the workspace
root (absolute path is still required by the indexer — compute once,
don't bake into any committed artefact):
```
index_repository(repo_path="$(pwd)/platform", mode="fast")
index_repository(repo_path="$(pwd)/plugins/tradesurface", mode="fast")
```

## Auto-Reindex

- **auto_index is ON** — the MCP server automatically re-indexes when files change
- After **major structural changes** (new crates, moved modules): `index_repository(mode="full")`
- After **minor changes** (new functions, edited methods): `mode="fast"` suffices
- **At session start**: run `index_status` — reindex if node count seems low

## Session Bootstrap (every session start)

1. `list_projects()` → read the names CBM has indexed on THIS machine (they encode the repo path).
2. `index_status(project=<platform-project>)` → verify healthy
3. `index_status(project=<tradesurface-project>)` → verify healthy
4. `manage_adr(project=<platform-project>, mode="get")` → load architecture decisions
5. If stale or missing: `index_repository(repo_path="$(pwd)/<sub-repo>", mode="fast")`

## Cross-Project Discovery

When tracing a feature across platform → plugin (e.g., ServiceSDK → bridge → app):
1. Search each project's graph independently
2. Use `trace_path` within each project for internal call chains
3. Match on exported types/functions at the SDK boundary

## Why Graph-First Matters

- `search_graph` returns ranked results with file:line — no guessing
- `trace_path` shows the actual call chain — no manual grep-and-follow
- `get_code_snippet` reads source by qualified name — no path lookup needed
- `detect_changes` maps git diffs to impacted functions — no manual tracing
- `get_architecture` gives crate structure instantly — no directory crawling
- Avoiding unnecessary file reads keeps context window lean
