# Script-Pack Schema (OptiScript reference scripts — L7)

Reference-script bundles ship one or more OptiScript `.opti` sources that
DeskModal surfaces register at install time — the chart indicator dialog,
the screener panel, the alert builder, and the drawing-tool registry. They
follow the standard plugin contract from `schema.md` (Ed25519 signed,
served via the public appmarket release surface) and add the `[[scripts]]`
block documented here, surfaced into the catalog entry as `script_pack`.

This mirrors the `[[indicators]]` indicator-pack precedent: **one
PluginEntry packs N scripts of one kind** (an `indicators` bundle, an
`algos` bundle, etc.), NOT one catalog row per `.opti`. A reference library
of 56 scripts therefore lands as ~5 kind-bundled entries, keeping the
catalog lean.

A plugin is **script-pack-shaped** when its `plugin.toml` has:

- `content_type = "script"` AND
- `categories ⊇ ["scripting"]` (an indicator bundle that also chart-registers
  may additionally carry `["indicator-pack"]`) AND
- at least one `[[scripts]]` entry.

The consuming surface reads the catalog entry directly: it filters by
`script_pack.scripts[].kind` and previews per-script metadata pulled from the
block without unpacking the `.dmpkg` tarball.

## `[[scripts]]` — required, one entry per `.opti`

Each entry declares a single reference script the bundle contributes. The
values mirror the script's own `manifest { … }` header inside the `.opti`
source.

```toml
[[scripts]]
path = "indicators/rsi.opti"            # path inside the .dmpkg optiscript/ tree
kind = "indicator"                       # indicator | algo | screener | alert | drawing
display_name = "RSI"                     # ≤60 chars; shown in the browser
intents_handled = ["deskmodal.IndicatorRsi"]   # from the .opti manifest { intents.handle }
broadcasts = ["deskmodal.indicator.rsi"]        # from the .opti manifest { broadcasts }
source_sha256 = "…64 hex chars…"         # SHA-256 of the .opti source bytes
conformance = "pass"                     # dmpkg test verdict: pass | compile-only | absent
```

### Field semantics

| Field | Type | Constraint |
|---|---|---|
| `path` | string | relative path inside the `.dmpkg` `optiscript/` tree; no leading `/`, no `..` |
| `kind` | string | one of: `indicator`, `algo`, `screener`, `alert`, `drawing` |
| `display_name` | string | 1-60 chars; user-visible label |
| `intents_handled` | string[] | FDC3 intents the script handles; **required non-empty** for `indicator`/`algo`/`screener`/`alert`; optional for `drawing` |
| `broadcasts` | string[] | FDC3 channels/contexts the script broadcasts |
| `source_sha256` | hex string | 64-char SHA-256 of the `.opti` source bytes (provenance; pairs the F143-D `script_source_hash` audit primitive) |
| `conformance` | string | `dmpkg test` verdict — `pass` \| `compile-only` \| `absent` |

### Kinds

The kind set is closed and maps to the five `reference/` subdirs:

- `indicator` — RSI/MACD/Bollinger/VPVR/TPO/footprint families (chart indicator dialog)
- `algo` — TWAP/VWAP/Iceberg/Sniper/Peg/multi-leg execution algorithms
- `screener` — market-scan filter scripts (screener panel)
- `alert` — alert-condition scripts (alert builder)
- `drawing` — drawing-tool extension scripts (drawing registry)

### `engine_min_version`

The bundle declares the optiscript-runtime compat floor once, surfaced as
`script_pack.engine_min_version`. A bundle declaring `0.2.0` against an
installed runtime at `0.1.5` is refused at install time, the same way an
indicator pack's chart-engine range is enforced.

## Conformance — the `dmpkg test` producer gate (L6)

Before pack, the publisher runs `dmpkg test <.opti>` per script. The CLI
compiles + sema-checks + (where golden bars exist) numeric-conformance-checks
each script, and the verdict populates `conformance`:

- `pass` — full numeric conformance against golden bars.
- `compile-only` — parsed + sema-checked but no golden fixture supplied.
- `absent` — not run.

The publisher publish-gate (`validate_catalog.py --category script
--manifest plugin.toml`) REQUIRES every script at `conformance == "pass"`;
a `compile-only` or `absent` script blocks publish (rc≠0). The storefront
renders a "verified-numeric" badge from this field.

## Aggregator + Verification Gateway behaviour

The appmarket aggregator (`scripts/aggregate.py::script_pack_metadata`)
passes the `[[scripts]]` block through into the catalog entry's
`script_pack` object (alongside the existing `platforms`, `signature`,
etc.), emitting it only when the block is well-formed (every script carries
a valid `kind` + 64-hex `source_sha256` + known `conformance`) — a malformed
block is dropped rather than zero-filled.

The Verification Gateway
(`scripts/verification_gateway.py::validate_script_pack`,
`validate_script_entry`, `validate_manifest_script`) treats a script bundle
as APPROVED iff:

1. `content_type == "script"` AND the bundle declares a non-empty
   `script_pack` (`[[scripts]]`).
2. Every script parses against the §Field semantics table above (closed
   `kind` set; 64-hex `source_sha256`; intent presence for
   indicator/algo/screener/alert kinds).
3. (publish gate) Every script is at `conformance == "pass"`.
4. The bundle is Ed25519-signed by the declared publisher key — the
   entry-level `signature` is reused verbatim; there is **no per-`.opti`
   signature**, per-script integrity binds via `source_sha256`.

A plugin that declares `content_type = "script"` but ships no `[[scripts]]`
entries is REJECTED — the bundle is a contract, not a marketing tag.

## Sign / validate roundtrip

The cryptographic roundtrip is 100% reused from the shipped `dmpkg`
machinery — only content-level validation is new:

1. **Author** in the OptiScript repo: `plugin.toml [[scripts]]` + the
   `optiscript/<kind>/<name>.opti` tree.
2. **Pre-pack gate (L6):** `dmpkg test optiscript/<kind>/<name>.opti` per
   script → verdict → recorded into `[[scripts]] conformance` +
   `source_sha256`.
3. **Pack+sign:** `dmpkg pack` (includes `optiscript/`) → `.dmpkg` →
   `dmpkg release --sign` → `.tgz` + `.tgz.sig` (Ed25519) + SLSA subject.
4. **Aggregate:** `aggregate.py` emits a `content_type:script` entry with
   `script_pack` + the standard entry-level `signature` pointer block.
5. **Publish-gate:** `validate_catalog.py --category script --manifest
   plugin.toml` enforces PRESENCE + conformance=pass → rc≠0 blocks publish;
   the index gate enforces VALIDITY only.
6. **Discover + verify-on-read:** plugin-index `search(content_type=Script,
   script_kind=Indicator)` returns a verified listing; the entry-level
   Ed25519 signature is checked before any listing crosses outward — script
   entries flow through the existing signed-discovery path unchanged.

## Dependency resolution

Reference scripts may depend on the OptiScript runtime + the consuming
surface via the standard `[[requires]]` block:

```toml
[[requires]]
id = "deskmodal.optiscript-runtime"
version = ">=0.1.0"
reason = "reference scripts execute on the OptiScript universal execution host"
```

The version range is enforced at install time before any script registers.
