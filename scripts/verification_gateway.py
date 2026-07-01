#!/usr/bin/env python3
"""
Capability Verification Gateway — §27.12 / §27.11 presence + validity checks.

The §27 capability contract requires every published capability to declare:
  - `[license]` (spdx, + notice + terms_url) — §27.12
  - `[bundle] tier` ∈ {required, recommended, optional} — §27
  - `[resources]` footprint (disk_mb, ram_mb_idle, ram_mb_peak, cpu_pct_steady) — §27.11

The presence/validity validators below are pure + dependency-free. The genuine
Ed25519 sign/verify functions (`verify_ed25519_signature_bytes`,
`resolve_trusted_public_key`, `verify_release_signature`) additionally require
the `cryptography` package and are used by the aggregator to cryptographically
verify a release's detached `SIGNATURE` over its `checksums.txt` before a catalog
entry is emitted — they FAIL LOUD (never a silent pass) when the backend is
absent.

This module is the validation core shared by:
  - the publisher pre-publish gate (`validate_catalog.py --category capability
    --manifest plugin.toml`), which enforces FULL PRESENCE — a publish missing
    license/tier/resources is rejected (rc≠0); and
  - the index gate (`validate_catalog.py --category capability`), which enforces
    VALIDITY of whatever each catalog entry declares + license presence.

Catalog-entry vocabulary matches the plugin-index discovery types (lane PI-1):
`capability_tier` (lowercase string) + `resources` object. Tier strings are
lowercase to match `plugin.toml [bundle] tier = "..."` and the Rust serde repr.
"""

from __future__ import annotations

import hashlib
import re
from typing import Any, Optional

# Lowercase to match plugin.toml `[bundle] tier` + plugin-index serde repr.
VALID_CAPABILITY_TIERS = frozenset({"required", "recommended", "optional"})

# §27.12 OFFERING (selling) model enum. DeskModal-MANAGED licensing: the catalog
# `offering` block is SELLING metadata (the publisher-LISTED price tag DeskModal
# sells at), NOT a licensing authority. License issuance/verification/entitlement
# are ALWAYS the DeskModal backend (core-server-api: POST /api/licenses,
# POST /api/licenses/verify-anonymous, GET /api/entitlements) — never a publisher
# endpoint. Byte-identical to dmpkg `VALID_OFFERING_MODELS`, the aggregator
# `_OFFERING_MODELS`, and the plugin-index `LicenseModel` serde repr (cross-repo
# parity contract). Lowercase / kebab-case.
VALID_OFFERING_MODELS = frozenset(
    {"subscription", "per-seat", "per-api-call", "one-time", "trial"}
)

# --------------------------------------------------------------------- #
# L7 — .opti reference-script catalog contract                           #
# --------------------------------------------------------------------- #
# A reference-script bundle is ONE PluginEntry with content_type "script"
# carrying a `script_pack` block (one entry per `.opti` in the bundle's
# optiscript/ tree). The five `kind` values map to the five reference/
# subdirs (indicator/algo/screener/alert/drawing) — each is a distinct UX
# surface (chart indicator dialog / screener panel / alert builder /
# drawing extension), so the generic content_type=script classifier is not
# sufficient for discovery. These constants + validators are the content
# half of the AM-1 gateway: the cryptographic Ed25519 sign/verify roundtrip
# stays entry-level (signature{}) and is reused verbatim.

# Lowercase to match the plugin-index `ScriptKind` serde repr (lane PI-1).
VALID_SCRIPT_KINDS = frozenset(
    {"indicator", "algo", "screener", "alert", "drawing"}
)

# dmpkg-test (L6) conformance verdict surfaced into the catalog so the
# storefront can render a "verified-numeric" badge. `pass` = full numeric
# conformance; `compile-only` = parsed + sema-checked but no golden fixture;
# `absent` = not run.
VALID_CONFORMANCE = frozenset({"pass", "compile-only", "absent"})

