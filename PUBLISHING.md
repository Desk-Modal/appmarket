# Publishing to the DeskModal app market

DeskModal's app market is an **open ecosystem**. Anyone — individual
developers, independent studios, financial data vendors, quant firms,
enterprise IT teams — can publish apps, services, and scripts that
any DeskModal user on any OS can discover, install, and run.

This document is the end-to-end contract for publishers. If you
follow it, your release shows up in every DeskModal session's
marketplace within ~30 seconds of `git push --tags`.

## What you can publish

| Type | Description | Example |
|---|---|---|
| **App** | A FDC3-compliant UI plugin — HTML/JS/CSS or WASM, rendered in a DeskModal WebView | a chart, an order ticket, a watchlist |
| **Service** | A background process — native binary per platform, or a WASM fallback — that publishes data or exposes an intent handler | a price feed, a paper-trading EMS, an analytics engine |
| **Script** | A single-file OptiScript or WASM script invoked by other apps | an indicator, a trading strategy, a risk model |
| **Bundle** | A themed collection of the above that installs atomically | an "Analyst Pack" with charts + screeners + alerts |

There is no technical distinction at install time — all four are
packaged as `.tar.gz` archives containing a `plugin.toml` manifest and
the runtime files. The `content_type` field in `plugin.toml` tells the
marketplace which bucket to file the entry under.

## Publisher tiers

Every entry in the catalog has a `publisher` block with a `verified`
boolean. Verification only affects how the marketplace surfaces your
entry — it does **not** gate what you can publish. Unverified
publishers are first-class citizens of the catalog.

| Tier | How you get there | What it gives you |
|---|---|---|
| **Unverified** | Default for everyone. Publish a valid release; get listed. | Appears in search, listable under Browse, installable. Displays an "unverified publisher" badge next to your name. |
| **Verified** | Send a signed request to `publishers@deskmodal.com` from the domain listed in your `plugin.toml`. A Desk-Modal admin adds your Ed25519 public key to `sources.json`'s `publisher_keys` block and marks `publisher.verified = true` for your entries. | "Verified" badge, eligible for Featured surfacing, can be listed in curated category feeds. |
| **Featured** | Editorial decision by Desk-Modal. Usually applied to verified publishers whose content meets a quality bar. | Surfaces on the marketplace home screen. Carries no extra trust guarantee beyond verified. |

**Important**: verification is a reputational signal, not a security
gate. Every release — verified or not — must be signed with the
publisher's Ed25519 key, and DeskModal clients always verify the
signature against the key bound to that publisher in the catalog.
An unverified publisher who signs correctly is trusted exactly as
much as a verified publisher, for exactly the assets they sign for.

## The publishing pipeline

```
┌─────────────────────────────┐
│ 1. Your GitHub repo         │
│    (public or private)      │
│                             │
│   git tag v1.2.3            │
│   git push --tags           │
└───────────┬─────────────────┘
            │ triggers your release.yml
            ▼
┌─────────────────────────────┐
│ 2. Your release workflow    │
│                             │
│  - Build per-platform       │
│    tarballs                 │
│  - Generate checksums.txt   │
│  - Sign with Ed25519        │
│  - Create GitHub Release    │
│    with assets              │
└───────────┬─────────────────┘
            │ final step: notify-appmarket
            ▼
┌─────────────────────────────┐
│ 3. Desk-Modal/appmarket     │
│    aggregator               │
│                             │
│  - Mirrors your release     │
│    assets (private repos    │
│    only — see below)        │
│  - Rebuilds index.json      │
│  - Signs index.json with    │
│    DeskModal publisher key  │
│  - Commits + pushes         │
└───────────┬─────────────────┘
            │ served via raw.githubusercontent.com CDN
            ▼
┌─────────────────────────────┐
│ 4. Every DeskModal session  │
│    on earth                 │
│                             │
│  - Fetches index.json       │
│  - Verifies signature       │
│  - Surfaces your entry      │
│  - Downloads + installs     │
│    your tarball on demand   │
└─────────────────────────────┘
```

## Step 0 — pick your repo model

You have two deployment models to choose from:

### Model A: Public repo, direct serving (simplest)

Your repo is public. Your release assets are served directly from your
own GitHub Releases URL. `appmarket`'s `index.json` links to your
asset URLs. Nothing gets mirrored.

