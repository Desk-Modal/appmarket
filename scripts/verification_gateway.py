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

from typing import Any

# Lowercase to match plugin.toml `[bundle] tier` + plugin-index serde repr.
VALID_CAPABILITY_TIERS = frozenset({"required", "recommended", "optional"})

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
