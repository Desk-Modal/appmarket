---
name: Recursive Build-Test-Audit Process
description: Multi-wave team process for building, deploying, testing, and recursively reviewing the tradesurface plugin on DeskModal
type: project
---

## Recursive Review Process — Full Plugin Build & Evaluation

**Goal:** Fully build, deploy to DeskModal, run automated GUI testing, and recursively fix all gaps/issues. Zero workarounds. 100% determinism.

### Team Structure (4 Waves)

**Wave 1: Build & Deploy** (parallel)
- Task 1: Production build all 8 apps (`TRADESURFACE_BUNDLE=1 pnpm nx run-many -t build`)
- Task 2: Validate AppD manifests + workspace templates + plugin.toml against specs
- **STATUS: COMPLETE** — All 8 apps built, 18 manifest gaps found

**Wave 2: Test & Audit** (parallel, blocked by Wave 1)
- Task 3: Run full Playwright E2E suite (12 specs, serve on ports 5173-5180)
- Task 4: Deep code audit — all 8 apps (expert: senior FDC3/trading platform architect)
- Task 5: Deep code audit — all 7 packages (expert: senior TypeScript library/perf engineer)
- **STATUS: IN PROGRESS** — 3 agents running

**Wave 3: Fix** (blocked by Wave 2)
- Task 6: Fix all issues found, grouped by severity (blocking → high → medium)
- Git commit after each stable evolution point
- **STATUS: PENDING**

**Wave 4: Recursive Validation** (blocked by Wave 3)
- Task 7: Re-run full pipeline (type-check → tests → build → bundle size → E2E)
- If issues remain, loop back to Wave 3. Continue until zero failures.
- **STATUS: PENDING**

### Agent Expert Profiles
Each audit agent must be profiled as the world's leading expert in their domain:
- E2E testing → Senior QA automation engineer, Playwright specialist
- App audit → Senior FDC3 2.2 / trading platform architect, 15yr finance + desktop interop
- Package audit → Senior TypeScript library author, performance engineer, API design expert
- Security audit → OWASP specialist, financial application security

### Environment Prerequisites
- Bitdefender: Add `D:\code\tradesurface\**/dist/` to exclusion list (prevents AV kernel locks on build output)
- After adding exclusion, reboot to release any existing file handles
- Verify: `rm -rf packages/ui-components/dist && echo OK` must succeed before proceeding

### Key Infrastructure
- Build: Nx + pnpm, Vite production builds to `apps/*/bundle/`
- Tests: Vitest (unit, ~2000+ tests), Playwright (E2E, 12 specs)
- Quality gates: Bundle size budgets per app, type-check, lint
- CI: `.github/workflows/ci.yml` (PR), `nightly.yml` (daily), `benchmark.yml` (perf)
- Manifests: `manifests/tradesurface-appd.json`, `manifests/tradesurface-templates.json`

### Known Issues Found
**Wave 1 — Build:** EPERM on `dist/` from Bitdefender kernel file locks. Root cause identified. Fix: BD exclusion + reboot.
**Wave 1 — Manifests:** 18 gaps across 3 severity levels — see findings_wave1.md
**Wave 2:** Pending agent completion

**Why:** User wants autonomous recursive quality improvement across the full plugin.
**How to apply:** Resume from the last completed wave. Check task list for current state. Always run full validation after fixes before declaring complete. Never use workarounds. Commit at evolution points.