# Kinds for which an intent handler is the whole point of the script — a
# reference indicator/algo/screener/alert with no `intents_handled` cannot be
# raised against and is therefore malformed. `drawing` extends a drawing tool
# and need not handle an FDC3 intent.
SCRIPT_KINDS_REQUIRING_INTENTS = frozenset(
    {"indicator", "algo", "screener", "alert"}
)

# SHA-256 of the .opti source bytes (provenance; pairs F143-D
# script_source_hash). 64 lowercase-or-uppercase hex chars.
_SHA256_HEX = re.compile(r"^[0-9a-fA-F]{64}$")
# optiscript-runtime compat floor — SemVer (no pre-release suffix required).
_SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$")

# The four §27.11 footprint dimensions. disk/ram are integer MB; cpu is a float
# percentage. All must be present + non-negative for a declared `[resources]`.
RESOURCE_INT_FIELDS = ("disk_mb", "ram_mb_idle", "ram_mb_peak")
RESOURCE_FLOAT_FIELDS = ("cpu_pct_steady",)


def _err(path: str, msg: str) -> dict[str, str]:
    return {"path": path, "severity": "error", "message": msg}


def _is_number(v: Any) -> bool:
    # bool is a subclass of int — reject it explicitly so `true` ≠ 1.
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def validate_license(license_value: Any, path: str = "license") -> list[dict[str, str]]:
    """A published capability must carry a non-empty SPDX/license string."""
    if not isinstance(license_value, str) or not license_value.strip():
        return [_err(path, "license must be a non-empty SPDX identifier string")]
    return []


def validate_offering(
    offering: Any, path: str = "offering"
) -> list[dict[str, str]]:
    """
    Validate a §27.12 `offering` SELLING-metadata block (catalog or manifest
    `[license.commercial]`).

    DeskModal-MANAGED licensing: this block is the publisher-LISTED price tag
    DeskModal sells at — model/price/trial_days/required_grants are DISPLAY/selling
    metadata only. It is NOT a licensing authority. License issuance, verification,
    and entitlement are ALWAYS the DeskModal backend (core-server-api:
    POST /api/licenses + POST /api/licenses/verify-anonymous + GET /api/entitlements);
    the runtime checks DeskModal, never a publisher endpoint.

    A publisher MUST NOT declare a `license_check_endpoint` — a publisher pointing
    the license check at its own (or an attacker's) URL is exactly the threat this
    gate closes. A non-empty `license_check_endpoint` is REJECTED here; the field
    is never validated as a legitimate authority and never propagated. (Mirrors the
    dmpkg `validate_offering` rejection so a manifest passes/fails BOTH gates
    identically — cross-repo parity.)

    `None` ⇒ no commercial offering (free App) ⇒ no findings. `price` may be empty
    at the manifest boundary (a dormant community-tier placeholder); the aggregator
    drops an empty-price block so it never surfaces in the catalog.
    """
    if offering is None:
        return []
    if not isinstance(offering, dict):
        return [_err(path, "offering must be an object")]

    issues: list[dict[str, str]] = []

    # model ∈ enum (byte-identical to dmpkg + plugin-index).
    model = offering.get("model")
    if not isinstance(model, str) or model not in VALID_OFFERING_MODELS:
        issues.append(
            _err(
                f"{path}.model",
                f"offering.model '{model}' must be one of: "
                + ", ".join(sorted(VALID_OFFERING_MODELS)),
            )
        )

    # price — DISPLAY string (may be empty in pre-publish dormant placeholders).
    price = offering.get("price")
    if price is not None and not isinstance(price, str):
        issues.append(_err(f"{path}.price", "offering.price must be a string"))

    # trial_days — integer >= 0 (bool rejected: `true` ≠ 1).
    trial = offering.get("trial_days")
    if trial is not None and (
        isinstance(trial, bool) or not isinstance(trial, int) or trial < 0
    ):
        issues.append(
            _err(f"{path}.trial_days", f"offering.trial_days must be an int >= 0, got {trial!r}")
        )

    # required_grants — DISPLAY-only array of strings (enforcement is runtime
    # ServiceClient::has_grant + DeskModal /api/entitlements, never this field).
    grants = offering.get("required_grants")
    if grants is not None and (
        not isinstance(grants, list) or not all(isinstance(g, str) and g.strip() for g in grants)
    ):
        issues.append(
            _err(f"{path}.required_grants", "offering.required_grants must be an array of non-empty strings")
        )

    # license_check_endpoint — a publisher MUST NOT declare a license-check
    # authority. Licensing is DeskModal-managed; reject a non-empty value.
    endpoint = offering.get("license_check_endpoint")
    if isinstance(endpoint, str) and endpoint.strip():
        issues.append(
            _err(
                f"{path}.license_check_endpoint",
                "licensing is DeskModal-managed — publishers must not declare a "
                "license_check_endpoint (the runtime always verifies via the DeskModal "
                "backend: /api/licenses/verify-anonymous + /api/entitlements)",
            )
        )

    return issues


