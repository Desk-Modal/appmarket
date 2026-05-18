---
name: deskmodal-mesh-claim
description: Declare this Claude session's write-set bounds to the mesh + check for conflicts with other active sessions. Per F157 Layer 11. Use at SessionStart.
when_to_use: Session start; about to begin work on a feature/program; want to coordinate with other parallel sessions
allowed-tools: Bash(scripts/session-mesh/*) Read
effort: low
---

# DeskModal mesh claim

F157 Layer 11 — declare this session's write-set + check for conflicts.

## Mesh state

!`bash ${CLAUDE_SKILL_DIR}/../../../scripts/session-mesh/check-concurrency.sh`

## Instructions

Arguments: `$ARGUMENTS` — typically `<feature-id> <program-description> <write-set-globs-csv> [<excludes-csv>]`.

If arguments empty, ask the user for:
- Feature id (e.g., `F156`)
- Program description (e.g., `core-server-api SOTA evolution`)
- Write-set includes (globs, comma-separated; e.g., `core-server-api/**,specs/156-core-server-api-sota/**`)
- Write-set excludes (optional)

Then run:

```bash
bash scripts/session-mesh/claim-write-set.sh "$1" "$2" "$3" "$4"
```

If rc=0 → claim accepted; print the claim path.
If rc=1 → conflict detected; print the conflict details + resolution options.

## Output

Claim status + active-session inventory + concurrency-cap state.
