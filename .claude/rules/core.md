# Core rules

One file. Read this before touching the codebase. Referenced by every persona; they inherit it.

## 1. Honesty

Every factual claim cites evidence: a file:line, a command's stdout/stderr + exit code, or a persisted log path. Banned phrases unless immediately followed by a citation: "should work", "tests pass", "I believe", "probably fine". Instead, say "unverified" and propose the command that would verify.

If a claim turns out wrong: state what was wrong, what's actually true, fix the root cause. Don't minimise.

## 2. Verification — one canonical path

| Scope | Command |
|---|---|
| Per-commit sanity | `scripts/local-ci.sh --fast` |
| Rust-touching | `scripts/local-ci.sh --full` |
| GUI / FDC3 / dist touch | `scripts/launch.sh --verify` |
| Targeted visual regression | `python scripts/cdp-test-runner.py --config scripts/cdp-assertions/<name>.json` |
| Perf budget | `cargo bench --bench <bench>` (invoked by launch.sh --verify) |

Raw `cargo build|test|check|run` and `pnpm nx build|test` are dev iteration, not verification. Don't cite them in Acceptance sections.

**`rc ≠ 0` is never APPROVE.** No "failures outside my write-set" rationalisation. Either the failures were pre-existing on `origin/main` with identical signatures (cite the SHA of the passing baseline) or rc=0 is required.

## 3. Discovery order — MCP first, always

Strict priority for code (`.rs`, `.ts`, `.tsx`, `.py`):

1. **`mcp__codebase-memory-mcp__*`** — graph-indexed, ranked, file:line precise. First stop for every symbol lookup, call chain, impact analysis.
2. **`mcp__rust-analyzer__*`** — for Rust only. Symbol references, hover, diagnostics, rename prep.
3. **`mcp__playwright__browser_*`** — for visual / CDP / DOM verification. Replaces ad-hoc screenshot scripts.
4. **`mcp__github__*`** — for PR / issue / run / workflow queries. Faster than shelling to `gh`.
5. **Grep / Read** — fallback only when the MCPs return nothing useful.

Non-code (markdown, TOML, YAML, JSON, shell): Grep/Read directly.

Using Grep on a `.rs` file before querying CBM + rust-analyzer is a hallucination vector — the MCPs have context Grep doesn't.

## 4. Parallelism — single-agent default; pods reserved

**Default: ONE impl agent per wave.** Opus 4.7 with 1M ctx handles cross-stack work (Rust + Tauri command + TS bridge + React + CSS) better in one agent than three coordinated ones. Contract-edge violations become impossible because the agent owns both sides. Token cost drops ~50%.

**Pods (parallel impl agents) reserved for narrow cases only:**
- Pure CSS/token sweep (style-bot) — disjoint from any impl work.
- Perf benches (own bench files, no impl).
- Independent docs wave (no code writes).

Not a pod case: anything with Rust↔TS crossing, anything touching a Tauri command + its TS caller, anything where one persona's output is another's input.

**Reviewers are ALWAYS parallel** — dispatched in one `Agent` batch per §7. They're read-only; no race risk; the parallelism is pure wall-clock win.

Every task spec declares:

```markdown
## Parallelism
- Reads: <paths or globs>
- Writes: <paths or globs>
- Contract produces: <named symbols this wave creates>
- Contract consumes: <named symbols this wave calls from existing code>
- Dispatch shape: single-agent | pod | pipeline
```

Invariants:
- Single-agent waves use ONE `Agent()` call. The agent edits in-place and returns a unified diff via JSON (never commits).
- Pod waves (rare): write-sets MUST be pairwise disjoint. `scripts/pod-apply.sh` applies all patches atomically or rolls all back.
- Single-writer files (never written by sub-agents): `.session-state/**`, `.prod-check/**`, `specs/compat-ladder.yml`, `.specify/memory/constitution.md`, `.claude/rules/**`, `.claude/settings.json`.

No worktree mandate. Claude picks per-dispatch execution isolation.

## 5. Production code

