---
description: Full codebase quality audit against project standards
user-invocable: true
---

# /audit — Full Codebase Quality Audit

Perform a comprehensive quality audit of the specified scope.

## Usage
/audit [scope]

Scopes:
- `all` — full codebase
- `apps` — all 8 apps
- `packages` — all packages
- `<name>` — specific app or package (e.g., `feeds`, `data-layer`)
- `security` — security-focused audit (DeskModal)
- `fdc3` — FDC3 compliance audit

## Process

### Step 1: Inventory
- Use `get_architecture(project, aspects=["all"])` for structural overview of the codebase
- Use `search_graph(project, query="...")` to find all definitions in scope
- List all files in scope
- Count exports, components, hooks, services
- Identify dependency graph for scope

### Step 2: Static Analysis
- Run typecheck: `pnpm nx run <project>:typecheck`
- Check for dead exports (exported but never imported)
- Check for dead code (`todo!()`, `unimplemented!()`, commented blocks)

### Step 3: Pattern Compliance
- Component pattern: forwardRef, data-ts-*, ensureXStyles(), --ts-* tokens
- Test pattern: co-located *.test.ts, userEvent interactions, axe assertions
- Export pattern: barrel exports via index.ts
- State pattern: Jotai atoms + Zustand stores
- FDC3 pattern: context types, intent handlers, channel management

### Step 4: Deep Review
- Architecture: separation of concerns, single responsibility
- Error handling: all error paths covered, no silent failures
- Performance: no main-thread blocking, bounded data structures
- Accessibility: ARIA, keyboard, screen reader
- Security: no hardcoded secrets, no unsafe eval, CSP compliance

### Step 5: Report
Generate findings with severity classification:
- BLOCKING: prevents build or causes runtime crash
- HIGH: incorrect behavior, data corruption, a11y failure
- MEDIUM: code smell, performance concern, pattern violation
- LOW: style inconsistency, documentation gap

Write findings to memory file: `findings_{scope}_{date}.md`

## Quality Gate
Audit is NOT complete until:
- [ ] All files in scope have been reviewed
- [ ] Findings are classified by severity
- [ ] Remediation plan exists for BLOCKING and HIGH items
- [ ] Memory file updated with findings
