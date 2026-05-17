# Indicator-Pack Schema

Indicator-pack plugins ship one or more chart indicators that the
DeskModal chart engine registers at install time. They follow the
standard plugin contract from `schema.md` (Ed25519 signed, served via
the public appmarket release surface) and add the `[indicators]` block
documented here.

A plugin is **indicator-pack-shaped** when its `plugin.toml` has:

- `[plugin] type = "service"` AND
- `categories ⊇ ["indicator-pack"]` AND
- at least one `[[indicators]]` entry.

The chart engine consumes the catalog entry directly: the right-rail
indicator dialog filters by `categories` and previews per-indicator
metadata pulled from the `[indicators]` block without unpacking the
tarball.

## `[[indicators]]` — required, one entry per indicator

Each entry declares a single indicator the pack contributes.

```toml
[[indicators]]
id = "acme.adaptive-rsi"          # globally unique within the pack
display_name = "Adaptive RSI"      # ≤40 chars; shown in the indicator browser
category = "momentum"              # one of the indicator-registry categories (§Categories below)
description = "RSI with adaptive smoothing window driven by realised vol."
inputs = ["close", "length"]       # OptiScript series / param names
outputs = ["rsi", "signal"]        # series names broadcast on the FDC3 indicator-results channel

[indicators.preview]
# Sparkline data the marketplace tile renders without instantiating the indicator.
# 64 little-endian f32 values; rendered as a 64×16 SVG sparkline.
# Encoded as a hex string for TOML-friendliness.
sparkline = "0000803f...64-f32-values-as-hex..."
```

### Field semantics

| Field | Type | Constraint |
|---|---|---|
| `id` | string | `[a-z][a-z0-9-]*(\.[a-z0-9-]+)*` — reverse-DNS within the pack |
| `display_name` | string | 1-40 chars; user-visible label |
| `category` | string | one of: `trend`, `momentum`, `volatility`, `volume`, `cycle`, `pattern`, `breadth`, `statistical`, `custom` |
| `description` | string | 1-280 chars; rendered in the indicator browser tooltip |
| `inputs` | string[] | OptiScript inputs the indicator binds at evaluation time |
| `outputs` | string[] | series the indicator publishes on the FDC3 results channel |
| `preview.sparkline` | hex string | optional; 256 bytes (64 f32 LE) hex-encoded |

### Categories

The category set is closed and curated by the chart engine — adding a
new category requires a coordinated change across `indicator-registry`
(plugins/tradesurface) and the schema doc. The current set:

- `trend` — moving averages, regression channels, supertrend variants
- `momentum` — RSI/Stoch/CCI/ROC families
- `volatility` — ATR/Bollinger/Keltner/Donchian
- `volume` — OBV, VWAP variants, volume profile
- `cycle` — Ehlers cycle detectors, Hilbert transforms
- `pattern` — fractal detectors, swing pivots, harmonic patterns
- `breadth` — A/D line, McClellan, market-internal aggregates
- `statistical` — Z-score, percentile rank, correlation
- `custom` — anything that doesn't fit the curated buckets

## `[services]` — the runtime entry

An indicator-pack ships as a service plugin (the indicator runtime is a
cdylib loaded by the chart engine). The standard `[[services]]` block
is required:

```toml
[[services]]
id = "acme.indicator-pack-momentum"
name = "Acme Momentum Indicator Pack"
description = "5 adaptive momentum indicators."
entryPoint = "services/libindicator_pack.dylib"   # platform-suffixed at install
runtime = "native"                                  # WASM permitted; native preferred for hot loops
broadcasts = ["fdc3.indicatorResult"]
intents = ["acme.RegisterIndicators"]
healthCheckIntervalSec = 60
```

The chart engine raises `acme.RegisterIndicators` on the pack's service
once on install/start; the pack responds by `addContextListener` on the
chart engine's evaluation channel for every declared `[[indicators]]`
entry.

## Aggregator + Verification Gateway behaviour

The appmarket aggregator passes the `[indicators]` block through into
the catalog entry's `indicators[]` array (alongside the existing
`platforms`, `signature`, etc.). The Verification Gateway treats an
indicator-pack manifest as APPROVED iff:

1. `plugin.type == "service"` AND `plugin.categories ⊇ ["indicator-pack"]`.
2. Every `[[indicators]]` entry parses against the §Field semantics
   table above (including the closed `category` set).
3. The native cdylib is Ed25519-signed by the declared publisher key.
4. The service crate compiles + passes the pack's own `cargo test`
   target (covered by the publisher's CI before tag).

A plugin that declares the indicator-pack category but ships no
`[[indicators]]` entries is REJECTED — the category is a contract, not
a marketing tag.

## Dependency resolution

Indicator packs may depend on the chart engine via the standard
`[[requires]]` block:

```toml
[[requires]]
id = "deskmodal.chart"
version = ">=1.0.0"
reason = "indicator-pack registers against the chart engine's indicator registry"
```

The chart-engine version range is enforced at install time: a pack
declaring `>=1.2.0` against an installed chart at `1.1.5` is refused
by the dependency resolver before any cdylib loads.

## Authoring

```sh
deskmodal plugin init <name> --type indicator-pack --publisher <org> --description '…'
cd <name>
# scaffold ships one stub indicator + tests; replace + extend
cargo test            # verifies the runtime compiles + indicators register
deskmodal plugin sign --key <publisher-key>
git tag v0.1.0 && git push origin v0.1.0
# the .github/workflows/publish.yml runs dmpkg release + aggregator dispatch
```

See `plugin-tools/typescript/src/templates/indicator-pack/` for the
scaffold templates the `init` command renders.
