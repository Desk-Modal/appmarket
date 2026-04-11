# Desk-Modal AppMarket

The public catalog of every app, service, and script published for
[DeskModal](https://github.com/Desk-Modal/deskmodal) — the Rust/Tauri
FDC3 2.2 desktop agent.

**This is an open but gated ecosystem.** Independent developers,
financial data vendors, quant firms, and enterprise IT groups can
all apply to become publishers on equal footing with the Desk-Modal
first-party teams. But publishing is not self-serve: every publisher
goes through a signup + review step before their releases can land
in the catalog. The Desk-Modal-owned entries currently seeded in
`sources.json` (`paper-trading`, `price-feed-service`, `tradesurface`)
are initial first-party entries that happen to ship the core
first-party services; once approved, every third-party publisher
gets exactly the same treatment from the aggregator. See
[**PUBLISHING.md**](PUBLISHING.md) for the end-to-end publisher
onboarding contract.

## What this repo is

A public, read-only, CDN-distributed source of truth. Every DeskModal
session on earth fetches **one** file from this repo on marketplace
open and has everything it needs to:

- enumerate installable apps, services, and scripts
- pick the right platform tarball for the host OS
- verify publisher signatures
- resolve dependencies between plugins
- render icons, descriptions, categories, and version history
- show "update available" prompts
- install a plugin in a single tarball download with no GitHub API calls

## The single lookup endpoint

```
https://raw.githubusercontent.com/Desk-Modal/appmarket/main/index.json
```

This URL is served by the Fastly-fronted GitHub raw CDN — free,
globally distributed, aggressively cached, unlimited reads, no
authentication. There is no API layer between the client and this
file; there are no rate limits to worry about at scale.

Every version of the file is signed with the DeskModal publisher
Ed25519 key. The detached signature is served alongside as
`index.json.sig` so the runtime can verify the catalog before
trusting anything inside it.

Full schema and client consumption example: [`schema/v2.md`](schema/v2.md).

## Layout

```
.
├── sources.json          # declarative list of source repos the aggregator walks
├── index.json            # generated catalog (do not hand-edit)
├── index.json.sig        # detached Ed25519 signature of index.json
├── schema/
│   └── v2.md             # the canonical schema spec
├── scripts/
│   └── aggregate.py      # the aggregator — reads sources.json, emits index.json
├── icons/                # per-entry SVG icons served via raw CDN
└── .github/
    └── workflows/
        ├── aggregate.yml # rebuilds index.json on schedule + dispatch
        └── validate.yml  # PR gate: sources.json schema + dry-run aggregator
```

## How index.json gets populated

1. A plugin repo (e.g. `Desk-Modal/paper-trading`) cuts a git tag
   `v1.2.3` and its own release workflow builds per-platform tarballs,
   signs the checksums with `DESKMODAL_SIGNING_KEY`, and creates a
   GitHub Release with all assets attached.
2. That workflow's final step fires a `repository_dispatch` event at
   this repo with type `release-published`.
3. `.github/workflows/aggregate.yml` picks up the dispatch, runs
   `scripts/aggregate.py` against `sources.json`, downloads
   `plugin.toml` + `checksums.txt` for the fresh release, assembles a
   fully-resolved catalog entry with per-platform URLs and SHA-256
   hashes, signs the whole catalog with `DESKMODAL_SIGNING_KEY`, and
   commits the new `index.json` + `index.json.sig` back to main.
4. GitHub's raw CDN picks up the new file within ~60 s. The next
   DeskModal marketplace refresh on any client sees the update.

Idempotent — reruns against unchanged state produce no commit.
A scheduled run every 6 h catches missed dispatches as a safety net.

## How to publish a plugin (quick reference)

Full contract in [**PUBLISHING.md**](PUBLISHING.md). The short version:

1. **Apply** — file a [Publisher signup issue](../../issues/new?template=publisher-signup.yml) with your Ed25519 public key, release repo list, and plugin list. Wait for Desk-Modal review. Approval gives you a namespaced publisher id, a sources.json entry committed on your behalf, and a scoped `APPMARKET_DISPATCH_TOKEN` PAT.
2. **Build** — your release workflow emits per-platform tarballs + `plugin.toml` + `checksums.txt` + `SIGNATURE` on every tag push. Sign `checksums.txt` with your own Ed25519 key (the one whose public half is in your sources.json entry). **Do not reuse the `DESKMODAL_SIGNING_KEY` secret** — that's the first-party key, only for Desk-Modal's own releases.
3. **Notify** — add this one line to the very end of your release workflow:
   ```yaml
   - uses: Desk-Modal/appmarket/.github/actions/notify-appmarket@main
     with:
       token: ${{ secrets.APPMARKET_DISPATCH_TOKEN }}
   ```
4. **Publish** — `git push --tags`. Within ~30 seconds your entry shows up in every DeskModal session's next marketplace refresh.

## Triggering a catalog rebuild from a source repo

Three consumption patterns, ranked by how much they do for you.

### A. Composite action (one line)

Add this step at the very end of your release workflow, after the
GitHub Release has been published:

```yaml
- uses: Desk-Modal/appmarket/.github/actions/notify-appmarket@main
  with:
    token: ${{ secrets.DESKMODAL_REPO_TOKEN }}
```

The action fires a `repository_dispatch` at this repo with
`event_type: release-published` and your repo name + tag in the
payload. Our `aggregate.yml` workflow picks it up within seconds,
mirrors your release assets into appmarket's own releases, and
rebuilds `index.json`.

**This is the recommended pattern** — minimal ceremony, tightest
feedback loop, no extra jobs in your workflow graph.

### B. Reusable workflow (`workflow_call`)

If you prefer an explicit job node in your workflow graph:

```yaml
jobs:
  publish-release:
    runs-on: ubuntu-latest
    # ... your existing build + sign + release steps ...

  sync-to-appmarket:
    needs: [publish-release]
    uses: Desk-Modal/appmarket/.github/workflows/sync-release.yml@main
    secrets:
      token: ${{ secrets.DESKMODAL_REPO_TOKEN }}
```

This spins up a one-step runner that delegates to the composite action
above. Same effect, slightly more visible in the Actions UI, slightly
more runner-minutes.

### C. Direct `repository_dispatch` POST

If you want no dependency on this repo at all, call the GitHub API
directly from a shell step:

```yaml
- name: Notify appmarket
  env:
    GH_TOKEN: ${{ secrets.DESKMODAL_REPO_TOKEN }}
  run: |
    curl -sS -X POST -f \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/repos/Desk-Modal/appmarket/dispatches \
      -d '{"event_type":"release-published","client_payload":{"source_repo":"${{ github.event.repository.name }}","tag":"${{ github.ref_name }}"}}'
```

All three paths land at the same `aggregate.yml` workflow. You can
verify it fired at:

```
https://github.com/Desk-Modal/appmarket/actions/workflows/aggregate.yml
```

## Who can publish to this repo

- Only members of the `Desk-Modal` GitHub organization can push to
  `main`. Outside collaborators and fork PRs are blocked from merging.
- All changes go through pull request — `main` is protected and
  requires the `CI: all green` status check.
- The aggregator workflow uses `DESKMODAL_REPO_TOKEN` for cross-repo
  API access and `DESKMODAL_SIGNING_KEY` for detached signature
  generation. Both secrets live in the org-level secrets and are only
  exposed to workflows running on this repo.
- Fork pull requests cannot read org secrets and cannot trigger the
  aggregator workflow (guarded at the GitHub Actions policy level).

## License

MIT — see [LICENSE](LICENSE).

The content of individual plugins referenced by the catalog is
governed by each plugin's own license; see the `license` field on each
catalog entry.
