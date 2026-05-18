---
name: deskmodal-spec-amend
description: Atomically update spec.md + benchmark.md per architecture.md §21 spec-hygiene. Use after any wave lands to flip §6 wave plan row + benchmark acceptance row + open-concern dispositions in ONE commit.
when_to_use: A wave just committed; need to update the parent spec to reflect LANDED state
disable-model-invocation: true
allowed-tools: Edit Read Bash(git add specs/*) Bash(git commit:*) Bash(git log:*) Bash(git rev-parse:*)
effort: medium
---

# DeskModal spec-amend skill

F157 Layer 2 helper — enforces `architecture.md §21` spec-hygiene contract.

## Current spec status

!`git log --oneline -3 specs/ 2>/dev/null | head -3`

## Instructions

The user invoked this skill to amend a spec. Arguments: `$ARGUMENTS` (typically `<spec-slug> <wave-id> <status>` e.g. `156 P1-A LANDED`).

Per `architecture.md §21`, every wave commit MUST atomically update:

1. **§6 wave plan row** — flip QUEUED → IN-FLIGHT → LANDED-<sha>-<date>. Cite the actual commit SHA.

2. **`benchmark.md` row** — mark acceptance status (GREEN / IN-FLIGHT / SCOPE-TRANSFERRED-TO-<wave> / ESCALATED). Cite verification evidence path.

3. **`§Open concerns` dispositions** — per `quality.md §18.1`, every `open_concern` exits as CLOSED-IN-WAVE / SCOPE-TRANSFERRED-TO-{NAMED-WAVE} / ESCALATED-TO-USER.

4. **`§Implementation status` block** (if present) — running tally GREEN / IN-FLIGHT / NOT-STARTED.

5. **Cross-references** — when this wave affects sibling specs, add one-line cross-ref entry citing this commit.

## The commit

After amending, commit with:

```
git add specs/<NNN-slug>/spec.md specs/<NNN-slug>/benchmark.md
git commit -m "feat(F<NNN>-<wave>): <subject>\n\nSpec hygiene per architecture.md §21:\n- spec.md §6 wave plan: <wave> → LANDED-<sha>-<date>\n- benchmark.md: <row> → GREEN evidence cited"
```

## Verification

After commit:
- `git log --oneline -1 specs/<NNN-slug>/` shows the spec-amend commit
- `grep 'LANDED-' specs/<NNN-slug>/spec.md` shows the new row
- `grep -c 'GREEN' specs/<NNN-slug>/benchmark.md` increased by ≥1

## Banned

- "We'll update the spec in the next wave" — banned per `quality.md §18.1`
- Reviewer findings closed in-wave NOT reflected in spec's `§Open concerns` table — invisible compliance
- Wave landing WITHOUT same-commit spec update — stale documentation
