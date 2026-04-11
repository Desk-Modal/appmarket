# DeskModal AppMarket Icon System

**Owner**: UX Design Lead + Brand Visual Identity
**Scope**: Every app, service, and script listed in the DeskModal AppMarket catalog
**Source of truth**: this document. Any icon deviating from these rules is a defect.

---

## 1. Design Principles (10, no fluff)

1. **One skeleton, one family.** Every icon shares the same 128 canvas, same rounded-square base, same corner radius (28), same 8px safe-area inset, same 1px blue-tinted border. A grid of ten icons must read as one product.
2. **The mark is singular.** One dominant idea per icon. No competing shapes. If there are secondary strokes, they support the dominant idea — they do not share visual weight with it.
3. **Metaphor is literal, not clever.** Paper trading is a paper twin of a real book. A feed is source-to-channel flow. Depth is stratified pressure. No dollar signs. No upward-sloping lines. No three bars. No lightbulbs.
4. **Silhouette over detail.** The icon must survive being rendered at 16px in a desaturated toolbar. If the silhouette collapses into noise, the icon fails.
5. **Direction means something.** Green and red only appear when the product concept is directional (bullish/bearish/threshold). Neutral products use accent blue only.
6. **Gradients carry material, not decoration.** The market variant has a base gradient and a single inner glow. The toolbar variant has neither. Gradients never replace contrast.
7. **Family sub-marks are earned.** The `tradesurface.*` family shares a 3px accent dot in the top-right corner of the safe area — one pixel of identity. Services (paper-trading, price-feed-service) have no sub-mark because they are not part of that family.
8. **No text. No logos. No letterforms.** If an icon needs a letter to be understood, the metaphor is wrong.
9. **The grid is sacred.** Every stroke endpoint, center, and radius snaps to a 2px sub-grid of the 128 canvas. No 73.4. No 91.7. Snap or redo.
10. **If you hesitate, it is wrong.** An icon either reads immediately or it does not. Hesitation is the signal to redesign the metaphor, not to add detail.

---

## 2. Shared Skeleton Spec

Both tiers share the 128 canvas, viewBox, safe area, corner radius, and stroke primitives. They diverge on base fill and color discipline.

### 2a. Market tier (colored product art)

```
Canvas:           128 x 128
viewBox:          "0 0 128 128"
Safe area:        8 px inset on all sides (usable region: 112 x 112)
Base shape:       rounded square, rx=28 ry=28, filled with linear gradient
Inner glow:       radial #3b82f6 → transparent, opacity 0.35
Border:           1 px stroke, rgba(120, 150, 255, 0.18), drawn last
Stroke primitive: 6 px, round caps, round joins
Family marker:    3 px square at (113, 12) for tradesurface.* family only
```

**Layer order (market)**:
1. Gradient base fill `linear-gradient(135deg, #0b1120 0%, #1e293b 100%)`
2. Inner glow (radial `#3b82f6` at alpha 0.55 → 0, opacity 0.35)
3. Dominant mark(s) — colored per Color Token Table
4. Family marker (tradesurface.* only)
5. Border stroke (on top)

### 2b. Glass toolbar tier (translucent tile)

```
Canvas:           128 x 128
viewBox:          "0 0 128 128"
Safe area:        8 px inset on all sides
Base shape:       NONE — no fill. The DeskModal frosted panel shows through.
Border:           1 px stroke, rgba(120, 150, 255, 0.22), drawn last
Stroke primitive: 7.5 px for lines, 6 px for outlines that must survive 16 px
Fill opacity:     0.85 (never fully opaque)
Stroke opacity:   0.92 (monochrome mark, never 1.0)
Color:            #60a5fa only (monochrome). No green, no red, no gradients, no glow.
Family marker:    DROPPED in glass tier (sub-pixel at 16 px)
```

**Layer order (glass)**:
1. (no base fill)
2. Dominant mark(s) — `#60a5fa` at 0.85 fill / 0.92 stroke
3. Border stroke `rgba(120, 150, 255, 0.22)` (on top — it is the family signal)

The glass tile is designed to sit on DeskModal's existing frosted panels (`backdrop-filter: blur(14px) saturate(180%)` over blue-tinted borders). The icon itself is the only ink; the panel behind it provides the substrate.

