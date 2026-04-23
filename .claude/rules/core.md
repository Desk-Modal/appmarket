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

## 4. Parallelism — minimal contract

Every task spec that will be dispatched as a pod includes:

```markdown
## Parallelism
- Reads: <paths or globs>
- Writes: <paths or globs>
- Contract produces: <named symbols this task creates>
- Contract consumes: <named symbols this task calls from peers or existing code>
```

Rules:
- Write-set disjointness is enforced at dispatch. If two pod members' Writes overlap, they run sequentially, not in parallel.
- **Contract edges force serial ordering.** If pod member A consumes what B produces, B commits first; A dispatches only after B's commit lands.
- Pod returns are **patches + verification output**, not commits. The main loop applies all patches atomically or discards all. No partial landings.
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