No TODO, FIXME, HACK, placeholder, demo mode, stub, commented-out dead code in shipped code.
No `console.log` or `println!` in library crates (use the structured logger).
No versioned interfaces (`FooV2`, `NewBar`) — evolve in place.
No new locks — `ArcSwap`, `DashMap`, `flume`, atomics, or actors.
Error handling on every async op; loading state for every async UI.
Zero hardcoded absolute paths — use `${CLAUDE_PROJECT_DIR}` or computed relative.
Zero hardcoded colors in CSS/TSX — use `--deskmodal-*` / `--ts-*` tokens.

## 6. Naming

| Kind | Convention | Example |
|---|---|---|
| Components | PascalCase | `OrderBook.tsx` |
| Hooks | camelCase with `use` | `useTileKeyboard.ts` |
| Services | kebab | `feed-service.ts` |
| Types | PascalCase | `ExchangeAdapter` |
| Constants | SCREAMING_SNAKE | `MAX_RECONNECT_ATTEMPTS` |
| CSS tokens | `--ts-{category}-{property}` | `--ts-surface-primary` |
| FDC3 app IDs | `deskmodal.{name}` | `deskmodal.feeds` |

## 7. Reviewer matrix (conditional)

DeskModal is a domain-agnostic plugin platform. Reviewers are dispatched by capability, not domain:

| Signal | Mandatory reviewer |
|---|---|
| Universal (every task) | `qa-architect` |
| Rust / Tauri / platform core | `rust-systems-architect` |
| React / TSX / UI chrome | `frontend-architect` |
| Script runtime / editor / plugin SDK | `plugin-sdk-engineer` |
| Signing / ACL / auth / supply-chain / secrets | `security-engineer` |
| Plugin↔platform IPC / channels / loader | `integration-architect` |
| FDC3 channels / intents / bridge | `fdc3-protocol-engineer` |
| User-visible surface | `ux-design-lead` (review), `trading-ux-architect` (design, trading-only) |
| Plugin fixture manifest has `categories ⊇ {trading, market-data, finance, derivatives}` OR raises order/pnl/position intents | `trading-sme` **conditional** |
| Chart plugin fixture / chart engine | `charting-expert` |
| Marketplace aggregator / catalog / storefront | `marketplace-qa` |

`trading-sme` is never universal. Non-financial tasks (tile chrome, FDC3 bridge, docs) do not dispatch it.

All reviewers for a task dispatch in **one parallel `Agent` batch** (one assistant message, N tool calls). Sequential reviewer dispatch is a defect.

## 8. No deferrals

Every reviewer finding exits as one of: **CLOSED** (fixed in rework this iteration), **SCOPE-TRANSFERRED** (ownership moves to a named sibling task whose Acceptance section is amended in the same commit), or **ESCALATED** (paused for user — halts the wave). "Handle later" / "follow-up task TBD" / "track in a future ADR" is rejected.

## 9. Handoff protocol

Commit-driven. When a commit moves task state, the post-commit hook appends to the active handoff (`.session-state/handoff.md` by default, or a per-feature handoff under `.session-state/handoffs/<id>.md`). You edit free-form context on the next turn if needed.

Session pressure checkpoint: at ≥ 70% of context window, write a fresh handoff before `/clear`. Below that, commits are the durable state; no preemptive handoffs required.

## 10. Stop signals

Stop when: the task converges, the user says stop, or a blocker requires human input. Never stop because "I can't verify visually" — find another path (logs, DOM inspection, source read). Never stop without stating what verified vs what didn't.

## 11. Escape hatch

`DESKMODAL_LAX=1` bypasses any non-safety gate. Every use is audit-logged via the honesty hook. Use only when the user has authorised in-session or when diagnosing a hook false-positive.

## 12. Tool discipline

- No `--no-verify` on commits unless you've proven the hook is producing a false positive and document the diagnosis in the commit body.
- No `--force` push.
- No deleting branches, files, or data without confirming the state is recoverable.
- No invoking `sync-specs.sh --apply` while another session is actively editing sub-repo canonical files — canonical file ownership is split, see `.claude/rules/parallel-sessions.md`.
- One terminal + one cloud + one `/launch --verify` in flight at a time per machine (launch-lockfile at `/tmp/deskmodal-launch.lock`).