---

## 3. Color Token Table

| Concept                    | Hex                         | DeskModal semantic       | Tier(s)        | Use                              |
|----------------------------|-----------------------------|--------------------------|----------------|----------------------------------|
| Accent (default mark)      | `#3b82f6`                   | `--ts-accent-default`    | Market         | Primary strokes and fills        |
| Accent (highlight)         | `#60a5fa`                   | `--ts-accent-hover`      | **Glass only** | The single glass-tier mark color |
| Accent (deep)              | `#2563eb`                   | `--ts-accent-active`     | Market         | Secondary strokes in market glow |
| Bullish / ascending        | `#22c55e`                   | `--ts-color-bullish`     | Market only    | Directional up — only if meaningful |
| Bearish / descending       | `#ef4444`                   | `--ts-color-bearish`     | Market only    | Directional down — only if meaningful |
| Base 0 (deepest surface)   | `#0b1120`                   | surface-0                | Market         | Market gradient bottom stop      |
| Base 1 (panel)             | `#1e293b`                   | surface-1                | Market         | Market gradient top stop         |
| Structural border (market) | `rgba(120, 150, 255, 0.18)` | border                   | Market         | Base shape stroke                |
| Structural border (glass)  | `rgba(120, 150, 255, 0.22)` | border hover             | Glass          | Glass tile border (slightly brighter so it survives the frost) |
| Family marker              | `#3b82f6`                   | accent                   | Market only    | 3 px dot top-right (tradesurface.*) |

**Rules**:
- No hex outside this table appears in any icon file. Ever.
- **Directional green/red appears in market tier only.** Glass toolbar tier is strictly monochrome `#60a5fa`. At 16 px on a frosted panel, a 2 px red dot is noise, not signal — so directional meaning in the glass tier is carried by geometry and position (e.g., left=buy / right=sell), never color.
- Glass tier has no base fill, no gradient, no glow, no secondary colors, no family marker dot.
- Market tier preserves the full tonal palette: gradient base + inner glow + directional color + accent-deep secondary strokes.

---

## 4. Two-Variant Pattern

Every catalog entry ships as two files. The two variants serve totally different surfaces and therefore obey different rules.

**Market variant** (`<id>-market.svg`) — **colored product art**:
- Lives on AppMarket cards, hero views, detail pages
- Gradient base fill + inner glow (opacity 0.35)
- Stroke weight: 6
- Full tonal range including directional green/red when the concept is directional
- Family marker dot for `tradesurface.*` family
- Rendered at 48 px on cards, 128 px on detail hero

**Toolbar variant** (`<id>-toolbar.svg`) — **translucent glass tile**:
- Lives on DeskModal toolbars, list rows, launcher tiles — all of which are already frosted-glass panels (`backdrop-filter: blur(14px) saturate(180%)`)
- **No base fill.** The DeskModal frosted panel shows through the icon.
- Border only: 1 px `rgba(120, 150, 255, 0.22)`, drawn last (the same blue hairline family signal as DeskModal panel borders).
- Dominant mark(s) in `#60a5fa` only — 0.85 fill opacity or 0.92 stroke opacity, never fully opaque.
- Stroke weight: 7.5 (6 for outlines that must survive 16 px downscale)
- Composition: MAX 2-3 silhouette elements. Feeds is the one exception (two circles + two paths read as a single fan).
- No directional color, no gradients, no glow, no family marker dot, no secondary accent colors.
- Rendered at 16 px and 24 px

### Worked example: `desk-modal.tradesurface.chart`

**Metaphor**: a single candlestick — the irreducible unit of a chart.

**Market variant — colored product art**:
A bullish green candle with ghost candles flanking it in accent-deep, a gradient base, and an inner glow. The `#22c55e` fill is earned because a chart is inherently directional.

