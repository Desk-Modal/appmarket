---
description: Prepare clean handoff state when approaching context window limits
user-invocable: true
---

# /handoff — Prepare for Context Window Limit

When approaching context limits, prepare a clean handoff so the next session can resume seamlessly.

## Usage
/handoff

## Process

### Step 1: Capture Current State
1. Run `detect_changes(project=<platform-project>  # resolve via list_projects())` to get precise list of affected symbols
2. Run `manage_adr(project=<platform-project>  # resolve via list_projects(), mode="get")` to capture architecture decisions
3. What task was being worked on?
4. What is complete? (list specific files and changes)
5. What remains? (list specific items with file paths)
6. Are there any blockers or open questions?
7. What tests pass/fail currently?

### Step 2: Write Handoff Document
Create or update the handoff memory file with:

```yaml
---
name: Active handoff state
description: Resume point for next session
type: project
---
```

Include:
- **Task**: one-line description of current task
- **Completed**: specific items with file paths
- **Remaining**: next steps with file paths and descriptions
- **Modified Files**: uncommitted changes and what changed
- **Test State**: passing/failing counts
- **Blockers**: any blockers or open questions
- **Resume Instructions**: exact next action to take

### Step 3: Update Memory Files
- Update any memory files that reflect structural changes made this session
- Ensure MEMORY.md index is current

### Step 4: Git Status
- Report `git status` and `git diff --stat`
- Recommend whether to commit current state or leave uncommitted

## Quality Gate
- [ ] Handoff document is complete and specific
- [ ] All modified files listed
- [ ] Resume instructions are actionable
- [ ] Memory files updated
- [ ] Git state documented
