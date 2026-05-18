<!-- MIRROR — DO NOT EDIT HERE -->
<!-- Source-of-truth: root wiki/CLAUDE.md -->
<!-- Mirror-script: scripts/wiki-mirror.sh -->
<!-- Mirrored-at: 2026-05-18T02:41:36Z -->
<!-- Mirror-source-sha: 461e0ca41c3297e13d1c628f6182fb61c0120d86 -->

> **This file is a MIRROR.** The authoritative copy lives at root
> `wiki/CLAUDE.md`. Sub-repo edits to this file are overwritten on
> the next `scripts/wiki-mirror.sh` run from the root session. Schema
> amendments are governance changes per `wiki/CLAUDE.md` §17 and
> happen at the root session.

---

# DeskModal Wiki — schema

> Persistent, evidence-gated, federated knowledge layer over the existing canonical
> sources (`.claude/rules/`, `.claude/agents/`, `.specify/memory/constitution.md`,
> `.codebase-memory/adr.md`, `specs/personas/`, CBM graph).
>
> **Pattern source**: Karpathy, *LLM Wiki* — gist `442a6bf555914893e9891c11519de94f`,
> 2026-04-04. Adapted to DeskModal's 8-repo federation, 26-persona dispatch, and
> evidence-first verification posture.
>
> **This file is the schema authority.** `scripts/wiki-lint.sh` enforces every
> contract below.

## 1. What lives here

The wiki is the **synthesis layer**. It does not replace canonical sources; it
indexes, cross-links, and contextualises them, and adds durable cross-cutting
knowledge that has no other home.

| Class of fact | Authoritative source (unchanged) | Wiki role |
|---|---|---|
| Workflow rules | `.claude/rules/*.md` | `governance/rules-charter.md` — index + intent |
| Persona definitions | `.claude/agents/*.md` | `inventory/personas.md` (auto-gen) + `personas/<name>.md` (synthesis) |
| Constitution | `.specify/memory/constitution.md` | `governance/constitution.md` — annotated mirror |
| Hooks | `.claude/hooks/*.sh` | `governance/hooks-charter.md` — event → outcome map |
| ADRs | `.codebase-memory/adr.md` (CBM) | `decisions/` (CBM-managed mirror) |
| Per-feature specs | `specs/feature-NNN/` (transient, archives on ship) | NOT mirrored — owner persona dispatches wiki updates on archive |
| Compat ladder | `specs/compat-ladder.yml` | `governance/compat-ladder.md` (auto-gen table view) |
| Code symbols | CBM graph | wiki references via `evidence_sources: [cbm:...]` |
| Visual evidence | `wiki-sources/cdp-captures/` | `visual/` references for synthesis |
| Design mockups | `wiki-sources/design-mocks/` | `design-system/` and `brand/` synthesis |

**Wiki contains:** durable cross-cutting product/codebase synthesis, governance
indexes, brand canon, naming canon, inventory registries, quality targets, risk
registers, capability boundaries, playbooks, design-system patterns.

**Wiki does NOT contain:** anything edited by automated tools at runtime
(`.session-state/`, `.prod-check/`), private user memory
(`~/.claude/.../memory/`), transient feature specs.

## 2. Federation topology

The wiki follows the 8-repo topology in `.claude/rules/parallel-sessions.md`.
Root wiki holds cross-cutting synthesis; each sub-repo holds local-detail
synthesis. Mirroring is one-way (root → sub-repos read-only); the mirror
script lands in Wave 2.5 (sub-repo `wiki/CLAUDE.md` skeletons, automated
sync). Wave 1+2 cover root-wiki only.