```xml
<!-- desk-modal.tradesurface.chart — market -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="b" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0b1120"/>
      <stop offset="1" stop-color="#1e293b"/>
    </linearGradient>
    <radialGradient id="g" cx="0.5" cy="0.5" r="0.65">
      <stop offset="0" stop-color="#3b82f6" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#3b82f6" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="128" height="128" rx="28" fill="url(#b)"/>
  <rect width="128" height="128" rx="28" fill="url(#g)" opacity="0.35"/>
  <line x1="64" y1="22" x2="64" y2="106" stroke="#22c55e" stroke-width="6" stroke-linecap="round"/>
  <rect x="46" y="46" width="36" height="44" rx="4" fill="#22c55e"/>
  <rect x="113" y="12" width="3" height="3" fill="#3b82f6"/>
  <rect x="0.5" y="0.5" width="127" height="127" rx="27.5" fill="none" stroke="rgba(120,150,255,0.18)"/>
</svg>
```

**Glass toolbar variant — translucent tile**:
Same candlestick geometry, but monochrome. No base fill — the DeskModal frosted panel behind it provides the substrate. The body is `#60a5fa` at 0.85, the wick at 0.92, and the faint blue-hairline border sits on top.

```xml
<!-- desk-modal.tradesurface.chart — toolbar (glass) -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <line x1="64" y1="20" x2="64" y2="108" stroke="#60a5fa" stroke-opacity="0.92" stroke-width="7.5" stroke-linecap="round"/>
  <rect x="44" y="40" width="40" height="52" rx="4" fill="#60a5fa" fill-opacity="0.85"/>
  <rect x="0.5" y="0.5" width="127" height="127" rx="27.5" fill="none" stroke="rgba(120,150,255,0.22)"/>
</svg>
```

Note: the glass variant drops directional color (`#22c55e` → `#60a5fa`), drops ghost candles, drops the family marker dot, and drops the base fill. What remains is the essential candlestick silhouette, rendered as ink on DeskModal's frosted surface.

---

## 5. 16px Legibility Rules

A 128 px icon will be rendered at 16 px in toolbars. That is an 8x downscale. The glass tier is harder than the market tier, because without an opaque base fill there is less contrast against whatever frosted content sits behind the DeskModal panel.

**Minimum feature size**:
- **Market tier**: smallest mark ≥ 10 canvas units (scales to ~1.25 px)
- **Glass tier**: smallest mark ≥ **12 canvas units** (tightened — no opaque base means lower contrast, so features need more area)

**Keep in the glass tier**:
- The border hairline (1 px stroke reads as a hair at 16 px — this is the family signal)
- ONE dominant shape with a thick stroke (7.5 scales to ~0.94 px, readable)
- Fills on shapes larger than ~16 units (scales to 2 px)

**Drop in the glass tier**:
- Any shape smaller than 12 canvas units (scales to <1.5 px and vanishes on a frosted background)
- Directional green/red (2 px of red on a blurred mixed-color background is noise)
- Gradients and inner glow
- Family marker dot — 3 px at 128 canvas becomes 0.375 px at 16 px, pure sub-pixel noise. The family signal is carried by the shared skeleton (rounded square, blue hairline border, monochrome accent) in the glass tier.
- Decorative inner detail, concentric patterns, dot grids
- Any opaque base fill

**Simplify in the glass tier**:
- Multi-silhouette metaphors → one silhouette
- Small counted things (three rows, three dots) → two
- Mixed stroke weights → one weight (7.5 or 6)
- Fill + stroke on the same shape → pick one

**Test**: downscale each glass SVG to 16 px over a blurred frosted-glass background (not black). Check silhouette clarity and that the blue hairline border survives. If the mark collapses into a blob or the border disappears, redesign.

---

## 6. Naming Convention

```
<full-id>-<variant>.svg

examples:
  desk-modal.paper-trading-market.svg
  desk-modal.paper-trading-toolbar.svg
  desk-modal.tradesurface.chart-market.svg
  desk-modal.tradesurface.chart-toolbar.svg
```

- Full catalog id, verbatim, including dots. No abbreviations.
- Variant suffix always `-market` or `-toolbar`, lowercase.
- Extension always `.svg`.
- No versioning (`-v2`). Replace in-place, commit the diff.

---

## 7. Review Checklist

Before any icon ships, the reviewer confirms, in order:

1. **Valid XML**: parses, `viewBox="0 0 128 128"`, no external references, no `<image href>`, no cross-file `<use>`.
2. **Base shape correct**:
   - Market: `rect width="128" height="128" rx="28"` with gradient fill; border at `rgba(120,150,255,0.18)` drawn last.
   - Glass: NO base fill rect; border at `rgba(120,150,255,0.22)` drawn last.