# The Ed25519 sign/verify roundtrip is entry-level: every published catalog
# entry (capability OR script) carries a `signature{}` pointer block. The
# catalog schema (schema/catalog-entry.json) makes `algorithm` (const "ed25519")
# + `publisher_key_id` REQUIRED, with `checksums_url` / `signature_url` as
# optional URI pointers to the detached-signature + checksums assets. This gate
# asserts that contract self-contained-ly (not relying on the separate
# index-schema check), so a missing/malformed signature fail-closes (rc≠0).
def validate_signature_presence(
    entry: Any, path: str = "signature"
) -> list[dict[str, str]]:
    """Assert the entry carries a well-formed Ed25519 `signature{}` block."""
    if not isinstance(entry, dict):
        return [_err("", "entry must be an object")]

    sig = entry.get("signature")
    if sig is None:
        return [_err(path, "signature is required (entry-level Ed25519 sign/verify block)")]
    if not isinstance(sig, dict):
        return [_err(path, "signature must be an object")]

    issues: list[dict[str, str]] = []

    # algorithm — required; schema pins it to the literal "ed25519".
    algo = sig.get("algorithm")
    if algo != "ed25519":
        issues.append(
            _err(f"{path}.algorithm", f"algorithm must be 'ed25519', got {algo!r}")
        )

    # publisher_key_id — required; non-empty string (binds entry to a publisher).
    key_id = sig.get("publisher_key_id")
    if not isinstance(key_id, str) or not key_id.strip():
        issues.append(
            _err(f"{path}.publisher_key_id", "publisher_key_id must be a non-empty string")
        )

    # checksums_url / signature_url — optional pointers; when present must be
    # non-empty strings (the schema types them as URI strings).
    for field in ("checksums_url", "signature_url"):
        v = sig.get(field)
        if v is not None and (not isinstance(v, str) or not v.strip()):
            issues.append(_err(f"{path}.{field}", f"{field} must be a non-empty string"))

    return issues


# --------------------------------------------------------------------- #
# Genuine Ed25519 cryptographic sign/verify — the roundtrip this module   #
# docstring promises. `validate_signature_presence` above only checks the #
# SHAPE of the `signature{}` pointer block (algorithm literal + non-empty #
# key_id). The functions below actually verify signature bytes against a   #
# TRUSTED publisher public key over the artifact's checksums, closing the  #
# gap where any tampered/unsigned release passed the gateway as "signed".  #
#                                                                          #
# Trust chain (PUBLISHING.md §"Required release assets"):                  #
#   detached `SIGNATURE` (raw 64-byte Ed25519 sig) --verifies-->           #
#   `checksums.txt` (sha256 of every artifact) --pins--> each artifact.    #
# The DeskModal client re-verifies each artifact's sha256 at install; this #
# gate proves the FIRST link cryptographically. The public key is the      #
# CATALOG-side trust anchor (`publisher_keys` registry, edited only via    #
# the approved publisher-signup PR flow) — NEVER the `publisher.pub`        #
# shipped inside the release, which an attacker controls.                   #
try:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

    _SIGNATURE_TOOL_IMPORT_ERROR: Optional[str] = None
