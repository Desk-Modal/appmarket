---
description: Code review against project quality standards
user-invocable: true
---

# /review — Code Review Against Standards

Review staged or recent changes against project quality standards.

## Usage
/review [scope]

Scopes:
- `staged` — review staged git changes (default)
- `branch` — review all commits on current branch vs main
- `pr` — review a specific PR (provide URL or number)
- `file <path>` — review a specific file

## Process

### Step 1: Gather Changes
- `git diff --cached` (staged) or `git diff main...HEAD` (branch)
- Identify affected files, components, and packages
- Use `trace_path(project, from, to)` to verify call chains and `detect_changes(project)` to scope the review

### Step 2: Check Against Standards
For each changed file, verify:

#### TypeScript/React
- [ ] Component follows forwardRef + data-ts-* + ensureXStyles pattern
- [ ] Uses --ts-* tokens, not hardcoded values
- [ ] Uses usePress, not onClick for buttons
- [ ] Has co-located test file with meaningful assertions
- [ ] No `any` types without documented justification
- [ ] Exports via barrel index.ts
- [ ] Error boundaries around async operations
- [ ] Accessibility: ARIA labels, keyboard support

#### Rust
- [ ] Error types use thiserror
- [ ] Logging uses tracing, not println
- [ ] No unwrap() on user data paths
- [ ] Platform-specific code behind cfg with trait abstraction
- [ ] Tests use real state, not mocks (except cfg(test))
- [ ] No unsafe without safety docs

#### Both
- [ ] No dead code (TODO, commented blocks, unused exports)
- [ ] No duplicate implementations
- [ ] No versioned interfaces
- [ ] No placeholders, stubs, or workarounds
- [ ] Memory files updated if architecture changed

### Step 3: Report
- List violations grouped by severity
- Suggest specific fixes with file paths and line numbers
- Approve if zero BLOCKING/HIGH issues

## Quality Gate
Review is NOT complete until:
- [ ] All changed files examined
- [ ] Violations classified by severity
- [ ] Specific fix suggestions provided for each violation
