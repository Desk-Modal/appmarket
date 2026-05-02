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

Strict priority. **Two MCPs share top tier** — pick by question shape:

| Question shape | First MCP |
|---|---|
| "Where is symbol X / what calls Y / what does Z look like / impact analysis" — **code-structure facts** | `mcp__codebase-memory-mcp__*` (CBM symbol graph) |
| "How does the FDC3 bridge work / what's the brand voice / which persona owns Y / what playbook covers Z / what governance applies / cross-cutting synthesis" — **synthesis facts** | `mcp__wiki-mcp__*` (wiki synthesis layer) |

Then in priority order:

1. **`mcp__codebase-memory-mcp__*`** — code symbol graph; first stop for every code-structure question for `.rs`, `.ts`, `.tsx`, `.py`.
2. **`mcp__wiki-mcp__*`** — cross-cutting synthesis from `wiki/` (84 root pages + 7 sub-repo mirrors). First stop for any synthesis question. Tools: `wiki_search`, `wiki_get_page`, `wiki_get_links`, `wiki_check_staleness`, `wiki_get_visual`.
3. **`mcp__rust-analyzer__*`** — for Rust only. Symbol references, hover, diagnostics, rename prep.
4. **`mcp__playwright__browser_*`** — for visual / CDP / DOM verification. Replaces ad-hoc screenshot scripts.
5. **`mcp__github__*`** — for PR / issue / run / workflow queries. Faster than shelling to `gh`.
6. **Grep / Read** — fallback only when the MCPs return nothing useful, AND only for non-code/non-wiki content.

Non-code, non-wiki (markdown specs, TOML, YAML, JSON, shell): Grep/Read directly.

**Anti-patterns flagged by hooks:**
- Grep on `.rs` / `.ts` / `.tsx` / `.py` before CBM = hallucination vector.
- Grep / Read on `wiki/**` paths before wiki-mcp = same. The wiki has its own MCP for a reason.

Specs and rules are *cited from*, not *discovered through*. Use the active feature spec for current intent; use rules/agents for workflow contract; use CBM for code; use wiki-mcp for synthesis.

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

## 15. Wave discipline — evolve-and-fix-forward (NEVER ROLL BACK)

**Cardinal rule: every wave moves forward.** Reviewer REWORK / BLOCK / HIGH findings close via a **subsequent commit on top of the current HEAD**, never via `git reset --hard`, `git revert`, or any destructive rewind. Rollback is banned as a wave-mechanic because it discards partial-value work the next wave would otherwise build on.

**The four invariants (replace the old rollback-based ITER-02 mitigations):**

1. **Impl Agents NEVER commit or push.** Agent instructions explicit: "edit files in-place. Do NOT `git commit`. Do NOT `git push`. Return your work as a unified diff via JSON field `patch`." If an agent returns `commit_sha` (committed behind the orchestrator): the orchestrator reconciles by adding a follow-up commit that completes the contract (never resets). The violation is logged to the handoff for persona-prompt tuning.

2. **Pre-wave snapshot is ADVISORY, not enforced.** `scripts/wave-sandbox.sh init` still captures `WAVE_BASE=$(git rev-parse HEAD)` so reviewers have a stable reference for their diffs. `assert-clean` still runs — if HEAD moved, that becomes a persona-tuning signal, **NOT** a rollback trigger. The orchestrator's response to HEAD-moved is: inspect, accept if the change is consistent with wave scope, fix-forward if not.

3. **Reviewer REWORK = one or more follow-up commits on the same branch.** Findings close in the order they reduce risk (BLOCKING → HIGH → MEDIUM → LOW). Each close is a separate small commit whose message cites the finding ID. Re-review runs against the final HEAD after all follow-ups land. Max 2 rework cycles; cycle 3 = ESCALATE to user, not reset.

4. **Pod integration is evolution-safe.** `scripts/pod-apply.sh` applies patches in declared order; if verification fails after apply, the fix is **another commit on top** (usually a reviewer-finding closure), not a reset. The pod's atomic guarantee is about patch application, not about undoing committed work.

**Agent-rejection handling (replaces wave-abort):**
- Rejected / errored Agent → inspect the partial state. If files are untouched, re-dispatch with sharpened prompt. If files were edited and the partial patch is usable, accept + close reviewer findings via follow-up commits. No reset.
- Non-APPROVE self-assessment → still integrate the patch, then dispatch a scoped follow-up to close the `open_concerns`.

**What's still prescribed (unchanged):**

5. **Wave ceiling.** Max 3 rows per wave when truly independent. Max 1 row when contract edges exist between personas in the wave. Smaller waves = smaller rework surface.

6. **Shift-left scope review.** Before impl dispatch, a single `qa-architect` review pass validates the wave's `## Parallelism` section and Acceptance clauses. Catches contract holes at spec-time (cheap).

7. **Contract-edge serialization.** When the wave has persona-to-persona contract edges, serialise — never dispatch in parallel. Each step commits before the next Agent dispatches.

**Verification cadence (batching discipline):**
- `scripts/local-ci.sh --fast` runs once per wave (at integration gate) and once per rework cycle (after follow-up commits land).
- `scripts/launch.sh --verify` runs once per wave (only when wave touches GUI/FDC3/dist), after all rework closes.
- Never per-row. Never per-persona.

**What this rule forbids:**
- `git reset --hard <any-prior-sha>` as a wave-mechanic response to reviewer findings.
- `git revert` of an in-wave commit unless a reviewer finding specifically requests reversion as the fix-forward (rare; typically the fix is amend-on-top).
- `wave-sandbox.sh rollback` as the default response to REWORK. The script's `rollback` subcommand is deprecated; use `wave-sandbox.sh fix-forward` (no-op stub that logs the finding for handoff) instead.
- "Throw away the Agent's work and re-dispatch fresh" as a first response. Re-dispatch only when the partial state is fundamentally unsalvageable (rare).

**What this rule requires:**
- Every reviewer BLOCKING / HIGH finding has a named close-out commit (or scope-transfer / escalation ledger entry) BEFORE the benchmark row is marked green.
- The post-commit-handoff hook records each close-out commit with its finding ID so future sessions see the fix-forward trail.