**Pros**: zero trust handoff to Desk-Modal, you own the CDN path,
audit trail of downloads lives in your repo.
**Cons**: if you ever take your repo private, every install URL in
the catalog breaks — we catch this at the next aggregator run and
drop the entry with a warning.

### Model B: Private repo, mirrored into appmarket (what Desk-Modal uses for its own services)

Your repo is private. Your release workflow grants a read-only token
to `Desk-Modal/appmarket` (via a deploy key or a fine-grained PAT)
and our aggregator mirrors every release asset into a public
`appmarket` release tagged `{your-repo-name}-v{version}`. The
catalog points at the `appmarket`-side URLs, so the binary is public
even though the source code isn't.

**Pros**: source stays private, the public asset URL is stable even
if your repo later gets renamed or archived.
**Cons**: requires one-time setup to grant appmarket read access to
your release assets, and the mirror eats storage on appmarket's side
(cleanup via retention policy).

Both models use the same notify + aggregate pipeline — the
difference is whether your release assets get copied or referenced.

## Step 1 — build your release artifacts

Your release workflow must emit the following asset set on every tag
push:

| Asset | Required? | Purpose |
|---|---|---|
| `{name}-{version}-win32-x64.tar.gz` | at least one platform required | Native build for Windows x64 |
| `{name}-{version}-darwin-arm64.tar.gz` | " | Native build for Apple Silicon |
| `{name}-{version}-darwin-x64.tar.gz` | " | Native build for Intel Macs |
| `{name}-{version}-linux-x64.tar.gz` | optional | Native build for Linux (not currently a DeskModal target) |
| `{name}-{version}-wasm.tar.gz` | optional | Cross-platform WASM fallback (required if you don't ship all three natives) |
| `plugin.toml` | yes | The manifest DeskModal reads at install time |
| `checksums.txt` | yes | SHA-256 of every tarball, one per line, in `sha256sum` format |
| `SIGNATURE` | yes | Ed25519 signature over `checksums.txt` produced with your publisher key |

If your plugin ships only a WASM variant, you only need the
`{name}-{version}-wasm.tar.gz`. Every native platform your entry
lists **must** be present in the release as a matching asset, or
the aggregator drops the platform from the entry with a warning.

## Step 2 — structure the tarball

Each platform tarball extracts into a single top-level directory
named `{name}-{version}-{platform}/` containing at minimum:

```
{name}-{version}-{platform}/
├── plugin.toml              # same file as uploaded separately
├── {runtime files}          # .wasm / .dll / .dylib / HTML / JS ...
└── icon.svg                 # optional, overrides the catalog icon
```

See `https://github.com/Desk-Modal/appmarket/releases/download/paper-trading-v0.1.2/deskmodal.paper-trading-0.1.2-win32-x64.dmpkg.tar.gz`
for a reference layout.

## Step 3 — wire the release workflow

Copy this template into `.github/workflows/release.yml` in your
repo. The relevant bit is the `notify-appmarket` step at the very
end. Everything above it is your normal build + sign + publish
flow — the template below shows how `paper-trading` does it.

```yaml
name: Release

on:
  push:
    tags: ["v*"]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: windows-latest
            target: x86_64-pc-windows-msvc
            platform: win32-x64
          - os: macos-latest
            target: aarch64-apple-darwin
            platform: darwin-arm64
          - os: macos-latest
            target: x86_64-apple-darwin
            platform: darwin-x64
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      # ... your per-platform build steps ...
      - name: Package tarball
        run: |
          tar czf "myplugin-${GITHUB_REF_NAME#v}-${{ matrix.platform }}.tar.gz" \
              -C staging "myplugin-${GITHUB_REF_NAME#v}-${{ matrix.platform }}"
      - uses: actions/upload-artifact@v4
        with:
          name: tarball-${{ matrix.platform }}
          path: myplugin-*.tar.gz

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          path: dist
          merge-multiple: true

      - name: Generate checksums.txt
        run: |
          cd dist && sha256sum *.tar.gz > checksums.txt

      - name: Sign checksums.txt with Ed25519
        env:
          SIGNING_KEY: ${{ secrets.MYPLUGIN_SIGNING_KEY }}
        run: |
          pip install cryptography
          python3 <<'PY'
          import os
          from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
          k = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(os.environ['SIGNING_KEY']))
          data = open('dist/checksums.txt','rb').read()
          open('dist/SIGNATURE','wb').write(k.sign(data))
          PY

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: |
            dist/*.tar.gz
            dist/checksums.txt
            dist/SIGNATURE
            plugin.toml

      # ---- THIS is the one line that hooks your release into appmarket ----
      - uses: Desk-Modal/appmarket/.github/actions/notify-appmarket@main
        with:
          token: ${{ secrets.APPMARKET_DISPATCH_TOKEN }}
```

### What `APPMARKET_DISPATCH_TOKEN` needs to be

It's a fine-grained GitHub PAT with one permission:
`contents: read/write` on `Desk-Modal/appmarket` — specifically the
`repository_dispatch` API, which requires `contents: write`. Nothing
else. No access to any other repo. Create it under your own account
or a bot account, store it as a repository secret in your publishing
repo named `APPMARKET_DISPATCH_TOKEN`.

Do not reuse this token for anything else. If it leaks, rotate it.

## Step 4 — register with sources.json (one-time)

Once your release workflow is set up, open a pull request against
this repo that adds your source to `sources.json`:

```jsonc
{
  "sources": [
    // ... existing entries ...
    {
      "owner": "your-github-org",
      "repo": "your-plugin-repo",
      "mode": "single_release",
      "content_type": "app",
      "id": "your-org.your-plugin",
      "display_name": "Your Plugin",
      "tagline": "One-sentence description, <80 chars",
      "categories": ["trading"],
      "tags": ["search", "hints"],
      "featured": false,
      "asset_name_template": "yourplugin-{version}-{platform}.tar.gz",
      "publisher_key_id": "your-publisher-key-id",
      "mirror": false  // true if you want Model B (private-repo mirroring)
    }
  ],
  "publisher_keys": {
    "your-publisher-key-id": {
      "algorithm": "ed25519",
      "public_key_hex": "the hex-encoded public key half of MYPLUGIN_SIGNING_KEY",
      "owner": "your-github-org",
      "valid_from": "2026-04-11T00:00:00Z"
    }
  }
}
```

The PR is reviewed by CODEOWNERS and must pass the
`validate sources.json + index.json` CI gate before merge. After
merge, the next aggregator run picks up your entry (or the
`repository_dispatch` your next release fires — whichever comes
first).

## Step 5 — publish

```bash
git tag v1.0.0
git push origin v1.0.0
```

Your release workflow builds, signs, publishes the GitHub Release,
and fires `notify-appmarket`. Within ~30 seconds:

1. `Desk-Modal/appmarket/.github/workflows/aggregate.yml` runs
2. Your release's assets get mirrored (Model B) or pointed at (Model A)
3. `index.json` rebuilds with your new version
4. Every DeskModal session's next marketplace refresh surfaces it

## Troubleshooting

### "My release fired but the catalog didn't update"

Check `https://github.com/Desk-Modal/appmarket/actions/workflows/aggregate.yml`
for the most recent run. The `Log dispatch context` step prints the
`source_repo`, `tag`, and `fired_by` from your `client_payload`. If
your run isn't there, the `notify-appmarket` step probably failed
inside your own workflow — check its logs.

### "The aggregator found my release but dropped my entry"

The aggregator emits a `[drop]` line in its log for every entry it
refuses. Common reasons:
- No `asset_name_template` match — the filename you uploaded doesn't
  match the pattern you declared in sources.json
- No installable platform — neither a native nor a wasm tarball
  matched your entry's `platforms` map
- Signature verification failed — the `SIGNATURE` file didn't
  validate against the publisher key bound to your entry
- Checksum mismatch — what the aggregator downloaded doesn't hash to
  what your `checksums.txt` said it should

### "DeskModal clients aren't seeing my entry"

The raw CDN caches `index.json` for up to 5 minutes. If the
aggregator completed more than 5 minutes ago and clients still see
the old catalog, purge the CDN by running `curl -X PURGE` against
the raw URL — or just wait.

## Security model

- Every release asset is signed with an Ed25519 key the publisher
  controls. The client verifies this signature before extracting the
  tarball.
- The aggregator verifies the signature before writing the catalog
  entry. A release with a broken signature never makes it into the
  catalog.
- The whole `index.json` is signed with the Desk-Modal publisher key
  so clients can verify the catalog itself hasn't been tampered with
  in transit or on the CDN.
- Publisher keys are bound to publishers in `sources.json` — a
  publisher can't spoof another publisher's signatures because the
  client checks the signature against the key bound to the entry's
  publisher block.
- Trust-level decisions (featured, verified) are editorial and
  mutable; they don't affect what a signature proves.
