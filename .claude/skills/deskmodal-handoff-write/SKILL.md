---
name: deskmodal-handoff-write
description: Write a session handoff per discipline.md §26 schema. Use before /clear, at 70% context utilisation, or before a major scope pivot.
when_to_use: Context near full OR about to /clear OR about to hand off to another session
allowed-tools: Read Write Edit Bash(git status:*) Bash(git log:*)
effort: medium
---

# DeskModal handoff-write

F157 Layer 2 — codifies the per `discipline.md §26` handoff format.

## Active state

!`git status --short`
!`git log --oneline -3`

## Instructions

Write `.session-state/handoffs/<feature>.md` (or `.session-state/handoff.md` for workspace-scope) with EXACTLY these sections:

```markdown
# Session handoff — <ISO timestamp>

## Task
<one sentence — what the user asked for>

## Current gate / checklist state
<paste from .prod-check/status.json or equivalent>

## What this session achieved
- <bullet — must cite file paths or gate names>
- <bullet — must cite evidence>

## Dead-ends (do NOT retry these)
- <hypothesis> — <why it was disproved> — <evidence path>

## Open work, in priority order
1. <concrete next step with the exact command>
2. <…>

## Files modified this session
<git status --short output>

## Flags to the next session
- Auth state: <e.g. "sub-agent dispatch requires re-login first">
- Environment: <anything unusual>

## Mesh share
<topics + summaries to share via scripts/session-mesh/share-finding.sh>
```

After writing the handoff:
1. `git add .session-state/handoffs/...` if it's tracked (else gitignored is fine)
2. Optionally `bash scripts/session-mesh/share-finding.sh handoff-<feature> 'summary of work + open work'`

## Output

The handoff file path + a 3-bullet summary for the chat.
