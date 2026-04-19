---
description: Full SDLC execution with Maestro coordinating all agent personas
user-invocable: true
---

# /orchestrate — Maestro-Driven Task Execution

Execute a task using the full V2 SDLC process with the Maestro Orchestrator coordinating all agent personas.

## Usage
/orchestrate <task description>

## Process

Load the Maestro Orchestrator persona from `specs/personas/maestro-orchestrator.md` and follow the full SDLC loop:

### Phase 1: ORIENT
1. Read `CLAUDE.md` + `.claude/rules/*` (already loaded)
2. Use `get_architecture(project, aspects=["all"])` and `search_graph(project, query="...")` for codebase understanding before reading files
3. Check for `handoff_active.md` in memory — resume if exists
4. Read relevant specs from `specs/` based on task description
5. Read existing source code in the affected area
6. Identify: what exists, what changes, what's new

### Phase 2: PLAN
1. Decompose task into implementable units
2. For each unit, identify:
   - **Primary persona** (from `specs/personas/`) — who implements
   - **Adversarial reviewer** (from `specs/personas/`) — who critiques
   - **Quality gates** — what must pass before "done"
   - **CDP verification** — what visual state must be verified (if GUI)
3. Determine execution order (parallel where possible)
4. Present plan to user for approval before proceeding

### Phase 3: IMPLEMENT
For each unit, acting as the assigned primary persona:
1. Read the persona file from `specs/personas/{persona}.md`
2. Follow that persona's quality gates and patterns
3. Write tests alongside code
4. For GUI changes: take CDP screenshot before AND after
5. Run `pnpm nx run <project>:typecheck` after each file change

### Phase 4: ADVERSARIAL REVIEW
For each unit, acting as the assigned adversarial reviewer:
1. Read the reviewer persona file
2. Review the implementation against that persona's criteria
3. Classify findings: BLOCKING / HIGH / MEDIUM / LOW
4. BLOCKING/HIGH findings MUST be fixed before proceeding

### Phase 5: VERIFY
1. `pnpm nx run <project>:typecheck` — MUST PASS
2. `pnpm nx run <project>:test` — MUST PASS
3. CDP verification for all GUI changes
4. Bundle size check against `specs/SPEC-QUALITY-PERFORMANCE.md`

### Phase 6: DOCUMENT
1. Update memory files if architecture changed
2. Update specs if behavior changed
3. Prepare commit message (only when user asks)

## Adversarial Review Matrix
| Change Type | Primary Persona | Adversarial Reviewer |
|-------------|----------------|---------------------|
| React component | frontend-architect | trading-ux-architect + qa-architect |
| Chart rendering | charting-expert | trading-sme + qa-architect |
| Exchange adapter | data-pipeline-engineer | security-engineer + trading-sme |
| FDC3 integration | fdc3-protocol-engineer | security-engineer + integration-architect |
| Rust crate | rust-systems-architect | security-engineer + qa-architect |
| Financial calculation | data-pipeline-engineer | trading-sme (MANDATORY) |
| Price display | frontend-architect | trading-sme (MANDATORY) + trading-ux-architect |
| Any change | any | qa-architect (ALWAYS) |
