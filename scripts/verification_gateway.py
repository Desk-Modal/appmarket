#!/usr/bin/env python3
"""
Capability Verification Gateway — §27.12 / §27.11 presence + validity checks.

The §27 capability contract requires every published capability to declare:
  - `[license]` (spdx, + notice + terms_url) — §27.12
  - `[bundle] tier` ∈ {required, recommended, optional} — §27
  - `[resources]` footprint (disk_mb, ram_mb_idle, ram_mb_peak, cpu_pct_steady) — §27.11

This module is the pure, dependency-free validation core shared by:
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

import re
from typing import Any

# Lowercase to match plugin.toml `[bundle] tier` + plugin-index serde repr.
VALID_CAPABILITY_TIERS = frozenset({"required", "recommended", "optional"})

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
    issues.extend(
        validate_capability_tier(entry.get("capability_tier"), required=require_footprint)
    )
    issues.extend(
        validate_resources(entry.get("resources"), required=require_footprint)
    )
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