except ImportError as _import_err:  # pragma: no cover - env-dependent
    Ed25519PublicKey = None  # type: ignore[assignment,misc]
    InvalidSignature = Exception  # type: ignore[assignment,misc]
    _SIGNATURE_TOOL_IMPORT_ERROR = str(_import_err) or "cryptography package not importable"

# True when the Ed25519 backend is importable. Callers MUST fail loud (never a
# silent pass) when this is False and a signed package is being verified.
SIGNATURE_TOOL_AVAILABLE = _SIGNATURE_TOOL_IMPORT_ERROR is None

ED25519_PUBLIC_KEY_LEN = 32
ED25519_SIGNATURE_LEN = 64
# 64 hex chars == 32 raw bytes; the canonical registry encoding for a raw
# Ed25519 public key (matches `.signing-key.hex` / CATALOG_PUBKEY hex form).
_ED25519_PUBKEY_HEX = re.compile(r"^[0-9a-fA-F]{64}$")


class SignatureToolUnavailable(RuntimeError):
    """Ed25519 verification requested but the `cryptography` backend is absent.

    Fail-loud per the honest-gate contract: a missing crypto backend must NEVER
    silently pass a package through as "verified". Callers surface this reason
    and drop the entry (or abort the run) rather than emit an unverified entry.
    """


def verify_ed25519_signature_bytes(
    message: bytes, signature: bytes, public_key: bytes
) -> bool:
    """
    Genuine Ed25519 verify: does `signature` prove `message` was signed by the
    holder of the private key matching `public_key`?

    Pure + deterministic. Returns True ONLY for a cryptographically valid
    signature; returns False for a forged/corrupt signature or malformed-length
    inputs. Raises `SignatureToolUnavailable` when the `cryptography` backend is
    missing — never a silent False-that-reads-as-pass, never a silent True.
    """
    if not SIGNATURE_TOOL_AVAILABLE:
        raise SignatureToolUnavailable(
            "Ed25519 verification requires the 'cryptography' package: "
            + str(_SIGNATURE_TOOL_IMPORT_ERROR)
        )
    if not isinstance(message, (bytes, bytearray)):
        return False
    if not isinstance(signature, (bytes, bytearray)) or len(signature) != ED25519_SIGNATURE_LEN:
        return False
    if not isinstance(public_key, (bytes, bytearray)) or len(public_key) != ED25519_PUBLIC_KEY_LEN:
        return False
    try:
        Ed25519PublicKey.from_public_bytes(bytes(public_key)).verify(
            bytes(signature), bytes(message)
        )
        return True
    except InvalidSignature:
        return False
    except ValueError:
        # Backend rejected the key/signature bytes as structurally invalid.
        return False


def resolve_trusted_public_key(
    publisher_keys: Any, key_id: Any
) -> tuple[Optional[bytes], Optional[str]]:
    """
    Resolve the trusted raw Ed25519 public key (32 bytes) bound to `key_id` in
    the catalog `publisher_keys` registry (sources.json / index.json).

    The registry is the TRUST ANCHOR: it is edited only via the approved
    publisher-signup PR flow (PUBLISHING.md Layer 1), so a key that appears here
    is one DeskModal has vouched for. A release's bundled `publisher.pub` is
    NEVER trusted for this decision — an attacker ships their own.

    Returns `(key_bytes, None)` on success or `(None, reason)` when no trusted
    key resolves (fail-closed: an unregistered publisher cannot be verified).
    """
    if not isinstance(key_id, str) or not key_id.strip():
        return None, "entry declares no publisher_key_id"
    if not isinstance(publisher_keys, dict):
        return None, "catalog carries no publisher_keys registry"
    entry = publisher_keys.get(key_id)
    if not isinstance(entry, dict):
        return None, f"no trusted key registered for publisher_key_id '{key_id}'"
    algo = entry.get("algorithm")
    if algo is not None and algo != "ed25519":
        return None, f"publisher_key_id '{key_id}' algorithm '{algo}' is not ed25519"
    hex_key = entry.get("public_key_hex")
    if not isinstance(hex_key, str) or not _ED25519_PUBKEY_HEX.match(hex_key.strip()):
        return None, (
            f"publisher_key_id '{key_id}' has no valid 64-hex-char public_key_hex "
            "in the registry (provision it via the publisher-signup flow)"
        )
    return bytes.fromhex(hex_key.strip()), None


