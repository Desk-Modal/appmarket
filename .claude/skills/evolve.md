---
description: Self-evolving recursive improvement loop — research, critique personas, verify chart GUI, fix, evolve, repeat
user-invocable: true
---

# /evolve — Recursive Self-Improving Agent Loop

Run the full Maestro orchestration loop: evolve personas based on gaps, verify all chart capabilities inside DeskModal with screenshots, fix failures, update personas with lessons learned, recurse until state-of-the-art.

## Process

### Step 0: Evolve Personas
1. Read all personas from `specs/personas/`
2. Read `specs/GUI-AUDIT-2026-03-25.md` for known issues
3. Read `.claude/memory/` for past failures
4. For each persona, ask: "What user-reported issue did this persona fail to catch?"
5. Update any persona that has gaps
6. Commit persona updates

### Step 1: Research State of the Art
1. What does TradingView's chart do that ours doesn't? (as of March 2026)
2. What do Bloomberg Terminal, CQG, Sierra Chart offer that we should match?
3. Update `specs/personas/charting-expert.md` with any new benchmarks
4. Update `.claude/rules/trading-ux.md` with any new standards

### Step 2: Build + Deploy + Launch
1. `pnpm nx run-many --target=type-check --all` — fix errors
2. `pnpm nx run-many --target=test --all` — fix failures
3. Build all apps + price-feed service
4. Deploy to `~/.deskmodal/plugins/deskmodal/`
5. Build DeskModal frontend + Tauri backend
6. Launch DeskModal

### Step 3: Visual Verification Inside DeskModal
Run `/chart-qa` — the full chart QA suite:
- Screenshot every feature before/after interaction
- Test in BOTH tiled and modal mode
- Classify each as WORKING/DEAD/BROKEN/PARTIAL
- Delete screenshots after evaluation

### Step 4: Fix Failures
For each DEAD/BROKEN feature:
1. Read source → diagnose
2. Fix code — production-grade
3. Rebuild + redeploy + restart
4. Re-test with screenshots inside DeskModal
5. Delete screenshots

### Step 5: UX Review
Apply trading-ux-architect persona:
- Screenshot at 5 widths (minimum, 600, 800, 1200, full)
- No label overlap, no garbled text, no overflow
- All numbers tabular-nums
- Compare against TradingView

### Step 6: Evolve Personas (Post-Fix)
1. What broke that personas didn't predict?
2. Update the relevant persona's checklist
3. Add new rules if patterns emerge
4. Update `.claude/memory/` with lessons learned

### Step 7: Commit + Push Cycle Results
After EVERY cycle (regardless of whether failures remain):
1. `pnpm nx run-many --target=type-check --all` — must pass before commit
2. `pnpm nx run-many --target=test --all` — must pass before commit
3. `cargo test --manifest-path services/price-feed/Cargo.toml` — must pass before commit
4. `rm -f /tmp/chart-qa-*.png` — delete all screenshots
5. Stage all changed files in TradeSurface repo:
   ```bash
   git add -A && git commit -m "evolve: cycle N — [summary of fixes and persona updates]" && git push
   ```
6. If DeskModal repo has changes:
   ```bash
   cd /path/to/deskmodal && git add -A && git commit -m "evolve: cycle N — [summary]" && git push
   ```
7. Log cycle results to `.claude/memory/evolve-log.md` (append, don't overwrite)

### Step 8: Refresh Code Graph
- Use `detect_changes(project)` after each evolution round to identify what changed
- After structural changes: `index_repository(repo_path, mode="fast")` to re-index the code graph

### Step 9: Recurse
If failures remain from Step 3/4/5 → go to Step 2 with evolved personas from Step 6.
Each cycle builds on the last — personas get smarter, rules get tighter, the chart gets better.
Continue until zero DEAD/BROKEN features remain in the chart-qa report.

## How to Use Continuously

### Option A: Loop within a session
```
/loop 30m /evolve
```
Runs the full evolve loop every 30 minutes while your session is active.

### Option B: Scheduled remote agent
```
/schedule daily chart evolution at 2am
```
Runs autonomously overnight, commits fixes, creates issues for manual review items.

### Option C: Manual invocation
```
/evolve
```
Run once, fix everything, commit.

### Option D: Continuous session
Start a session and say:
```
Run /evolve recursively until all chart features pass visual verification inside DeskModal. Do not stop until zero failures remain. Evolve personas after each round.
```