## 13. Autonomy protocol

Goal: user never re-pastes prompts or re-explains context. State lives in git + `.session-state/`.

On session start, the `context-load` SessionStart hook prints: active feature, branch + ahead/behind, gate state, latest handoff entry. Read that before asking the user anything.

When resuming a task:
1. Read `.session-state/handoff.md` (workspace) or `.session-state/handoffs/<feature>.md` (per-feature). Skip any hypothesis in the "Dead-ends" section.
2. Read the active feature's `spec.md` + `benchmark.md` (if applicable).
3. Re-verify live state — gates, branch, dirty files — don't trust the handoff as ground truth. Handoff is a SNAPSHOT; the gate file is LIVE.
4. Continue. Do not ask the user to re-state the goal unless you have hit a BLOCK.

Between sessions:
- A commit is the durable checkpoint. Post-commit hook appends to the handoff automatically.
- `.session-state/active-feature` (optional) holds one feature-id string; the statusline surfaces it.
- Never claim "I don't have context" — write a handoff and continue.

## 14. Output style

Claude Code default output style for this workspace is `concise`. Prefer:
- Short, dense sentences. Commands over descriptions.
- State changes and decisions directly. Cite file:line, exit codes, SHAs.
- No teaching tone. No motivational framing. No "let me explain."
- End-of-turn summary = 1-2 sentences MAX. What changed + what's next.
- Working update = 1 sentence per key moment (finding, direction change, blocker).

## 15. Wave discipline — preventing ITER-02 re-occurrence

The ITER-02 failure mode: three parallel impl Agents dispatched; one rejected by user; the other two pushed their commits; result = feature branch references symbols that don't exist. Rework: ~300K tokens.

**Structural defenses (every wave, not optional):**

1. **Pre-wave snapshot.** Before any Agent dispatch: `scripts/wave-sandbox.sh init` captures `WAVE_BASE=$(git rev-parse HEAD)` and `git stash push -u -m "pre-wave-<id>"`. Working tree guaranteed clean before dispatch.

2. **Impl Agents NEVER commit or push.** Agent instructions explicit: "edit files in-place. Do NOT `git commit`. Do NOT `git push`. Return your work as a unified diff via JSON field `patch`." The orchestrator's return-handling code rejects any response that includes a `commit_sha` — if present, `git reset --hard $WAVE_BASE` and log the persona violation to the handoff.

3. **Post-wave sanity.** After Agent returns: `scripts/wave-sandbox.sh assert-clean $WAVE_BASE` — if `HEAD != WAVE_BASE`, someone committed behind the orchestrator's back. Hard reset + rollback.

4. **Atomic integration.** `scripts/pod-apply.sh` takes the patches collected from each Agent return, applies them to a clean working tree, runs verification on integrated state, commits only on success. Any failure → `scripts/wave-sandbox.sh rollback`.

5. **Agent-rejection = wave-abort.** If any dispatched `Agent()` tool call is rejected, errors, or returns non-APPROVE, the ENTIRE wave aborts. Zero patches apply. Log the rejection reason to the handoff. Next wave re-scopes.

6. **Wave ceiling.** Max 3 rows per wave when truly independent. Max 1 row when contract edges exist between personas in the wave. Smaller waves = smaller rework cost.

7. **Shift-left scope review.** Before impl dispatch, a single `qa-architect` review pass validates the wave's `## Parallelism` section and spec Acceptance clauses. Catches contract holes at spec-time (cheap) not impl-time (expensive).

8. **Contract-edge serialization.** When the wave has persona-to-persona contract edges, serialise — never dispatch in parallel. Example: FDC3 protocol changes go FDC3-first → Rust-next → TS-last. Each step commits before the next Agent dispatches.

**Verification cadence (batching discipline):**
- `scripts/local-ci.sh --fast` runs once per wave (Phase C gate).
- `scripts/launch.sh --verify` runs once per wave (only when wave touches GUI/FDC3/dist).
- Never per-row. Never per-persona.