def verify_release_signature(
    *,
    checksums_bytes: Optional[bytes],
    signature_bytes: Optional[bytes],
    publisher_keys: Any,
    key_id: Any,
) -> tuple[bool, str]:
    """
    The load-bearing publish-gate decision: is the release's detached
    `SIGNATURE` a genuine Ed25519 signature over its `checksums.txt`, by the
    trusted key bound to `key_id`?

    Fail-closed — a missing trusted key / checksums / SIGNATURE, a wrong-length
    signature, or a signature that does not verify all return `(False, reason)`.
    Only a cryptographically valid signature returns `(True, reason)`. Propagates
    `SignatureToolUnavailable` (fail-loud) if the crypto backend is absent.

    Returns `(ok, human_reason)` so the caller can log an honest drop reason.
    """
    pubkey, key_reason = resolve_trusted_public_key(publisher_keys, key_id)
    if pubkey is None:
        return False, key_reason or "no trusted publisher key"
    if not checksums_bytes:
        return False, "missing checksums.txt asset (nothing for the signature to cover)"
    if not signature_bytes:
        return False, "missing SIGNATURE asset (release is unsigned)"
    if len(signature_bytes) != ED25519_SIGNATURE_LEN:
        return False, (
            f"SIGNATURE is {len(signature_bytes)} bytes; expected a raw "
            f"{ED25519_SIGNATURE_LEN}-byte Ed25519 signature"
        )
    if verify_ed25519_signature_bytes(bytes(checksums_bytes), bytes(signature_bytes), pubkey):
        return True, f"Ed25519 SIGNATURE verified over checksums.txt by '{key_id}'"
    return False, (
        f"Ed25519 SIGNATURE does not verify over checksums.txt for publisher_key_id "
        f"'{key_id}' (tampered artifact/checksums, wrong key, or corrupt signature)"
    )


def verify_manifest_checksum_binding(
    *,
    manifest_bytes: Optional[bytes],
    expected_sha256: Optional[str],
) -> tuple[bool, str]:
    """
    Transitively bind a fetched manifest (plugin.toml) to the signature-verified
    checksums, so the catalog fields DERIVED from it (capability_tier / offering /
    script_pack) inherit the Ed25519 signature's trust rather than being taken on
    the publisher's word.

    Call this ONLY after `verify_release_signature` returned ok=True: at that point
    the parsed checksums map was produced from the exact `checksums.txt` bytes the
    detached SIGNATURE cryptographically covered, so any entry in that map is
    itself signature-bound. `expected_sha256` is the checksums entry for the
    manifest's path (the caller resolves it against how checksums.txt lists the
    file). A manifest whose sha256 equals `expected_sha256` is therefore covered by
    the release signature; its displayed fields can be trusted.

    Fail-closed (mirrors the [drop] contract in `verify_release_signature`):
      - no manifest bytes         -> (False, ...) — nothing to bind;
      - manifest not in checksums -> (False, coverage-gap) — its bytes are NOT
        covered by the signature, so its tier/license/offering cannot be trusted;
      - sha256 mismatch           -> (False, tampered) — a validly-signed artifact
        set served alongside a manifest carrying false tier/license/offering.
    Only a byte-exact match returns (True, reason). Pure + deterministic; needs no
    crypto backend (the signature itself was already verified upstream).
    """
    if not isinstance(manifest_bytes, (bytes, bytearray)):
        return False, "no fetched manifest bytes to bind to the signature-verified checksums"
    if not isinstance(expected_sha256, str) or not expected_sha256.strip():
        return False, (
            "manifest is not listed in the signature-verified checksums.txt — its "
            "capability_tier/license/offering are not covered by the release signature"
        )
    actual = hashlib.sha256(bytes(manifest_bytes)).hexdigest()
    want = expected_sha256.strip().lower()
    if actual.lower() != want:
        return False, (
            f"manifest sha256 {actual} does not match the signature-verified checksums "
            f"entry {want} (manifest tampered — false capability_tier/license/offering "
            "served alongside a validly-signed artifact set)"
        )
    return True, "manifest bytes match the signature-verified checksums entry"


