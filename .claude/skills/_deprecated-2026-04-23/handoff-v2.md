---
description: Persist session state for seamless handoff to next session
user-invocable: true
---

# /handoff — Context Persistence for Session Transition

When approaching context limits or ending a session, prepare a clean handoff so the next session can resume seamlessly.

## Usage
/handoff

## Process

### Step 1: Capture Current State
1. Run `detect_changes(project=<platform-project>  # resolve via list_projects())` to capture affected symbols
2. Run `manage_adr(project=<platform-project>  # resolve via list_projects(), mode="get")` to include architecture decisions
3. What task was being worked on?
2. What is complete? (list specific files and changes)
3. What remains? (list specific items with file paths)
4. Are there any blockers or open questions?
5. What tests pass/fail currently?
6. Which agent personas were active?

### Step 2: Write Handoff Document

Create or update `.claude/memory/handoff_active.md`:

```markdown
---
name: Active handoff state
description: Resume point for next session — {task description}
type: handoff
timestamp: {ISO 8601}
agents_involved: [{list of active personas}]
---

## Task
{One-line description}

## Completed
- {File path}: {what was done}

## Remaining
1. {Next step — exact action with file path}
2. {Following step}

## Quality Gate Status
- Typecheck: PASS / FAIL (which errors)
- Tests: PASS / FAIL (which failing)
- CDP: VERIFIED / NOT YET (which apps)
- Adversarial review: DONE / PENDING (which personas)

## Modified Files (uncommitted)
- {path}: {change summary}

## Memory Files Updated
- {path}: {what was added/changed}

## Resume Instructions
1. Read this file
2. Read {specific memory files}
3. Read {specific source files}
4. Start with: {exact next action}
5. Delete this file once work is resumed
```

### Step 3: Update Memory Files
- Update any memory files that reflect structural changes made this session
- Ensure memory index is current

### Step 4: Git Status
- Report `git status` and `git diff --stat`
- Recommend whether to commit current state or leave uncommitted

## Quality Gate
Handoff is NOT complete until:
- [ ] Handoff document is complete and specific
- [ ] All modified files listed
- [ ] Resume instructions are actionable (not vague)
- [ ] Memory files updated
- [ ] Git state documented