```
deskmodal/wiki/                        # ROOT (this file's directory) — cross-cutting
deskmodal/wiki-sources/                # ROOT — immutable raw sources
platform/wiki/                         # per-repo: Rust crates, IPC, window-manager, wasmtime
plugins/tradesurface/wiki/             # per-repo: 8 apps, chart engine, drawings, indicators
plugins/optiscript/wiki/               # per-repo: runtime, editor, syntax + stdlib
plugin-tools/wiki/                     # per-repo: dmpkg CLI, signing flows
marketplace/appmarket/wiki/            # per-repo: catalog schema, federation
marketplace/plugin-index/wiki/         # per-repo: discovery index, search
core-server-api/wiki/                  # per-repo: control-plane endpoints, auth
```

**Cross-repo URI scheme:** `wiki://<repo>/<path>` where `<repo>` ∈ `{root,
platform, tradesurface, optiscript, plugin-tools, appmarket, plugin-index,
core-server-api}`. Resolved by `wiki-mcp` (Wave 3); fallback resolution
walks the per-repo `wiki/` directories directly.

**Ownership invariant:** root `wiki/` is edited only from a session whose
`CLAUDE_PROJECT_DIR=$WORKSPACE_ROOT` (or equivalent). Sub-repo `wiki/`
is edited only from a session whose `CLAUDE_PROJECT_DIR` points at that
sub-repo. Mirrored copies in sub-repos are read-only — `sync-specs.sh`
overwrites them.

## 3. Frontmatter contract

Every wiki page has YAML frontmatter. Field order is free; field names are
fixed.

```yaml
---
title: <Human-readable page title>
entity_type: <see §3.1>
owner_persona: <one of .claude/agents/*.md filename stem>
review_personas: [<persona>, ...]              # optional
references_canonical: <path>#<anchor?>          # optional, see §4
last_canonical_sha: <40-char-git-sha>           # required iff references_canonical present
last_verified_against_sha: <40-char-git-sha>    # required for non-auto-gen pages
evidence_sources:                                # required, ≥1 entry, see §5
  - <typed reference>
  - ...
visual_assets: [<path under wiki-sources/ or wiki/visual/>]  # optional
links_in: [<wiki-page-path>, ...]                # optional, declared inbound
links_out: [<wiki-page-path | wiki://<repo>/<path>>, ...]   # optional, declared outbound
status: <draft | stable | deprecated | stale>
schema_version: 1
synthesis_only: true                              # optional, set when references_canonical
adds: [<rationale | exemplars | anti-patterns | history | cross-refs>]  # optional
auto_generated: true                              # optional, see §6
---
```

### 3.1 `entity_type` vocabulary

| Value | Use for |
|---|---|
| `entity` | Durable cross-cutting concept (FDC3 bridge, plugin lifecycle, signing chain) |
| `contract` | A specific protocol or interface contract (Tauri command shape, FDC3 channel format) |
| `playbook` | Runbook for a recurring procedure (ship a Tauri command, rotate signing key) |
| `decision` | ADR mirror or cross-cutting design decision |
| `design-token` | A specific design-system token or token group (OKLCH palette, motion canon) |
| `benchmark` | Perf baseline page with bench artefacts |
| `visual` | Page primarily about visual reference material |
| `governance` | Rules, constitution, hooks, settings synthesis |
| `inventory` | Registry page (plugins, services, SDKs, APIs, surfaces, dependencies) |
| `brand` | Brand canon (logo, palette, voice, motion) |
| `naming` | Naming convention page |
| `risk` | Threat model, dead-end registry, known-issue, postmortem |
| `capability` | Autonomy boundary (autonomous, human-required, escalation, cost) |
| `operation` | Devops, observability, release, migration |

## 4. The `references_canonical` contract (anti-duplication)

When a wiki page exists primarily to synthesise an authoritative source, it
MUST declare:

```yaml
references_canonical: .claude/rules/quality.md#6-naming
last_canonical_sha: <SHA at which this synthesis was verified>
synthesis_only: true
adds: [rationale, exemplars]
```

**Lint enforces:**

1. **Resolves** — file at `references_canonical` exists; `#anchor` (if present)
   resolves to a heading in that file.
2. **Freshness** — `last_canonical_sha` matches
   `git log -1 --format=%H -- <canonical>` of the canonical file.