def validate_capability_tier(
    tier: Any, path: str = "capability_tier", *, required: bool
) -> list[dict[str, str]]:
    """Validate a capability tier. `required` toggles presence enforcement."""
    if tier is None:
        if required:
            return [
                _err(
                    path,
                    "capability_tier is required and must be one of: "
                    + ", ".join(sorted(VALID_CAPABILITY_TIERS)),
                )
            ]
        return []
    if not isinstance(tier, str) or tier not in VALID_CAPABILITY_TIERS:
        return [
            _err(
                path,
                f"capability_tier '{tier}' must be one of: "
                + ", ".join(sorted(VALID_CAPABILITY_TIERS)),
            )
        ]
    return []


def validate_resources(
    resources: Any, path: str = "resources", *, required: bool
) -> list[dict[str, str]]:
    """Validate a `[resources]` footprint block. `required` toggles presence."""
    if resources is None:
        if required:
            return [
                _err(
                    path,
                    "resources footprint is required: declare "
                    + ", ".join(RESOURCE_INT_FIELDS + RESOURCE_FLOAT_FIELDS),
                )
            ]
        return []

    if not isinstance(resources, dict):
        return [_err(path, "resources must be an object")]

    issues: list[dict[str, str]] = []
    for field in RESOURCE_INT_FIELDS:
        v = resources.get(field)
        if v is None:
            issues.append(_err(f"{path}.{field}", f"{field} is required"))
        elif not _is_number(v) or v < 0:
            issues.append(
                _err(f"{path}.{field}", f"{field} must be a number >= 0, got {v!r}")
            )
    for field in RESOURCE_FLOAT_FIELDS:
        v = resources.get(field)
        if v is None:
            issues.append(_err(f"{path}.{field}", f"{field} is required"))
        elif not _is_number(v) or v < 0:
            issues.append(
                _err(f"{path}.{field}", f"{field} must be a number >= 0, got {v!r}")
            )
    return issues


def validate_capability_entry(
    entry: Any, *, require_footprint: bool
) -> list[dict[str, str]]:
    """
    Validate a published catalog entry against the §27 capability contract.

    `require_footprint=True` (publisher/manifest gate) enforces PRESENCE of
    capability_tier + resources. `require_footprint=False` (index gate over
    already-published entries) enforces only VALIDITY of what is declared, plus
    license presence — so legacy entries predating the contract still pass while
    any malformed declaration is rejected.
    """
    if not isinstance(entry, dict):
        return [_err("", "entry must be an object")]

    issues: list[dict[str, str]] = []
    issues.extend(validate_license(entry.get("license")))
    issues.extend(validate_signature_presence(entry))
    issues.extend(
        validate_capability_tier(entry.get("capability_tier"), required=require_footprint)
    )
    issues.extend(
        validate_resources(entry.get("resources"), required=require_footprint)
    )
    # §27.12 offering — selling metadata; validated when present (a free App
    # carries no `offering`). Never required; the catalog key is `offering`.
    issues.extend(validate_offering(entry.get("offering")))
    return issues


