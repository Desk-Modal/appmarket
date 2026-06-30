# Agent dispatch

## Canonical

Personas live in `.claude/agents/<name>.md` with YAML frontmatter (`name`, `description`, `tools`, `model`, optional `color`, `permissionMode`, `memory`). Body is ≤ 15 lines: domain scope + invariants + exit criteria. Central rules come from `.claude/rules/core.md`.

Dispatch: `Agent(subagent_type=<name>, model=<pinned>)`. Claude's native router matches task wording against each agent's `description`.

## Standing impl-agent contract (design-first — fed to EVERY dispatch, up front)

**Every impl dispatch (Agent or Workflow `agent()`) carries this contract UP FRONT as the design-time quality bar — NEVER re-asked per task, NEVER a reactive after-the-fact fix.** Operationalises `core.md §1` · `quality.md §5`/`§18.1`/`§18.8` · `architecture.md §16`/`§24`/`§28`. Reusable copy (lane template, also the persona exit-criteria reference): `plugins/optiscript/specs/impl-agent-contract.md`. Embed it verbatim in every `Workflow` impl prompt; cite it in persona exit-criteria.

- **DESIGN-FIRST decomposition (§24 — proactive, never reactive-split):** before writing, decompose into cohesive concerns, assign each to its own sibling module (`mod.rs` + `<concern>.rs`) targeted ≤300 LOC carrying COMPLETE logic; implement INTO that layout from line one. Every file is BORN ≤300 + complete — never monolith-then-split, never a latent "decomp later" task (a pre-existing-over file you touch → split it in the SAME diff). `over_ceiling_files` MUST be empty; critique REWORKs on any breach.
- **Production-grade (§5):** zero stub/TODO/FIXME/placeholder/demo; complete error handling + every edge case; no `unwrap`/`expect` on fallible runtime paths; no versioned interfaces (evolve in place).
- **Non-blocking (§16):** loops in their own `tokio::spawn`; bounded channels (≥4096, drop-on-overflow, never `unbounded_channel`); no `Mutex`/`RwLock` across `.await` on hot paths (ArcSwap/DashMap/atomics/actors); no sync HTTP/WS in service code; NO fallbacks (hard-fail `rc≠0` on unmet precondition).
- **Mission-critical/deterministic (§28) + SOTA (§18.8 + `scope.html`):** correct under concurrency, no lost updates; best-in-field approach that BEATS the named competitor on the axis — not a minimal pass.
- **CRITIQUE COLLABORATES UP FRONT — not a latent gate; minimise gates (user 2026-06-20: "why are they not collaborating up front… minimise unnecessary gates"):** the reviewer lenses — the exact things a critic REWORKs on (§24 over-ceiling, dead-helper vs DEPLOYED-seam, compat-shim/versioned-alias, dishonest gate rc, trivially-true tests, capability-cut) — are a **design INPUT the impl agent self-satisfies BEFORE returning**, never a downstream stage that finds the problem after the fact (the same anti-pattern as a post-hoc verify). A separate adversarial-critique agent is reserved for **load-bearing** changes — subtle correctness / security / deployed-seam / financial-math — where a genuine second set of eyes catches what self-review can't (closure-capture semantics, signing/ACL, intent-registration-on-the-deployed-service, PnL). For **mechanical** changes (rename, decomp, test/fixture authoring, config/manifest, docs) the self-run scoped gate + the BATCHED mechanical audit gates (loc-ceiling, clippy `-D`, tests, no-stub grep) already cover it — a per-lane opus critique there is ceremony. **Every gate must be LOAD-BEARING:** if a cheap deterministic script already checks it, don't spend an agent; if the contract already mandated it, verify it ONCE at the batch boundary, not per-lane. Memory: `feedback_critique_up_front_minimise_gates`.