3. **No restating** — synthesis-only pages may not verbatim-copy more than
   25 contiguous tokens from the canonical source. (Enforced via shingled
   token-hash comparison.)
4. **No contradiction** — read-only LLM contradiction lint flags semantic
   conflict between wiki and canonical (cron-driven, not per-commit).

The reverse direction is enforced too: when a `.claude/rules/*.md` or
`.claude/agents/*.md` or `.specify/memory/constitution.md` file changes, the
linked wiki pages must be updated in the same commit OR the commit body must
carry `[wiki:not-impacted] <reason>` (mirroring the `[adr:not-applicable]`
pattern from the deprecated ADR-discipline rule).

## 5. `evidence_sources` reference scheme

Every claim in a wiki page must trace to one of these typed references.
`scripts/wiki-lint.sh` resolves each one and fails if unresolved.

| Prefix | Form | Resolution |
|---|---|---|
| `file:` | `file:<path>:<lineN>-<lineM>` | file exists; line range non-empty |
| `cbm:` | `cbm:<project-name>/<qualified-name>` | `mcp__codebase-memory-mcp__get_code_snippet` returns content |
| `canonical:` | `canonical:<path>#<anchor?>` | shorthand for `references_canonical`; same resolution rules as §4.1 |
| `log:` | `log:<path>` (under `wiki-sources/` or `.session-state/`) | file exists |
| `bench:` | `bench:<path>` (under `wiki-sources/bench-runs/`) | file exists; criterion JSON parse OK |
| `cdp:` | `cdp:<path>` (under `wiki-sources/cdp-captures/`) | file exists; sibling `manifest.json` valid |
| `url:` | `url:https://...` | HEAD request returns 2xx (cron-driven, not per-commit, with cache) |

Stale `cbm:` references (qualified name no longer exists in the graph) flip
the page to `status: stale` and require owner-persona refresh.

## 6. Auto-generated pages (`auto_generated: true`)

Pages produced by generators (`scripts/wiki-gen-personas.sh`,
`scripts/wiki-gen-apis.sh`, `scripts/wiki-gen-tokens.sh`,
`scripts/wiki-gen-compat-ladder.sh`) carry `auto_generated: true` and a
trailing comment block:

```markdown
<!-- auto-generated — do NOT hand-edit -->
<!-- regenerate via: scripts/wiki-gen-personas.sh -->
<!-- generator-sha: <commit-sha-of-generator-script> -->
<!-- generated-at: <ISO timestamp> -->
```

Lint rejects manual edits to auto-generated pages: it re-runs the generator
and diffs against the on-disk content. Any drift fails the gate.

## 7. Owner-persona matrix

Path-based owner mapping. Single-writer per page is enforced by directory
rule. The orchestrator dispatches the owner persona for any wiki edit; pod
patterns are forbidden for wiki writes (single-writer invariant).