def validate_manifest_capability(manifest: Any) -> list[dict[str, str]]:
    """
    Full presence + validity enforcement against a parsed `plugin.toml`.

    This is the publisher pre-publish Verification Gateway: a manifest missing
    `[license] spdx`, `[bundle] tier`, or a complete `[resources]` block is
    rejected (the caller returns rc≠0).
    """
    if not isinstance(manifest, dict):
        return [_err("", "manifest must be an object")]

    issues: list[dict[str, str]] = []

    # [license] spdx (+ advisory notice/terms_url per §27.12).
    license_block = manifest.get("license")
    if not isinstance(license_block, dict):
        issues.append(_err("license", "manifest must declare a [license] table (§27.12)"))
    else:
        issues.extend(validate_license(license_block.get("spdx"), "license.spdx"))
        for advisory in ("notice", "terms_url"):
            v = license_block.get(advisory)
            if v is not None and (not isinstance(v, str) or not v.strip()):
                issues.append(
                    _err(f"license.{advisory}", f"license.{advisory} must be a non-empty string")
                )
        # [license.commercial] OFFERING block — selling metadata; validated when
        # present (DeskModal-managed; a publisher license_check_endpoint here is
        # REJECTED — see validate_offering). Catalog emits it as `offering`.
        issues.extend(
            validate_offering(license_block.get("commercial"), "license.commercial")
        )

    # [bundle] tier — presence required.
    bundle = manifest.get("bundle")
    tier = bundle.get("tier") if isinstance(bundle, dict) else None
    issues.extend(validate_capability_tier(tier, "bundle.tier", required=True))

    # [resources] — full footprint required.
    issues.extend(validate_resources(manifest.get("resources"), required=True))

    return issues


# --------------------------------------------------------------------- #
# L7 — script-pack validators                                            #
# --------------------------------------------------------------------- #
def validate_script_descriptor(
    desc: Any, path: str, *, require_conformance: bool
) -> list[dict[str, str]]:
    """Validate one `script_pack.scripts[]` descriptor (one `.opti`)."""
    if not isinstance(desc, dict):
        return [_err(path, "script descriptor must be an object")]

    issues: list[dict[str, str]] = []

    # path inside the .dmpkg optiscript/ tree
    rel = desc.get("path")
    if not isinstance(rel, str) or not rel.strip() or rel.startswith("/") or ".." in rel:
        issues.append(
            _err(f"{path}.path", "path must be a non-empty relative .opti path (no '..' / leading '/')")
        )

    # kind ∈ enum
    kind = desc.get("kind")
    if not isinstance(kind, str) or kind not in VALID_SCRIPT_KINDS:
        issues.append(
            _err(
                f"{path}.kind",
                f"kind '{kind}' must be one of: " + ", ".join(sorted(VALID_SCRIPT_KINDS)),
            )
        )

    # display_name
    name = desc.get("display_name")
    if not isinstance(name, str) or not (1 <= len(name) <= 60):
        issues.append(_err(f"{path}.display_name", "display_name must be a 1-60 char string"))

    # intents_handled / broadcasts — arrays of non-empty strings
    for field in ("intents_handled", "broadcasts"):
        v = desc.get(field, [])
        if not isinstance(v, list) or not all(isinstance(x, str) and x.strip() for x in v):
            issues.append(
                _err(f"{path}.{field}", f"{field} must be an array of non-empty strings")
            )

    # intents_handled non-empty for intent-bearing kinds
    if isinstance(kind, str) and kind in SCRIPT_KINDS_REQUIRING_INTENTS:
        ih = desc.get("intents_handled")
        if not isinstance(ih, list) or not ih:
            issues.append(
                _err(
                    f"{path}.intents_handled",
                    f"kind '{kind}' must declare at least one handled intent",
                )
            )

    # source_sha256 — 64 hex
    sha = desc.get("source_sha256")
    if not isinstance(sha, str) or not _SHA256_HEX.match(sha):
        issues.append(
            _err(f"{path}.source_sha256", "source_sha256 must be a 64-char hex SHA-256 of the .opti bytes")
        )

    # conformance — enum; publish gate requires `pass`
    conf = desc.get("conformance")
    if not isinstance(conf, str) or conf not in VALID_CONFORMANCE:
        issues.append(
            _err(
                f"{path}.conformance",
                f"conformance '{conf}' must be one of: " + ", ".join(sorted(VALID_CONFORMANCE)),
            )
        )
    elif require_conformance and conf != "pass":
        issues.append(
            _err(
                f"{path}.conformance",
                f"publish gate requires conformance 'pass', got '{conf}' "
                "(run `dmpkg test <.opti>` to numeric-verify before publish)",
            )
        )

    return issues