3. **Safe area respected**: no mark extends outside the `(8,8)→(120,120)` region.
4. **Color discipline**: every fill/stroke maps to a value in the Color Token Table. No stray hex.
5. **Stroke weight**: market = 6, glass = 7.5 for the dominant mark (6 for outlines that must survive 16 px).
6. **Family marker**: present (3×3 at 113,12) if and only if the id starts with `desk-modal.tradesurface.` AND the variant is `-market`. Glass variants never carry the marker.
7. **Family coherence**: place alongside the other 19 icons. Does it feel like the same product? If not, redo.
8. **16 px silhouette**: visualize the glass variant at 16 px over a frosted-glass background. Is the dominant mark still recognizable and is the border hairline still visible?
9. **Metaphor sharpness**: does the icon read as its product function in under 500 ms by someone who has never seen it before? Ask two colleagues.
10. **Direction discipline**: green/red only in the market tier and only if the product is directional. Glass tier is always monochrome `#60a5fa`.
11. **Gradient discipline**: market has gradient + inner glow; glass has neither.
12. **Anti-pattern check**: no dollar signs, no rising arrows, no three horizontal bars, no gears, no lightbulbs, no generic documents.
13. **Glass tier purity**: glass tier has no base fill, no gradient, no glow, no green/red, no family marker dot. Every glass fill uses `#60a5fa` at 0.85 and every glass stroke uses `#60a5fa` at 0.92 (with occasional reduced-opacity variants for stratification, e.g. 0.55/0.60, still monochrome).

A single failed item blocks the icon. Fix and re-review.

---

## 8. Icon Index

| ID                                      | Market metaphor                         | Directional (market)? | Family marker (market) | Glass silhouette (toolbar)                                  |
|-----------------------------------------|-----------------------------------------|-----------------------|------------------------|-------------------------------------------------------------|
| `desk-modal.paper-trading`              | Paper ledger over real-book stubs       | No                    | No                     | Dashed ledger outline + 2 ruled lines (1 dominant, 3 marks) |
| `desk-modal.price-feed-service`         | Source core with directional arcs       | No                    | No                     | Dot + outer arc + sink bar (3 marks)                        |
| `desk-modal.tradesurface.feeds`         | Multi-source fan converging to channel  | No                    | Yes                    | 2 circles + 2 converging paths + channel bar (1 fan motif)  |
| `desk-modal.tradesurface.chart`         | Single bullish candlestick              | Yes (green)           | Yes                    | Wick + body monochrome (2 marks)                            |
| `desk-modal.tradesurface.watchlist`     | Stacked list rows                       | No                    | Yes                    | 2 pill rows (2 marks)                                       |
| `desk-modal.tradesurface.depth`         | Stratified bid/ask pressure profile     | Yes (green/red)       | Yes                    | Upper slab (0.92) + centerline + lower slab (0.60) (3 marks, monochrome) |
| `desk-modal.tradesurface.analytics`     | 2×2 correlation matrix                  | No                    | Yes                    | 4 cells: diagonal strong (0.92) / off-diagonal weak (0.55)  |
| `desk-modal.tradesurface.screener`      | Filter funnel                           | No                    | Yes                    | Funnel outline only (1 closed path)                         |
| `desk-modal.tradesurface.alerts`        | Spike crossing threshold line           | Yes (red spike)       | Yes                    | Threshold line + spike (2 marks, monochrome)                |
| `desk-modal.tradesurface.trading`       | Buy slab + price line + sell slab       | Yes (green/red)       | Yes                    | 2 slabs + price line (3 marks, monochrome — direction by position) |

Notes:
- Glass variants never carry the family marker (sub-pixel at 16 px).
- Glass variants never use directional green/red — when the concept is directional, the meaning is carried by geometry and position.
- The `feeds` glass variant is the one composition with four marks; it is permitted because the two circles + two converging paths read as a single fan silhouette.

---

*All icons in this directory are authored by hand against this spec. Regenerate only by editing the source SVGs, never by importing from a third-party set.*
