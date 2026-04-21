## PURPOSE
The appmarket is a federated plugin-catalog aggregator for DeskModal.
It fetches plugin manifests from multiple sources (npm-published,
AppD vendor repos, local), validates checksums and Ed25519
signatures, deduplicates across sources, optionally mirrors private
assets, signs the merged catalog, and publishes one immutable
`index.json` served globally via Fastly CDN. Every DeskModal session
fetches this single file on marketplace open.

**Design stance**: open but gated. Independent publishers apply via
signup issue + domain verification before earning a `sources.json`
entry. Once approved they release via their own GitHub repos;
the aggregator mirrors their assets and repackages them into a
unified catalog. Trust flows: per-publisher Ed25519 key → per-release
checksums → per-platform tarballs. The aggregator composes
verification metadata; it never *verifies* — clients do that.

## STACK
- Python 3.12, `scripts/aggregate.py` (914 lines) — the entire
  aggregation pipeline in one file.
- Entry: `aggregate(sources_path, out_path, token, mirror=True,
  dry_run=False) → bool`.
- External APIs: GitHub Releases API (read upstream + write
  appmarket), `cryptography` library (Ed25519 signing).
- CI/CD: GitHub Actions (`aggregate.yml` for catalog builds,
  `validate.yml` for sources.json schema).
- Secrets: `DESKMODAL_REPO_TOKEN` (org PAT, read all sources + write
  appmarket), `DESKMODAL_SIGNING_KEY` (org Ed25519 private key hex,
  signs `index.json`).

## ARCHITECTURE

**AD-1 — Multi-source aggregation with per-publisher keys.**
`sources.json` declares `{owner, repo, mode, plugins[],
asset_name_template, publisher_key_id}`; `publisher_keys` map binds
key IDs to hex public keys. `aggregate.py:12-24, 406-501`
implements per-source fetch + optional mirror. Catalog entries embed
the publisher's `key_id`; clients verify signatures against the
embedded key rather than trusting the aggregator.

**AD-2 — Template-driven asset resolution.**
`build_platforms_map(release, template, subs, checksums)` resolves
`{version},{slug},{platform}` into asset names; searches release
assets; matches against `PLATFORMS = ["win32-x64","darwin-arm64",
"darwin-x64","linux-x64","wasm"]` in priority order; drops the entry
if no installable platform found. Decouples source-repo naming from
catalog schema.

**AD-3 — Idempotent mirroring for private sources.**
`mirror_source_release(source_owner, source_repo, source_release,
token, dry_run)` at `aggregate.py:406-501`: creates appmarket
release tagged `{repo}-v{version}`, uploads missing assets, no-ops
if target release exists with all assets. Stable public URLs for
private upstreams; double storage cost accepted.

**AD-4 — Content-change detection via normalised comparison.**
`aggregate.py:813-821` zeros `generated_at` + `source_commit` before
byte-comparing old vs new catalog. Same source state across 6-hour
scheduled cron = no commit, even if timestamps differ.

**AD-5 — Overwrite-safety guard.**
`aggregate.py:859-870`: refuses to write a 0-entry catalog if the
existing catalog has >0 entries. Catches token/network failures that
would otherwise nuke the public catalog for all clients on next CDN
refresh.

**AD-6 — Two-tier signature trust.**
Publisher signs their own `checksums.txt` with their Ed25519 private
key (embedded `SIGNATURE` asset). Appmarket signs `index.json` with
`DESKMODAL_SIGNING_KEY` (detached `index.json.sig` at
`aggregate.yml:84-101`). Clients verify catalog sig first (appmarket
pubkey), then each plugin's per-publisher sig. Aggregator does no
crypto verification — only composes pointers.

**AD-7 — Monorepo support via multi-plugin entries.**
`build_entries_multi` emits multiple catalog entries per release
(tradesurface ships 10 plugins in one release). Each gets its own
checksums template + manifest URL so a client can install one plugin
without downloading all.

## PATTERNS
- Idempotency everywhere: fetch-check-upload-missing for mirror;
  normalised-byte-compare for catalog; stable sort by `id` for
  deterministic output.
- Dataclasses for structured external data (`Release`,
  `ReleaseAsset`) — no dicts with string-key access across the
  aggregator.
- Hand-rolled `parse_toml_minimal` (aggregate.py:175-234) — only
  extracts `[compat]` + `description`. Zero TOML dependency.
- Publisher signup gate (PUBLISHING.md:34-66): GitHub issue →
  domain verification → sources.json entry (CODEOWNERS-gated) →
  fine-grained PAT provisioned.
- Per-release dispatch flow: publisher pushes tag → their
  `release.yml` builds + signs + creates GH Release + dispatches →
  appmarket `aggregate.yml` fires within seconds → signs + pushes.

## TRADEOFFS
- Aggregator-composes, client-verifies — stateless aggregator,
  scales to hundreds of publishers, compromise-resistant. Costs:
  every client re-verifies.
- Mirror=true for private sources — stable URLs across repo
  renames/archivals; doubles storage.
- Dependency-light Python (only `cryptography`) — hand-rolled TOML
  parser, no retry libraries. Supply-chain surface minimised for a
  tool that runs in every release pipeline.
- Immutable catalog — every `index.json` is signed and frozen
  (no in-place update). Clients can pin-verify old catalogs.
- Single `index.json` over federated queries — one file fetch per
  DeskModal session; simple dep resolution; no availability
  cascade across multiple registries.

## PHILOSOPHY
- Openness with curation — signup review before first entry, then
  open publishing cadence (no PR review per release) guarded by
  per-publisher Ed25519 signatures.
- Zero-downtime publishing — ~30s dispatch-to-CDN latency; push a
  tag, it's live.
- Stateless aggregator — decides nothing about signature validity;
  scales horizontally.
- Federated sources, centralised distribution — plugins live in
  their own repos, catalog is one signed file.
- Immutable catalog releases — every `index.json` is frozen; clients
  can pin any previous catalog state.
