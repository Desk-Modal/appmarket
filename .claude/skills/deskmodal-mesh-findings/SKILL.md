---
name: deskmodal-mesh-findings
description: List recent findings from other Claude sessions' mesh bus, OR share a finding to the mesh. Per F157 Layer 11 inter-session learning.
when_to_use: SessionStart context surfacing; OR after a wave that produced a cross-session-relevant pattern
allowed-tools: Bash(scripts/session-mesh/*)
effort: low
---

# DeskModal mesh findings

F157 Layer 11 — cross-session knowledge bus.

## Recent findings (last 24h, from other sessions)

!`ROOT=$(bash "${CLAUDE_SKILL_DIR}/../_lib/dm-root.sh") && bash "$ROOT/scripts/session-mesh/list-findings.sh" --since 24 --from-others`

## All recent findings (last 24h, all sessions)

!`ROOT=$(bash "${CLAUDE_SKILL_DIR}/../_lib/dm-root.sh") && bash "$ROOT/scripts/session-mesh/list-findings.sh" --since 24`

## Instructions

Arguments: `$ARGUMENTS`.

- **List mode** (no args, OR args contain `list`): just surface findings to context (the dynamic-context blocks above already did this).

- **Share mode** (args contain `share <topic> <summary> [<evidence-path>]`): write a finding via:
  ```bash
  bash scripts/session-mesh/share-finding.sh "<topic>" "<summary>" "<evidence>" "this-program"
  ```

- **Promote mode** (args contain `promote <topic>`): if a finding is durable cross-session-cross-machine, promote to `~/.claude/projects/-Users-adrian-deskmodal/memory/feedback_<topic>.md` AND update `MEMORY.md` index.

## Output

For share: the finding's file path. For list: the surfaced findings already shown via dynamic context. For promote: the memory file path + MEMORY.md index entry.
