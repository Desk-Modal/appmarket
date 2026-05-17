---
title: marketplace/appmarket/wiki — index (MIRROR)
entity_type: governance
owner_persona: documentation-engineer
last_verified_against_sha: 0106036876e3712d039b0fa1e121276d4109605d
auto_generated: true
evidence_sources:
  - canonical:wiki/CLAUDE.md
status: draft
schema_version: 1
---

<!-- auto-generated — do NOT hand-edit -->
<!-- regenerate via: scripts/wiki-mirror.sh (from root) -->
<!-- mirror-source-sha: 0106036876e3712d039b0fa1e121276d4109605d -->
<!-- generated-at: 2026-05-17T04:36:42Z -->

# marketplace/appmarket/wiki — index

Sub-repo wiki for `marketplace/appmarket`. Local-detail synthesis specific to
this repo. The root wiki holds cross-cutting synthesis; see federation
map at root `wiki/index.md`.

## Schema

This sub-repo's `wiki/CLAUDE.md` is a mirror of the root schema.
Edits to schema happen at the root session per
`.claude/rules/parallel-sessions.md` canonical-file ownership.

## Federation

- Root wiki: `wiki://root/` → repo root `wiki/`
- Schema: `wiki/CLAUDE.md` (mirrored from root, edit at root only)
- Cross-repo links: `wiki://<repo>/<path>` (resolved by wiki-mcp
  Wave 3+ or sub-repo working trees as fallback)

## Status

Bootstrapped (mirror schema + index stub only). Local-detail content
will be authored by sessions whose `CLAUDE_PROJECT_DIR` points at
`marketplace/appmarket`, per `.claude/rules/parallel-sessions.md`. Until then,
this directory holds only the mirrored schema and this stub.