def validate_script_pack(
    script_pack: Any, path: str = "script_pack", *, require: bool, require_conformance: bool
) -> list[dict[str, str]]:
    """
    Validate a `script_pack` block. `require` toggles presence enforcement
    (publisher gate). `require_conformance` enforces conformance == 'pass'
    on every script (publish gate); the index gate enforces only validity of
    whatever each declared script carries.
    """
    if script_pack is None:
        if require:
            return [_err(path, "script_pack is required for a content_type=script entry")]
        return []

    if not isinstance(script_pack, dict):
        return [_err(path, "script_pack must be an object")]

    issues: list[dict[str, str]] = []

    eng = script_pack.get("engine_min_version")
    if not isinstance(eng, str) or not _SEMVER.match(eng):
        issues.append(
            _err(f"{path}.engine_min_version", "engine_min_version must be a SemVer string")
        )

    scripts = script_pack.get("scripts")
    if not isinstance(scripts, list) or not scripts:
        issues.append(
            _err(f"{path}.scripts", "script_pack must declare at least one [[scripts]] entry")
        )
        return issues

    seen_paths: set[str] = set()
    for i, desc in enumerate(scripts):
        issues.extend(
            validate_script_descriptor(
                desc, f"{path}.scripts[{i}]", require_conformance=require_conformance
            )
        )
        if isinstance(desc, dict) and isinstance(desc.get("path"), str):
            rel = desc["path"]
            if rel in seen_paths:
                issues.append(
                    _err(f"{path}.scripts[{i}].path", f"duplicate script path '{rel}' within pack")
                )
            seen_paths.add(rel)

    return issues


def validate_script_entry(
    entry: Any, *, require: bool, require_conformance: bool
) -> list[dict[str, str]]:
    """
    Validate a published reference-script catalog entry.

    `require=True` (publisher/manifest gate) enforces PRESENCE of the
    `script_pack` block + content_type=script + license; every script must be
    conformance `pass`. `require=False` (index gate over already-published
    entries) enforces only VALIDITY of declared script metadata + license
    presence, so legacy entries predating the contract still pass.
    """
    if not isinstance(entry, dict):
        return [_err("", "entry must be an object")]

    issues: list[dict[str, str]] = []
    issues.extend(validate_license(entry.get("license")))
    issues.extend(validate_signature_presence(entry))

    ct = entry.get("content_type")
    if require and ct != "script":
        issues.append(
            _err("content_type", f"reference-script entries must declare content_type 'script', got {ct!r}")
        )

    issues.extend(
        validate_script_pack(
            entry.get("script_pack"),
            require=require,
            require_conformance=require_conformance,
        )
    )
    return issues


def validate_manifest_script(manifest: Any) -> list[dict[str, str]]:
    """
    Publisher pre-publish gate against a parsed `plugin.toml` carrying a
    reference-script bundle. Enforces a non-empty `script_pack` (or its TOML
    `[[scripts]]` form) with every script conformance `pass`, plus the §27
    license presence. A manifest declaring content_type=script with no scripts
    is REJECTED — the bundle is a contract, not a marketing tag.
    """
    if not isinstance(manifest, dict):
        return [_err("", "manifest must be an object")]

    issues: list[dict[str, str]] = []

    # license may be a [license] table (spdx) or a bare string id.
    license_block = manifest.get("license")
    if isinstance(license_block, dict):
        issues.extend(validate_license(license_block.get("spdx"), "license.spdx"))
    else:
        issues.extend(validate_license(license_block))

    # Resolve the script-pack shape: a manifest may carry it as a top-level
    # `[[scripts]]` array (TOML) normalised into {scripts: [...]}, or an
    # already-shaped `script_pack` table.
    sp = manifest.get("script_pack")
    if sp is None and isinstance(manifest.get("scripts"), list):
        eng = None
        bundle = manifest.get("bundle")
        if isinstance(bundle, dict):
            eng = bundle.get("engine_min_version")
        sp = {
            "engine_min_version": eng or manifest.get("engine_min_version"),
            "scripts": manifest["scripts"],
        }
    issues.extend(
        validate_script_pack(sp, require=True, require_conformance=True)
    )
    return issues
