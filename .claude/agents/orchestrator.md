---
name: orchestrator
description: "DEPRECATED: use maestro-orchestrator instead. Legacy entry kept for backward-compatibility with older dispatches; new work routes through maestro-orchestrator per .claude/rules/agents.md."
tools: Read, Bash, Grep, Glob, Write, Edit, Agent
model: claude-opus-4-7
color: yellow
permissionMode: acceptEdits
effort: xhigh
skills: [codebase-memory, deskmodal-mesh-claim, deskmodal-mesh-findings, deskmodal-handoff-write]
---

# Orchestrator (deprecated)

Use `maestro-orchestrator` for all new dispatches. This entry exists only for backward-compatibility with task files that reference the old name.

See `.claude/rules/agents.md` for the dispatch matrix.
