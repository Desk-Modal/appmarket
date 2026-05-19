#!/usr/bin/env python3
"""
appmarket brand-catalog aggregator — walks every `marketplace/appmarket/
brands/<id>/<version>/` directory, parses `brand.toml` + `manifest.json`,
and regenerates `marketplace/plugin-index/index/brands.json` so the
marketplace UI / sdk-brand can discover first-party + community brands.

F152 W12 — replaces the hand-maintained brands.json with a generator
that cross-checks signed `.dmbrand` bundle SHA-256 against on-disk
state. Output is byte-identical given byte-identical inputs (entries
sorted by id; explicit schema_version; canonical ISO timestamp via
--generated-at).

Distribution invariants:
  - NO publishing to npmjs.org / crates.io / external registries
    (per quality.md §18.4.1 — internal-only).
  - Signature URLs reference paths inside the appmarket repo;
    consumers re-verify against `marketplace/plugin-index/index/
    trusted-publishers.json` before install.
  - Hard-fails on:
      - missing brand.toml / manifest.json
      - id mismatch between brand.toml and manifest.json
      - missing signed bundle when --require-signed is passed
      - missing detached `.dmbrand.sig` when --require-signed is passed

Usage:
  # Regenerate brands.json from filesystem walk + cross-check on-disk state.
  python3 marketplace/appmarket/scripts/build_appmarket_catalog.py

  # Lint-mode: ensure the brands.json on disk matches what we'd emit.
  python3 marketplace/appmarket/scripts/build_appmarket_catalog.py --check

  # Hard-require signed bundles for every brand.
  python3 marketplace/appmarket/scripts/build_appmarket_catalog.py --require-signed

Exit codes:
  0  success
  1  validation / drift failure
  2  argument / IO error
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import tomllib  # py3.11+
except ImportError:  # pragma: no cover — py3.10
    import tomli as tomllib  # type: ignore

SCHEMA_VERSION = 1
GENERATOR_NAME = "F152-W12-brand-catalog"
GENERATOR_VERSION = "1.1.0"
SPEC_REF = "specs/152-branding-single-capability-sota/spec.md#§19.5.4"


def repo_root() -> Path:
    """Resolve the workspace root: walk up until we see marketplace/appmarket/."""
    cur = Path(__file__).resolve().parent
    while cur != cur.parent:
        if (cur / "marketplace" / "appmarket").is_dir():
            return cur
        cur = cur.parent
    # Fall back: assume the script lives at <root>/marketplace/appmarket/scripts/.
    return Path(__file__).resolve().parents[3]


def sha256_hex(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_brand_toml(path: Path) -> dict:
    with path.open("rb") as f:
        data = tomllib.load(f)
    brand = data.get("brand")
    if not isinstance(brand, dict):
        raise ValueError(f"{path}: missing [brand] table")
    for key in ("id", "version", "publisher_tier"):
        if key not in brand:
            raise ValueError(f"{path}: [brand] missing required key `{key}`")
    return data


def parse_manifest_json(path: Path) -> dict:
    with path.open("rb") as f:
        return json.load(f)


def collect_brand_entry(
    brand_dir: Path,
    repo: Path,
    *,
    require_signed: bool,
    generated_at: str,
) -> dict:
    """Build one catalog entry for a single `brands/<id>/<ver>/` directory."""
    brand_toml_path = brand_dir / "brand.toml"
    manifest_path = brand_dir / "manifest.json"
    if not brand_toml_path.is_file():
        raise ValueError(f"{brand_dir}: missing brand.toml")
    if not manifest_path.is_file():
        raise ValueError(f"{brand_dir}: missing manifest.json")

    brand_data = parse_brand_toml(brand_toml_path)
    manifest_data = parse_manifest_json(manifest_path)

    brand_id = brand_data["brand"]["id"]
    brand_version = brand_data["brand"]["version"]
    publisher_tier = brand_data["brand"]["publisher_tier"]

    # Identity cross-check (mirrors HIGH-12 in the Rust sign/verify path).
    manifest_id = (manifest_data.get("meta") or {}).get("id")
    if manifest_id != brand_id:
        raise ValueError(
            f"{brand_dir}: id mismatch — brand.toml=`{brand_id}`,"
            f" manifest.json /meta/id=`{manifest_id}`"
        )

    # The dir layout enforces <brands_root>/<id>/<version>/ — assert.
    if brand_dir.parent.name != brand_id or brand_dir.name != brand_version:
        raise ValueError(
            f"{brand_dir}: filesystem layout doesn't match brand.toml identity"
            f" (expected brands/{brand_id}/{brand_version}/)"
        )

    bundle_name = f"{brand_id}-{brand_version}.dmbrand"
    bundle_path = brand_dir / bundle_name
    sig_path = brand_dir / f"{bundle_name}.sig"
    pub_path = brand_dir / "publisher.pub"

    signed_section: dict = {
        "algorithm": "ed25519",
        "publisher_key_url": f"brands/{brand_id}/{brand_version}/publisher.pub",
        "signature_url": f"brands/{brand_id}/{brand_version}/{bundle_name}.sig",
    }

    if bundle_path.is_file():
        signed_section["bundle_sha256"] = sha256_hex(bundle_path)
        signed_section["bundle_bytes"] = bundle_path.stat().st_size
    elif require_signed:
        raise ValueError(
            f"{brand_dir}: --require-signed set but bundle missing at {bundle_path}"
        )
    if sig_path.is_file():
        signed_section["signature_sha256"] = sha256_hex(sig_path)
    elif require_signed:
        raise ValueError(
            f"{brand_dir}: --require-signed set but .dmbrand.sig missing at {sig_path}"
        )
    if pub_path.is_file():
        signed_section["publisher_key_sha256"] = sha256_hex(pub_path)

    brand_section = brand_data["brand"]
    preview_section = brand_section.get("preview") or {}
    swatch = preview_section.get("swatch") or []

    entry = {
        "id": brand_id,
        "name": brand_section.get("name", brand_id),
        "version": brand_version,
        "description": brand_section.get("description", ""),
        "tier": publisher_tier,
        "license": brand_section.get("license", ""),
        "default_mode": brand_section.get("default_mode", "auto"),
        "publisher": {
            "display_name": brand_section.get("author", "DeskModal"),
            "verified": publisher_tier in ("verified", "certified"),
            "key_id": "deskmodal-root",
        },
        "compatibility": {
            "deskmodal_min_version": (brand_section.get("compatibility") or {}).get(
                "deskmodal_min_version", "1.0.0"
            ),
            "schema_version": (brand_section.get("compatibility") or {}).get(
                "schema_version", SCHEMA_VERSION
            ),
        },
        "preview": {
            "swatch": list(swatch),
            "screenshot_url": (
                f"brands/{brand_id}/{brand_version}/{preview_section['screenshot']}"
                if preview_section.get("screenshot")
                else None
            ),
        },
        "manifest_url": f"brands/{brand_id}/{brand_version}/manifest.json",
        "brand_toml_url": f"brands/{brand_id}/{brand_version}/brand.toml",
        "bundle_url": f"brands/{brand_id}/{brand_version}/{bundle_name}",
        "signature": signed_section,
    }
    # Drop screenshot_url when not declared (keeps shape consistent).
    if entry["preview"]["screenshot_url"] is None:
        entry["preview"].pop("screenshot_url")
    return entry


def collect_catalog(
    brands_root: Path,
    repo: Path,
    *,
    require_signed: bool,
    generated_at: str,
) -> dict:
    """Walk brands_root and build the full catalog."""
    if not brands_root.is_dir():
        raise FileNotFoundError(f"brands root not found: {brands_root}")

    entries: list[dict] = []
    for id_dir in sorted(brands_root.iterdir()):
        if not id_dir.is_dir():
            continue
        if "." not in id_dir.name:
            # Not a reverse-DNS id (e.g. README.md, scratch dirs) — skip.
            continue
        for ver_dir in sorted(id_dir.iterdir()):
            if not ver_dir.is_dir():
                continue
            if not (ver_dir / "brand.toml").is_file():
                continue
            entries.append(
                collect_brand_entry(
                    ver_dir,
                    repo,
                    require_signed=require_signed,
                    generated_at=generated_at,
                )
            )
    # Sort by id then version for deterministic output.
    entries.sort(key=lambda e: (e["id"], e["version"]))
    return {
        "generated_at": generated_at,
        "generator": {
            "name": GENERATOR_NAME,
            "version": GENERATOR_VERSION,
            "spec": SPEC_REF,
        },
        "schema_version": SCHEMA_VERSION,
        "brands": entries,
    }


def write_catalog(catalog: dict, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(catalog, indent=2, sort_keys=False, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def check_catalog(catalog: dict, out_path: Path) -> tuple[bool, str]:
    if not out_path.is_file():
        return False, f"missing: {out_path}"
    current = json.loads(out_path.read_text())
    # Compare without the generated_at timestamp (timestamp would always drift).
    a = dict(catalog)
    b = dict(current)
    a.pop("generated_at", None)
    b.pop("generated_at", None)
    if a == b:
        return True, "catalog matches on-disk brands.json"
    return False, (
        "catalog drift: regenerate via "
        "`python3 marketplace/appmarket/scripts/build_appmarket_catalog.py`"
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="F152 W12 — appmarket brand-catalog aggregator"
    )
    parser.add_argument(
        "--brands-root",
        type=Path,
        default=None,
        help="Override brands root (default: <repo>/marketplace/appmarket/brands)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Override output path (default: <repo>/marketplace/plugin-index/index/brands.json)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Lint-mode: assert on-disk brands.json matches generator output.",
    )
    parser.add_argument(
        "--require-signed",
        action="store_true",
        help="Hard-fail if any brand directory lacks a signed .dmbrand bundle.",
    )
    parser.add_argument(
        "--generated-at",
        default=None,
        help=(
            "Override generated_at ISO-8601 timestamp (default: current UTC). "
            "Set to a fixed value for byte-identical reruns."
        ),
    )
    args = parser.parse_args(argv)

    repo = repo_root()
    brands_root = args.brands_root or (repo / "marketplace" / "appmarket" / "brands")
    out_path = args.out or (
        repo / "marketplace" / "plugin-index" / "index" / "brands.json"
    )
    generated_at = args.generated_at or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    try:
        catalog = collect_catalog(
            brands_root,
            repo,
            require_signed=args.require_signed,
            generated_at=generated_at,
        )
    except (FileNotFoundError, ValueError) as e:
        print(f"build_appmarket_catalog: {e}", file=sys.stderr)
        return 2

    if args.check:
        ok, msg = check_catalog(catalog, out_path)
        print(msg)
        return 0 if ok else 1

    write_catalog(catalog, out_path)
    n = len(catalog["brands"])
    print(f"wrote {out_path} ({n} brand{'s' if n != 1 else ''})")
    for entry in catalog["brands"]:
        sig = entry.get("signature", {})
        signed = "signed" if "bundle_sha256" in sig else "unsigned"
        print(f"  - {entry['id']}@{entry['version']} ({entry['tier']}; {signed})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