**Verify-discipline (CORRECT-UP-FRONT, then anti-waste — NEVER block, NEVER repeat a long run; §4.2/§4.3/§18.7.1):**
- **CORRECT UP FRONT — every impl agent runs the SCOPED REAL GATE before returning, fixing to green IN ITS WORKTREE:** `cargo fmt -p <crates>` + `cargo clippy -p <crates> --all-targets -- -D warnings` + `cargo test -p <crates>`. **`cargo check` is NOT the gate, and a no-cargo draft is FALSE economy** — both let fmt drift, clippy `-D` unused-imports (incl. test-only re-exports), and test breaks escape to the integration Tier-C as expensive post-event fix-forwards. Scoped to the agent's crates on the warm cache this is ~1 min. The agent returns its scoped-gate rc; the detached workspace-Tier-C is then a cross-crate CONFIRMATION, not a bug-finder. (New crate / wide ripple: run the scoped gate iteratively to chase compile+lint clean.)
- **NEVER run the workspace battery on the LIVE tree.** Always a detached worktree (`git worktree add --detach <tmp> <sha>` + `Bash run_in_background`); the live tree stays free so impl + next-dispatch pipeline (shares the warm cache, §29; needs `--offline`+copied lock only when the repo gitignores `Cargo.lock`).
- **Scoped fix-forwards:** `cargo -p <changed-crate> --all-targets -- -D warnings` (seconds) for small fixes — NOT the full battery. The full `clippy --workspace + test --workspace` battery runs ONCE per impact boundary.
- **Batch across units:** let N completed units land, then ONE Tier-C covers all N — never one verify per unit/fix.
- `cargo check` is NOT the gate (it misses clippy `-D warnings` unused-imports + test-only re-exports → keep those `#[cfg(test)]`-gated). Memory: `feedback_section24_split_in_wave_agent_contract`.

## Model tiering

**Policy (2026-05-14; reaffirmed 2026-05-16; bumped 4.7→4.8 on 2026-05-31 — Claude Code CLI is now Opus 4.8, 1M ctx): every persona runs on `claude-opus-4-8`.** Quality dominates cost for the DeskModal-beats-TradingView mandate; the 1M ctx lets one agent own cross-stack work (Rust + TS + CSS) end-to-end so contract-edge violations become impossible. The multi-tier rationale + the throughput-estimate prose live in `wiki/governance/rules-charter.md`.

**Effort tuning (F157 Layer 3; ULTRACODE-FOR-ALL policy 2026-06-10, user directive "update to ultracode for all"):** the SESSION runs ultracode — `.claude/settings.json` sets `"effortLevel": "xhigh"` + `"ultracode": true` (xhigh + standing dynamic-workflow orchestration; the harness `ultracode` key is the durable form — `effortLevel` itself only accepts low|medium|high|xhigh). EVERY persona declares `effort: xhigh` in frontmatter (the subagent ceiling — the medium/high reviewer+build tiers are RETIRED; workflow orchestration stays main-loop per parallelism.md §4.1, so xhigh is the max meaningful persona value). Orchestrator may pass `--effort` per dispatch to override frontmatter (rare; quality dominates cost).

**Skills preloaded (F157 Layer 3):** every persona declares `skills:` in frontmatter. lodestar knowledge is via the `mcp__lodestar__knowledge_*` MCP tools (not a preloaded skill). Specialised additions: Rust personas `+ deskmodal-verify-tier-a`; UI personas `+ frontend-design`; Docs personas `+ deskmodal-spec-amend`; Build personas `+ deskmodal-verify-tier-b + deskmodal-verify-tier-c`. (The former mesh-claim / mesh-findings / handoff-write skills are RETIRED — replaced by native per-repo worktree isolation + native auto-memory; see architecture.md §33.)

**disallowedTools (F157 Layer 3):** review-only personas declare `disallowedTools: [Write, Edit, NotebookEdit]` as belt-and-braces beyond their `tools` allowlist.

