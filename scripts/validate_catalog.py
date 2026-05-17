#!/usr/bin/env python3
"""
appmarket catalog validator — schema-checks index.json entries by
category. Wired into the marketplace publish pipeline as the
content-side counterpart to Ed25519 signature verification.

Today's scope:
  - indicator-pack — F133-W13 third-party indicator-bundle plugins.
  - (others added in subsequent waves as the schema grows; the
    --category flag selects which schema rules to apply.)

The validator runs against EITHER:

  1. An entire `index.json` (default) — iterates the `catalog[]`
     array and applies the per-category schema to matching entries.

  2. A single TOML manifest via `--manifest <path>` — useful for the
     publisher's local CI (`dmpkg release --validate`) before push.

Exit codes:
  0   all entries with the requested category pass
  1   one or more entries failed
  2   invalid arguments / IO error

Usage:
  python3 scripts/validate_catalog.py --category indicator-pack
  python3 scripts/validate_catalog.py --category indicator-pack --manifest path/to/plugin.toml
  python3 scripts/validate_catalog.py --index index.json --category indicator-pack
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Optional

# ----------------------------------------------------------------------
# Indicator-pack schema (mirrors schema/indicator-pack.md)
# ----------------------------------------------------------------------

INDICATOR_PACK_CATEGORY = "indicator-pack"

# Closed indicator-category set. Adding a value requires coordinated edits
# in plugins/tradesurface/indicator-registry, schema/indicator-pack.md, and
# this constant.
INDICATOR_CATEGORIES = frozenset(
    {
        "trend",
        "momentum",
        "volatility",
        "volume",
        "cycle",
        "pattern",
        "breadth",
        "statistical",
        "custom",
    }
)

INDICATOR_ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z0-9-]+)*$")
SPARKLINE_BYTE_LEN = 256  # 64 little-endian f32 values
HEX_PATTERN = re.compile(r"^[0-9a-f]+$")


def _err(path: str, msg: str) -> dict[str, str]:
    return {"path": path, "severity": "error", "message": msg}


def _warn(path: str, msg: str) -> dict[str, str]:
    return {"path": path, "severity": "warning", "message": msg}


def validate_indicator_entry(entry: Any, idx: int) -> list[dict[str, str]]:
    """Validate one `[[indicators]]` entry. Returns issues (empty = pass)."""
    issues: list[dict[str, str]] = []
    p = f"indicators[{idx}]"

    if not isinstance(entry, dict):
        return [_err(p, "indicator entry must be an object")]

    # id
    raw_id = entry.get("id")
    if not isinstance(raw_id, str) or not raw_id:
        issues.append(_err(f"{p}.id", "indicator id must be a non-empty string"))
    elif not INDICATOR_ID_PATTERN.match(raw_id):
        issues.append(
            _err(
                f"{p}.id",
                f"indicator id '{raw_id}' must match [a-z][a-z0-9-]*(\\.[a-z0-9-]+)*",
            )
        )

    # display_name
    name = entry.get("display_name")
    if not isinstance(name, str) or not (1 <= len(name) <= 40):
        issues.append(
            _err(f"{p}.display_name", "display_name must be a 1-40 char string")
        )

    # category
    cat = entry.get("category")
    if not isinstance(cat, str) or cat not in INDICATOR_CATEGORIES:
        issues.append(
            _err(
                f"{p}.category",
                f"category must be one of: {', '.join(sorted(INDICATOR_CATEGORIES))}",
            )
        )

    # description
    desc = entry.get("description")
    if not isinstance(desc, str) or not (1 <= len(desc) <= 280):
        issues.append(
            _err(f"{p}.description", "description must be a 1-280 char string")
        )

    # inputs / outputs
    for field in ("inputs", "outputs"):
        v = entry.get(field)
        if not isinstance(v, list) or not all(isinstance(x, str) and x for x in v):
            issues.append(
                _err(f"{p}.{field}", f"{field} must be a non-empty array of strings")
            )

    # preview.sparkline (optional)
    preview = entry.get("preview")
    if preview is not None:
        if not isinstance(preview, dict):
            issues.append(_err(f"{p}.preview", "preview must be an object"))
        else:
            spark = preview.get("sparkline")
            if spark is not None:
                if not isinstance(spark, str) or not HEX_PATTERN.match(spark.lower()):
                    issues.append(
                        _err(
                            f"{p}.preview.sparkline",
                            "sparkline must be a lowercase hex string",
                        )
                    )
                elif len(spark) != SPARKLINE_BYTE_LEN * 2:
                    issues.append(
                        _err(
                            f"{p}.preview.sparkline",
                            f"sparkline must encode exactly {SPARKLINE_BYTE_LEN} bytes "
                            f"({SPARKLINE_BYTE_LEN * 2} hex chars), got {len(spark)}",
                        )
                    )

    return issues


def validate_indicator_pack(entry: Any) -> list[dict[str, str]]:
    """
    Validate that `entry` is a well-formed indicator-pack catalog entry
    or plugin.toml fragment. The caller supplies either:

      - a catalog entry from index.json (top-level shape: {id, categories,
        indicators, ...}), or
      - a parsed plugin.toml dict (top-level shape: {plugin: {...},
        services: [...], indicators: [...], ...}).
    """
    issues: list[dict[str, str]] = []

    if not isinstance(entry, dict):
        return [_err("", "entry must be an object")]

    # Resolve manifest-vs-catalog shape
    plugin_block = entry.get("plugin") if isinstance(entry.get("plugin"), dict) else None
    if plugin_block is not None:
        # plugin.toml shape
        categories = plugin_block.get("categories", [])
        plugin_type = plugin_block.get("type")
    else:
        # catalog entry shape
        categories = entry.get("categories", [])
        plugin_type = entry.get("content_type")

    if not isinstance(categories, list) or INDICATOR_PACK_CATEGORY not in categories:
        issues.append(
            _err(
                "categories",
                f"indicator-pack entries must declare '{INDICATOR_PACK_CATEGORY}' in categories",
            )
        )

    # An indicator-pack ships as a service plugin (its cdylib runtime).
    if plugin_type not in ("service", None):
        issues.append(
            _err(
                "plugin.type" if plugin_block is not None else "content_type",
                "indicator-pack plugins must declare type 'service' "
                "(category is a contract, not a marketing tag)",
            )
        )

    # [[indicators]]
    indicators = entry.get("indicators")
    if not isinstance(indicators, list) or not indicators:
        issues.append(
            _err(
                "indicators",
                "indicator-pack entries must declare at least one [[indicators]] entry",
            )
        )
    else:
        seen_ids: set[str] = set()
        for i, ind in enumerate(indicators):
            issues.extend(validate_indicator_entry(ind, i))
            if isinstance(ind, dict) and isinstance(ind.get("id"), str):
                ind_id = ind["id"]
                if ind_id in seen_ids:
                    issues.append(
                        _err(
                            f"indicators[{i}].id",
                            f"duplicate indicator id '{ind_id}' within pack",
                        )
                    )
                seen_ids.add(ind_id)

    # [[services]] — must exist (the cdylib runtime entry).
    services = entry.get("services")
    if plugin_block is not None:
        if not isinstance(services, list) or not services:
            issues.append(
                _err(
                    "services",
                    "indicator-pack manifests must declare at least one [[services]] entry "
                    "(the cdylib runtime)",
                )
            )

    return issues


# ----------------------------------------------------------------------
# TOML reader — reuse aggregate.py's minimal parser to stay dep-light
# ----------------------------------------------------------------------
def _read_toml(path: str) -> dict[str, Any]:
    """
    Parse plugin.toml using the first available TOML library, preferring
    stdlib over third-party. Hard-fails if none is available so the
    operator surfaces the dependency rather than silently mis-parsing.

    The aggregator's `parse_toml_minimal` is intentionally NOT used here
    — it does not handle [[array-of-tables]], which the indicator-pack
    schema relies on for [[indicators]] / [[services]].

    Library precedence:
      1. tomllib (Python 3.11+ stdlib)
      2. tomli   (back-port; tomllib API)
      3. toml    (older third-party with read-only API)
    """
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8")

    try:
        import tomllib  # type: ignore[import-not-found]

        return tomllib.loads(text)
    except ImportError:
        pass

    try:
        import tomli  # type: ignore[import-not-found]

        return tomli.loads(text)
    except ImportError:
        pass

    try:
        import toml as _toml  # type: ignore[import-not-found]

        return _toml.loads(text)
    except ImportError as e:
        raise RuntimeError(
            "no TOML parser available — install Python 3.11+, `tomli`, or `toml`"
        ) from e


# ----------------------------------------------------------------------
# Driver
# ----------------------------------------------------------------------
def _format_issues(label: str, issues: list[dict[str, str]]) -> str:
    if not issues:
        return f"  {label}: OK"
    lines = [f"  {label}: {len(issues)} issue(s)"]
    for i in issues:
        sev = i["severity"].upper()
        lines.append(f"    [{sev}] {i['path']}: {i['message']}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Schema-check appmarket catalog entries by category."
    )
    parser.add_argument(
        "--category",
        required=True,
        choices=[INDICATOR_PACK_CATEGORY],
        help="Category schema to apply.",
    )
    parser.add_argument(
        "--index",
        default="index.json",
        help="Path to the catalog index (default: index.json relative to cwd).",
    )
    parser.add_argument(
        "--manifest",
        default=None,
        help="Validate a single plugin.toml instead of the whole index.",
    )
    args = parser.parse_args()

    # Manifest mode
    if args.manifest is not None:
        if not os.path.exists(args.manifest):
            print(f"manifest not found: {args.manifest}", file=sys.stderr)
            return 2
        try:
            parsed = _read_toml(args.manifest)
        except (OSError, ValueError, UnicodeDecodeError) as e:
            print(f"failed to parse {args.manifest}: {e}", file=sys.stderr)
            return 2
        issues = validate_indicator_pack(parsed)
        label = parsed.get("plugin", {}).get("id", args.manifest)
        print(f"validate_catalog --category {args.category}")
        print(_format_issues(label, issues))
        return 0 if not issues else 1

    # Index mode
    if not os.path.exists(args.index):
        # An empty/missing index isn't a hard fault when the category
        # has zero entries yet — the validator simply reports "no entries
        # matched". This lets a brand-new category (like indicator-pack
        # on W13) pass before any plugin has shipped.
        print(
            f"index not found at {args.index}; nothing to validate for "
            f"category '{args.category}'",
            file=sys.stderr,
        )
        return 0

    with open(args.index, "rb") as f:
        try:
            doc = json.loads(f.read().decode("utf-8"))
        except json.JSONDecodeError as e:
            print(f"invalid JSON in {args.index}: {e}", file=sys.stderr)
            return 2

    catalog = doc.get("catalog")
    if not isinstance(catalog, list):
        print(f"{args.index} missing required 'catalog' array", file=sys.stderr)
        return 2

    matched: list[dict[str, Any]] = [
        e
        for e in catalog
        if isinstance(e, dict)
        and isinstance(e.get("categories"), list)
        and args.category in e["categories"]
    ]

    print(f"validate_catalog --category {args.category} ({len(matched)} entries)")
    failed = 0
    for entry in matched:
        issues = validate_indicator_pack(entry)
        print(_format_issues(entry.get("id", "<unknown>"), issues))
        if issues:
            failed += 1

    if failed:
        print(f"\nFAIL: {failed} entry/entries failed validation", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
