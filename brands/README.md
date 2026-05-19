# DeskModal brand marketplace

This directory hosts the catalog of signed `.dmbrand` bundles distributed
via the DeskModal app market. Companion to `releases/plugins/` — same
publishing model, different content type.

## Scope

`.dmbrand` bundles ship comprehensive brand definitions per F152 spec §4
(palette / typography / spacing / radii / motion / glassmorphism / iconography /
window-decorations / chart-styling / trading-tokens / assets / brand-mark).
Unlike `.dmpkg` (which carries executable code), `.dmbrand` is asset- and
config-only — no native binaries, no scripts.

## Layout

```
brands/
├── README.md
└── <brand-id>/
    └── <version>/
        ├── brand.toml              (thin metadata + sig pointer)
        ├── manifest.json           (full BrandManifest)
        ├── publisher.pub           (Ed25519 verify-key — 32 bytes)
        ├── brand.sig               (Ed25519 signature — 64 bytes)
        ├── <brand-id>.dmbrand      (signed gzip-tar bundle)
        └── checksums.txt           (SHA-256 sidecar)
```

The signed bundle (`.dmbrand`) is the canonical install artefact. The
adjacent uncompressed `brand.toml` + `manifest.json` exist for catalog
search + storefront preview (UIs read these without extracting the bundle).

## Publishing pipeline

1. Brand author runs `dmpkg sign --brand <dir> --key <publisher-key>` —
   produces `<id>-<version>.dmbrand` gzip-tar containing the signed manifest
   + assets + publisher.pub + brand.sig.
2. Author commits the bundle (+ uncompressed metadata) under
   `brands/<brand-id>/<version>/`.
3. The aggregator's `build_appmarket_catalog.py` script ingests new entries
   and regenerates `marketplace/plugin-index/index/brands.json`.
4. Catalog signing — root catalog `index.json` is re-signed by the marketplace
   key on every aggregate update.

## Publisher tiers

Per F152 schema.md §1 every brand declares one of:

| Tier | Onboarding | Catalog placement |
|---|---|---|
| `community` | Self-serve after publisher signup approval | Browse-all |
| `verified` | One manual review by DeskModal curation | Surfaced in `Verified` filter |
| `certified` | DeskModal-published or partner-published | Top of storefront |

## See also

- `specs/152-branding-single-capability-sota/spec.md §7` — bundle shape + verification.
- `specs/152-branding-single-capability-sota/schema.md §17` — `brand.toml` schema.
- `plugin-tools/src/commands/sign_brand.rs` — bundle signer.
- `plugin-tools/src/commands/verify_brand.rs` — signature verifier.
- `marketplace/plugin-index/index/brands.json` — the search-indexed catalog.
