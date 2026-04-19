---
description: Adversarial review using domain-hostile personas
user-invocable: true
---

# /critique — Adversarial Review on Demand

Run an adversarial review of specified code using domain-hostile personas.

## Usage
/critique <scope>

Scopes:
- `staged` — review staged git changes (default)
- `<file-path>` — review a specific file
- `<app-name>` — review an entire app
- `<package-name>` — review an entire package
- `all` — review all uncommitted changes

## Process

### Step 1: Identify Changes
- `git diff --cached` (staged) or `git diff` (unstaged) or read specified files
- Use `search_graph(project, query="...")` and `trace_path(project, from, to)` to find all code paths affected by the change
- Categorize each change by type (component, data, security, financial, etc.)

### Step 2: Assign Adversarial Reviewers
Using the matrix from `specs/personas/maestro-orchestrator.md`:
- Load each assigned reviewer persona from `specs/personas/`
- Apply their specific review criteria and checklists

### Step 3: Run Reviews (in parallel where possible)

**QA Architect** (runs on ALL changes):
- Load `specs/personas/qa-architect.md`
- Apply: compile check, test check, behavior test check, production-grade check, simplicity check

**Trading SME** (runs on ANY financial logic/display):
- Load `specs/personas/trading-sme.md`
- Apply: calculation correctness, price display rules, domain accuracy

**Trading UX Architect** (runs on ANY visual change):
- Load `specs/personas/trading-ux-architect.md`
- Apply: chart-first hierarchy, information density, keyboard support, TradingView benchmark

**Security Engineer** (runs on data/auth/IPC changes):
- Load `specs/personas/security-engineer.md`
- Apply: threat model, input validation, trust boundary analysis

**FDC3 Protocol Engineer** (runs on cross-app communication):
- Load `specs/personas/fdc3-protocol-engineer.md`
- Apply: FDC3 compliance, feature detection, fallback paths

### Step 4: CDP Verification (if GUI changes detected)
For any visual changes, run via CDP:
1. `Page.captureScreenshot` — capture current state
2. `Runtime.evaluate` — run DOM assertions from the relevant persona
3. Report any assertion failures as findings

### Step 5: Report
Output findings in this format:

```
## Adversarial Review Report

### Reviewer: {persona}
| # | Severity | Category | Description | File:Line | Fix |
|---|----------|----------|-------------|-----------|-----|
| 1 | BLOCKING | ... | ... | ... | ... |

### Summary
- BLOCKING: {count} (must fix before commit)
- HIGH: {count} (must fix before commit)
- MEDIUM: {count} (tracked, fix when possible)
- LOW: {count} (tracked)
```

## Verdict
- **APPROVE**: Zero BLOCKING + zero HIGH findings
- **BLOCK**: Any BLOCKING finding exists
- **REQUEST CHANGES**: Zero BLOCKING but HIGH findings exist