| Path glob | Owner persona | Default review personas |
|---|---|---|
| `wiki/governance/**` | `documentation-engineer` | `integration-architect` |
| `wiki/governance/constitution.md` | `documentation-engineer` | `integration-architect`, `security-engineer`, `qa-architect` |
| `wiki/governance/human-gates.md` | `documentation-engineer` | `security-engineer`, `qa-architect`, `integration-architect` |
| `wiki/targets/quality-attributes.md` | `documentation-engineer` | `qa-architect`, `ux-design-lead`, `security-engineer` |
| `wiki/targets/perf-budgets.md` | `qa-architect` (review) → `documentation-engineer` writes | `rust-systems-architect`, `frontend-architect` |
| `wiki/targets/compliance.md` | `security-engineer` (BLOCK auth) | `integration-architect`, `fdc3-protocol-engineer` |
| `wiki/inventory/personas.md` | `documentation-engineer` (auto-gen) | — |
| `wiki/inventory/plugins.md` | `marketplace-architect` | `verification-gateway-engineer` |
| `wiki/inventory/services.md` | `data-pipeline-engineer` | `fdc3-protocol-engineer` |
| `wiki/inventory/sdks.md` | `plugin-sdk-engineer` | `documentation-engineer` |
| `wiki/inventory/apis.md` | `integration-architect` | `rust-systems-architect`, `fdc3-protocol-engineer` |
| `wiki/inventory/tokens.md` | `style-bot` (auto-gen) | `ux-design-lead` |
| `wiki/inventory/dependencies.md` | `build-deploy-engineer` | `security-engineer` |
| `wiki/inventory/mcps.md` | `documentation-engineer` | `integration-architect` |
| `wiki/brand/**` | `deskmodal-design-agent` | `ux-design-lead` |
| `wiki/naming/**` | `documentation-engineer` | persona named in scope |
| `wiki/design-system/**` | `deskmodal-design-agent` | `ux-design-lead`, `trading-ux-architect` |
| `wiki/personas/<name>.md` | `documentation-engineer` | the named persona |
| `wiki/playbooks/**` | `documentation-engineer` | persona named in playbook |
| `wiki/risks/**` | `qa-architect` | `security-engineer`, `integration-architect` |
| `wiki/capabilities/**` | `documentation-engineer` | `qa-architect`, `integration-architect` |
| `wiki/operations/**` | `build-deploy-engineer` | `qa-architect`, `security-engineer` |
| `wiki/decisions/**` | CBM `manage_adr` (machine) | `documentation-engineer` |
| `wiki/visual/**` | `chart-qa-verifier` (chart-related) / `qa-architect` (other) | `ux-design-lead` |
| `wiki/entities/fdc3-bridge.md` | `fdc3-protocol-engineer` | `integration-architect`, `security-engineer` |
| `wiki/entities/plugin-lifecycle.md` | `integration-architect` | `rust-systems-architect`, `security-engineer` |
| `wiki/entities/signing-chain.md` | `security-engineer` (BLOCK auth) | `build-deploy-engineer`, `integration-architect` |
| `wiki/entities/dist-topology.md` | `build-deploy-engineer` | `rust-systems-architect`, `integration-architect` |
| `wiki/entities/mcp-topology.md` | `integration-architect` | `documentation-engineer` |
| `wiki/entities/deskmodal-contract.md` | `documentation-engineer` | `integration-architect`, `fdc3-protocol-engineer`, `security-engineer` |
| `wiki/entities/<other>.md` | inferred from CBM domain — fallback `documentation-engineer` | declared per page |
| `<sub-repo>/wiki/**` | per sub-repo persona (see sub-repo's `wiki/CLAUDE.md`) | declared per page |

The `trading-sme` persona is **conditional**, mirroring `core.md §7`: it
reviews wiki pages whose subject matter touches order flow, PnL, position,
or financial-capability plugins. Non-financial pages do not dispatch
`trading-sme`.

## 8. The two pivot files

### `wiki/index.md`

Category-overview catalog. **Not** the primary retrieval surface — that role
belongs to `wiki-mcp` from Wave 3 onward. The index serves humans browsing
the repo and serves as the entry-point reading order. Lint requires:

- Every directory under `wiki/` has at least one inbound link from
  `index.md`.
- Auto-generated section per category (lint refreshes from frontmatter).

### `wiki/log.md`

Append-only chronological journal. One line per ingest / lint / generation /
schema-amendment event. Format:

```
## [<ISO timestamp>] <event-type> | <subject>

<one-paragraph summary>

- Affected pages: <wiki paths>
- Triggered by: <commit SHA | PR # | cron | manual>
- Verification: <command + exit code | "n/a">
```

Event types: `ingest`, `lint`, `gen`, `schema-amend`, `cross-repo-sync`,
`postmortem`, `rollback`.

`grep "^## \[" wiki/log.md | tail -10` yields the last 10 events. Lint
rejects out-of-order entries.

## 9. Lint contract

`scripts/wiki-lint.sh` is wired into `scripts/local-ci.sh --fast`. It enforces:

| Check | Fails on | Notes |
|---|---|---|
| **schema-validate** | Missing required frontmatter field; unknown field; invalid enum value | Per §3 |
| **canonical-resolve** | `references_canonical` path/anchor doesn't exist | Per §4 |
| **canonical-fresh** | `last_canonical_sha` ≠ `git log -1 --format=%H -- <canonical>` | Per §4 |
| **canonical-no-restate** | Synthesis-only page restates >25 contiguous canonical tokens | Per §4 |
| **evidence-resolve** | Any `evidence_sources` entry fails its resolution rule | Per §5 |
| **owner-valid** | `owner_persona` not in `.claude/agents/<name>.md` | Per §7 |
| **owner-path-match** | Page path's owner-glob owner ≠ frontmatter `owner_persona` | Per §7 |
| **link-resolve** | `links_out` target doesn't exist | — |
| **link-bidirectional** | `links_out` target page lacks reciprocal `links_in` | Cron-driven (not per-commit) |
| **autogen-fresh** | `auto_generated: true` page differs from generator output | Per §6 |
| **stale-status** | Page with `last_verified_against_sha` ≥ N commits behind HEAD has `status: stable` (must be `stale`) | N defaults to 100; configurable |
| **schema-version** | `schema_version` ≠ current schema version (this file's `## 11`) | — |
| **log-monotonic** | `wiki/log.md` entries non-monotonic in timestamp | — |
| **coverage** | `wiki-coverage.sh` flag (Wave 2) | Per §10 |

Comprehensive lint (`wiki-lint.sh --comprehensive`, cron-driven):

- **contradiction** — read-only LLM dispatch flags semantic conflict
  between wiki page and its canonical source.
- **orphan** — pages with zero `links_in` and zero generator-claim.
- **url-resolve** — every `url:` reference returns 2xx (cached 24h).

## 10. Coverage contract (Wave 2)

`scripts/wiki-coverage.sh` enforces that the wiki keeps pace with reality.
Wired into `local-ci.sh --fast` Wave 2 onward.

| Coverage check | Source of truth | Wiki target |
|---|---|---|
| Persona dossier | `.claude/agents/*.md` filenames | `wiki/inventory/personas.md` rows |
| Rule index | `.claude/rules/*.md` filenames | `wiki/governance/rules-charter.md` index entries |
| Plugin registry | `dist/plugins/*/plugin.toml` | `wiki/inventory/plugins.md` rows |
| Tauri command | `#[tauri::command]` macros via CBM | `wiki/inventory/apis.md` rows |
| FDC3 intent | `deskmodal.*` intent declarations via CBM | `wiki/inventory/apis.md` (intents section) |
| Design token | `--ts-*` / `--deskmodal-*` CSS custom properties | `wiki/inventory/tokens.md` rows |
| Hook | `.claude/hooks/*.sh` filenames | `wiki/governance/hooks-charter.md` rows |
| MCP server | `.mcp.json` entries | `wiki/inventory/mcps.md` rows |

Reverse coverage: every wiki entry must point at a real artefact
(no orphan inventory rows).

## 11. Schema versioning

Current `schema_version`: **1**.

Schema amendments are governance changes:

- Edit this file (`wiki/CLAUDE.md`).
- Bump `schema_version` if any field's semantics change in a non-additive
  way.
- Add a `## 11.1 Migration history` row.
- Author a `wiki/log.md` entry of type `schema-amend`.
- Required reviewers: `documentation-engineer` (primary),
  `integration-architect` (federation impact), `qa-architect` (lint
  impact).
- All existing pages retain their declared `schema_version`; lint runs
  per-page against the declared version. Migrations land as a
  `wiki-migrate.sh` invocation that rewrites frontmatter in place.

## 12. Discovery order amendment

Extends `.claude/rules/core.md §3` for sessions working at any scope:

1. `mcp__codebase-memory-mcp__*` — code graph (unchanged).
2. `mcp__rust-analyzer__*` — Rust diagnostics (unchanged).
3. **`wiki-mcp__*` — wiki retrieval (new, Wave 3+).** Slots in here because
   durable synthesis beats raw screenshots for governance / inventory /
   contract questions.
4. `mcp__playwright__browser_*` — visual verification (unchanged).
5. `mcp__github__*` — PR/issue queries (unchanged).
6. Grep / Read — fallback only.

For non-code question shapes (governance, brand, inventory, naming, target,
risk), wiki-mcp is the **first** stop. For code-symbol shapes, CBM remains
first. Choose by question shape, not file extension.

## 13. Reading-order conventions

Three onboarding paths (operationalised in `wiki/playbooks/onboard-*.md`,
Wave 4):

- **New human developer**: `wiki/index.md` → `governance/rules-charter.md` →
  `governance/human-gates.md` → `targets/quality-attributes.md` →
  `inventory/personas.md` → `entities/deskmodal-contract.md` → relevant
  sub-repo `wiki/CLAUDE.md`.
- **New persona dispatch (any session)**: `wiki/CLAUDE.md` (this file) →
  `inventory/personas.md` row for the dispatched persona →
  `governance/rules-charter.md` → relevant `entities/` for the task domain.
- **Cross-stack integration session**: `wiki/CLAUDE.md` →
  `entities/deskmodal-contract.md` → `entities/fdc3-bridge.md` →
  `entities/plugin-lifecycle.md` → all affected sub-repo `wiki/CLAUDE.md`.

## 14. Session-targeted access patterns

Mirrors `.claude/rules/parallel-sessions.md` capacity table.

| Session shape | `CLAUDE_PROJECT_DIR` | Wiki read-set | Wiki write-set |
|---|---|---|---|
| App (e.g. chart) | `plugins/tradesurface` | local + root `design-system/`, `entities/chart-engine.md` (Wave 2), `brand/`, `naming/` | local only |
| Service | sub-repo of plugin | local + root `entities/fdc3-bridge.md`, `playbooks/service-lifecycle.md` (Wave 4) | local only |
| Plugin loader | `platform` | `platform/wiki/`, root `entities/plugin-lifecycle.md`, `entities/signing-chain.md` | `platform/wiki/` |
| SDK | sub-repo containing the SDK | local + root `entities/<contract>.md` | local only |
| DeskModal-level | root | full root wiki | root wiki only |
| Cross-stack | root (orchestrator-led) | full federation read | per-repo writes via dispatched owners |

## 15. Continuous evolution mechanisms (Wave 3+)

- `post-commit-wiki-ingest.sh` — opt-in via commit trailer
  `[wiki:ingest <page>]`; auto for `feat:`/`fix:` commits touching domains
  with declared wiki coverage.
- `post-merge-wiki-ingest.sh` — PR description ingested as `log.md` entry;
  PR labels `wiki:entity/<name>` trigger targeted ingest.
- `feature-archive-wiki-sync.sh` — `specs/feature-NNN/` archive blocks until
  affected wiki pages updated.
- Weekly `/schedule` cron — `wiki-lint.sh --comprehensive --propose-fixes`,
  PR opened by `documentation-engineer`.
- Monthly cron — `wiki-divergence.sh` cross-references root vs sub-repo
  wikis.
- Quarterly human review — `governance/human-gates.md` ratification.

## 16. Escape hatch

`DESKMODAL_LAX=1` bypasses wiki-lint at commit time, mirroring other rule
escape hatches. Every bypass appends one line to
`.prod-check/wiki-lax-bypass.log` with the failed-check name and reason.
Use only when the user has authorised in-session or when diagnosing a lint
false-positive.

## 17. Amendments to this schema

Required reviewers: `documentation-engineer` (primary), `integration-architect`
(federation impact), `qa-architect` (lint impact). Schema amendments follow
the Constitution's Governance section (`.specify/memory/constitution.md`).
