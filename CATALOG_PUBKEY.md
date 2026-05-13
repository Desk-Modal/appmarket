# DeskModal App Market — Catalog signing public key

Clients verify `index.json` against this Ed25519 public key. The DeskModal
agent reads it from the `DESKMODAL_CATALOG_PUBKEY_HEX` environment
variable at boot (`platform/apps/deskmodal-agent/src-tauri/src/state.rs`,
the catalog verifier closure).

```
DESKMODAL_CATALOG_PUBKEY_HEX=629f5a25328468e9d55c22e2b48182cd9f91889cbc3027de583bbc5837cfcc80
```

## Verification flow

1. DeskModal fetches `index.json` from `DESKMODAL_PLUGIN_INDEX_URL`
   (default `https://raw.githubusercontent.com/Desk-Modal/appmarket/main/index.json`).
2. Fetches `index.json.sig` from the sibling path.
3. Loads the public key from `DESKMODAL_CATALOG_PUBKEY_HEX`.
4. Calls `deskmodal_security::CodeSigningVerifier::verify_signature`
   over `(index.json bytes, sig)`.
5. On `Verified` → sets `state.catalog_verified = true` (atomic flag).
6. Install commands gate on this flag via
   `commands::app::gate_catalog_verified`. A failed gate returns
   `CatalogNotVerified` error to the marketplace UI.

## Signing flow

`scripts/sign-catalog.sh` signs `index.json` with `.signing-key.hex`
(gitignored, kept local + in GitHub Actions secret
`DESKMODAL_CATALOG_SIGNING_KEY`). Runs automatically after
`scripts/lib/build_appmarket_catalog.py` regenerates the index.

## Key rotation

Run `plugin-tools/dmpkg keygen --output marketplace/appmarket/keys/` to
produce a fresh keypair. Update this file with the new public hex,
commit, then push the new `index.json.sig` produced under the new key
in the same commit cycle. Clients running with the OLD pubkey will
refuse to verify until they pick up the new public hex from the
deployment manifest.