**Per-task model tiering (user 2026-06-10 + 2026-06-20: "using the optimal claude model for the tasks in our dynamic workflow" + "we don't worry about the cost, we want the RIGHT model for the job"):** persona frontmatter pins (`claude-opus-4-8`) are the DEFAULT; every `Workflow agent()` / `Agent()` dispatch picks the **RIGHT model for the task class — best FIT, NOT cheapest. Cost is NOT a constraint (ultracode); under-powering a task to save spend is the error.** The table below is the *fitness floor* (the lightest model that is genuinely the right tool for that class), not a budget cap — task-fit governs, and model-tiering is also what lets many lanes run concurrently (lighter classes don't hit the opus-concurrency limit).

| Task class | Model |
|---|---|
| Mechanical sweeps — lock/pin bumps, renames, file moves, log/gitignore hygiene | `haiku` |
| Delta re-reviews (owner-scoped findings), scoped Tier-A verify runs, doc/tracker/ledger updates | `sonnet` |
| Cross-stack impl, type-system/runtime features, architecture, adversarial full-lane review, deployed-seam changes | `opus` / `fable` (default) |

When unsure, go MORE capable (up a tier) — the right model for the job, never the cheapest; cost is not the constraint, an under-powered output + rework cycle is.

## Dispatch patterns

Claude Code's native orchestration is via BOTH the `Agent` tool (single-shot / pod / speculative / warm-agent) AND the dynamic `Workflow` tool (graph-driven background orchestration — `parallelism.md §4.1`). This section is workflow POLICY for when to use each.

**Default is single-agent per wave.** Opus 4.8 1M-ctx owns cross-stack work end-to-end; contract-edge violations impossible; token cost ~50% vs multi-agent.

| Pattern | When | How |
|---|---|---|
| **Single-agent** (default) | Any wave — one agent owns Rust + TS + CSS end-to-end | One `Agent` call; agent edits in-place; returns unified diff via JSON |
| **Workflow** (graph/pipeline; supersedes Sequenced single-agent) | Dependency-ordered multi-step graph (research→draft→cross-check; fan-out-N→synthesise; impl-draft→adversarial-refute) that would otherwise be hand-sequenced `Agent` calls; preferred when the main context is saturated | Native dynamic `Workflow` tool — runtime JS holds orchestration + intermediate results OUT of main context; children run in fresh background contexts; only the final answer returns. ONE phase per invocation; ≤3 concurrent; disjoint dirs; main loop writes canonical files + commits. `parallelism.md §4.1` |
| **Pod (≤7)** | Proven pairwise-disjoint write-sets (audited via `scripts/audit-wave-write-sets.sh`) AND zero contract edges between members | Parallel `Agent` batch up to 7 concurrent (empirical cap 3); main loop integrates via `git apply` + commit on top per worktree (core.md §4) |
| **Speculative N+1** (default ON) | While wave N's reviewers run, dispatch wave N+1 impl against current HEAD | Parallel `Agent` call alongside the review batch; rebase or discard per wave N verdict. Opt-out: `DESKMODAL_SPECULATIVE=0` |
| **Warm-agent SendMessage** | Wave N+1 is a continuation of wave N with same persona + loaded context | `SendMessage(to: <agent-id>)` instead of fresh `Agent()` — saves ~30–50K cold-start re-read tokens. Only for true continuations |
| **Angle-swarm** (review only) | One reviewer persona, multiple lenses | Parallel dispatch of same persona with angle-specialised prompts |
| **Adversarial review** (mandatory every wave) | All declared reviewers for the wave | ONE parallel `Agent` batch per core.md §7 |

Reviewers always parallel (read-only, no race risk). Impl single-agent by default; promote to pod when write-sets audit clean; layer speculative N+1 on top when pipelining pays. Each prompt ≤ 15 concrete objectives; past that, decompose the wave not the agent.

**Audit-by-path, not by inline quote (core.md §4).** When dispatching N parallel agents that share an audit/spec/finding reference, pass the **file path** and instruct the agent to read it once. Inline-quoting burns ~30–80K tokens per dispatch.

## Return contract (every impl sub-agent)

**Impl Agents NEVER `git commit` or `git push`.** They edit files in-place and return the unified diff via JSON.

```json
{
  "patch": "<output of: git diff HEAD -- <declared write-set>>",
  "write_set_declared": ["<path>", ...],
  "write_set_actual": ["<path>", ...],
  "verification_command": "scripts/local-ci.sh --fast",
  "verification_exit_code": 0,
  "contract_produces": ["<symbol>", ...],
  "contract_consumes": ["<symbol>", ...],
  "self_assessment": "APPROVE | CONCERNS | REWORK | BLOCK",
  "open_concerns": ["..."]
}
```

**`patch` field** is required; MUST contain a valid unified diff. If an agent returns `commit_sha` (old shape), orchestrator reconciles by folding the agent's commit into a wave-cohort commit on top of current HEAD and logs the persona-prompt violation to the handoff. **Never reset.**

**Orchestrator handles (does NOT reject) returns where:**
- `patch` is empty or malformed → dispatch a follow-up Agent with the exact malformation cited; never reset.
- `write_set_actual ⊄ write_set_declared` → review the out-of-set files; accept if consistent, otherwise carve into a separate scoped follow-up commit.
- `verification_exit_code != 0` → diagnose inline; the fix is a forward commit, not a reset.
- `self_assessment == APPROVE` with non-empty `open_concerns` → integrate the patch; dispatch a scoped follow-up to close `open_concerns` before the benchmark row marks green.
- HEAD moved during agent's run → inspect the commit; accept + continue if consistent, else add a reconciling commit. Never `git reset --hard`.

**Integration flow (evolve-and-fix-forward per core.md §15):**
1. Main loop records `git rev-parse HEAD` as an advisory diff anchor (NOT a rollback anchor).
2. Dispatch Agent(s) → collect patches.
3. Assert working tree clean; if dirty, inspect + reconcile via follow-up commits (never reset).
4. Integrate via `git apply` (single-agent) or sequential per-worktree apply (pod); native worktree isolation keeps parallel write-sets separate.
5. `scripts/local-ci.sh --fast` → on failure, dispatch a scoped follow-up or close inline; commit the fix. Never reset.
6. Parallel adversarial review → findings close via follow-up commits in severity order.
7. `scripts/launch.sh --verify` (GUI/FDC3/dist-touching waves only) after all reviewer findings close.
8. Benchmark row marks green in a final outer-workspace commit; push both repos.

**Rollback is banned** as a wave-mechanic. If a wave's direction is wrong at the strategic level (rare), ESCALATE to the user; do not `git reset` unilaterally.

## Adversarial review contract

Reviewers return:

```json
{
  "verdict": "APPROVE | APPROVE_WITH_COMMENTS | REWORK | BLOCK",
  "angle": "<the review lens>",
  "findings": [
    { "severity": "BLOCKING|HIGH|MEDIUM|LOW",
      "file": "<path>", "line_range": "NN-MM",
      "summary": "<one line>",
      "disposition_required": "CLOSED|SCOPE_TRANSFERRED|ESCALATED" }
  ],
  "grep_calls_on_code": 0
}
```

`grep_calls_on_code` MUST be 0 — reviewers use lodestar on code files. Non-zero rejects the return.

## Review-only personas

`qa-architect`, `security-engineer`, `trading-sme`, `ux-design-lead`, `integration-architect`, `chart-qa-verifier`, `marketplace-qa` have **no** `Write` / `Edit` / `NotebookEdit` in their tools list. They emit findings; impl personas apply fixes.

## No-deferrals (from core.md §8)

Every finding exits as CLOSED, SCOPE-TRANSFERRED, or ESCALATED. Main loop rejects pod returns with findings not dispositioned.

## Small-agent principle

Prefer two agents with 8 objectives each over one agent with 16. Focus scales; monolithic prompts lose focus ~20 objectives in.

## Escape hatches

None for sequential reviewer dispatch — if a reviewer depends on another reviewer's output, decompose the review scope. `DESKMODAL_LAX=1` bypasses the integration gate in emergencies; audit-logged.
