#!/usr/bin/env python3
"""
appmarket aggregator — builds index.json from the declarative
sources.json file by walking each source repo's latest GitHub Release,
pulling down its manifest/checksums/signature, and assembling a
platform-resolved catalog entry.

The output is the single file every DeskModal session fetches on
marketplace open:

  https://raw.githubusercontent.com/Desk-Modal/appmarket/main/index.json

Design invariants (enforced on every run):
  - Every catalog entry MUST have at least one installable platform
    (native tarball or wasm fallback); otherwise dropped with warning.
  - sha256 is pulled from the upstream release's checksums.txt — not
    recomputed locally, because this aggregator is intentionally
    network-light. The DeskModal client re-verifies sha256 at install
    time against the same checksums.txt (which is itself Ed25519
    signed), so trust still flows from signature → checksums → asset.
  - Signature URL pointers are surfaced in the output but signature
    verification happens on the client side, not here. This keeps the
    aggregator stateless and lets clients verify against their own
    trusted-key bundle.
  - Output is written only if content changed (idempotent) — avoids
    spurious commits on scheduled runs.

Run locally against the public API with no auth for smoke tests:

  python3 scripts/aggregate.py --sources sources.json --out index.json

Run in GitHub Actions with the DESKMODAL_REPO_TOKEN secret for
authenticated rate limits and access to private upstream repos during
the pre-public-flip phase:

  GITHUB_TOKEN=$DESKMODAL_REPO_TOKEN python3 scripts/aggregate.py \\
      --sources sources.json --out index.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from verification_gateway import (
    SIGNATURE_TOOL_AVAILABLE,
    verify_release_signature,
)

AGGREGATOR_NAME = "appmarket-aggregator"
AGGREGATOR_VERSION = "1.2.0"

# The catalog-side trust anchor id for DeskModal-first-party releases. The
# matching Ed25519 public key lives in `sources.json publisher_keys`; a source
# may override per-entry via `publisher_key_id`. This is the id the emitted
# `signature{}` block carries AND the id used to resolve the trusted key for the
# genuine Ed25519 SIGNATURE-over-checksums verification (verification_gateway).
DESKMODAL_PRIMARY_KEY_ID = "deskmodal-primary"

# Native platforms DeskModal targets. Order matters: when the aggregator
# walks release assets, it tries each key in turn and picks the first
# match. `wasm` is the portable fallback.
PLATFORMS = ["win32-x64", "darwin-arm64", "darwin-x64", "linux-x64", "wasm"]

# The public distribution repo — every client URL in index.json points
# here, never at an upstream source repo. This is what enables keeping
# build repos private while serving plugins to the public.
APPMARKET_OWNER = "Desk-Modal"
APPMARKET_REPO = "appmarket"


# -------------------------------------------------------------------- #
# HTTP                                                                 #
# -------------------------------------------------------------------- #
class _AuthStrippingRedirectHandler(urllib.request.HTTPRedirectHandler):
    """
    GitHub release asset URLs (`github.com/.../releases/download/...`)
    are 302s to signed S3 URLs on `objects.githubusercontent.com`. If we
    forward our `Authorization` header through the redirect the signed
    URL rejects it with 400. Strip `Authorization` on every redirect.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None:
            # Remove Authorization on the follow-up request
            new_headers = {k: v for k, v in new.header_items() if k.lower() != "authorization"}
            new = urllib.request.Request(
                new.full_url,
                data=new.data,
                headers=new_headers,
                origin_req_host=new.origin_req_host,
                unverifiable=True,
                method=new.get_method(),
            )
        return new


_opener = urllib.request.build_opener(_AuthStrippingRedirectHandler())


def http_get(
    url: str,
    token: Optional[str] = None,
    accept: str = "application/vnd.github+json",
) -> bytes:
    """GET with optional auth. Raises on non-2xx. Strips Authorization on redirect."""
    req = urllib.request.Request(url)
    req.add_header("User-Agent", f"{AGGREGATOR_NAME}/{AGGREGATOR_VERSION}")
    req.add_header("Accept", accept)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with _opener.open(req, timeout=30) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} on {url}: {e.read().decode(errors='replace')[:200]}") from e


def fetch_json(url: str, token: Optional[str] = None) -> Any:
    return json.loads(http_get(url, token).decode("utf-8"))


def fetch_text(url: str, token: Optional[str] = None) -> str:
    # Release asset downloads need the octet-stream accept header
    return http_get(url, token, accept="application/octet-stream").decode("utf-8", errors="replace")


def fetch_binary(url: str, token: Optional[str] = None) -> bytes:
    """Same as fetch_text but returns raw bytes for binary asset mirroring."""
    return http_get(url, token, accept="application/octet-stream")


def http_request(
    url: str,
    method: str,
    token: str,
    body: Optional[bytes] = None,
    content_type: str = "application/json",
    accept: str = "application/vnd.github+json",
) -> bytes:
    """POST/PATCH/DELETE helper for the appmarket write path."""
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("User-Agent", f"{AGGREGATOR_NAME}/{AGGREGATOR_VERSION}")
    req.add_header("Accept", accept)
    req.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        req.add_header("Content-Type", content_type)
    try:
        with _opener.open(req, timeout=60) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} {method} {url}: {e.read().decode(errors='replace')[:500]}") from e


# -------------------------------------------------------------------- #
# Helpers                                                              #
# -------------------------------------------------------------------- #
def parse_checksums(text: str) -> dict[str, str]:
    """Parse a standard `sha256sum` output file into {filename: hash}."""
    out: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            continue
        h, name = parts
        # sha256sum outputs " *name" for binary mode; strip leading char
        if name.startswith("*") or name.startswith(" "):
            name = name[1:]
        out[name.strip()] = h.strip().lower()
    return out


def parse_toml_minimal(text: str) -> dict[str, Any]:
    """
    Tiny TOML parser for plugin.toml manifests. Handles the subset we
    emit from plugin-tools: top-level key=value, [section] headers,
    arrays of strings, and string values. Avoids the `toml` stdlib
    dep so the aggregator can run on any Python 3.9+ without extras.
    """
    result: dict[str, Any] = {}
    current: dict[str, Any] = result
    stack: list[str] = []

    def set_nested(keys: list[str], value: Any) -> None:
        cur = result
        for k in keys[:-1]:
            cur = cur.setdefault(k, {})
        cur[keys[-1]] = value

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        # Section header
        if line.startswith("[") and line.endswith("]"):
            stack = [s.strip() for s in line[1:-1].split(".") if s.strip()]
            continue

        # key = value
        if "=" in line:
            key, _, rhs = line.partition("=")
            key = key.strip()
            rhs = rhs.strip().rstrip(",")
            # Strip inline comments
            if "#" in rhs:
                rhs = rhs[: rhs.index("#")].strip()

            val: Any
            if rhs.startswith('"') and rhs.endswith('"'):
                val = rhs[1:-1]
            elif rhs.startswith("[") and rhs.endswith("]"):
                inner = rhs[1:-1].strip()
                if not inner:
                    val = []
                else:
                    # Only handle string arrays (most common in plugin.toml)
                    items = [i.strip().strip('"') for i in inner.split(",") if i.strip()]
                    val = items
            elif rhs in ("true", "false"):
                val = rhs == "true"
            else:
                try:
                    val = int(rhs)
                except ValueError:
                    try:
                        val = float(rhs)
                    except ValueError:
                        val = rhs

            set_nested(stack + [key], val)
    return result


def infer_platform_from_asset_name(name: str) -> Optional[str]:
    """Match the canonical platform tag inside an asset filename."""
    for p in PLATFORMS:
        # Match the platform token at a word boundary (before .tar.gz or similar)
        if re.search(rf"(^|[-_.]){re.escape(p)}([-_.]|$)", name):
            return p
    return None


def semver_key(tag: str) -> tuple:
    """Sort key for SemVer tags. Pre-releases sort before their base."""
    t = tag.lstrip("v")
    core, *pre = t.split("-", 1)
    parts = core.split(".")
    nums = []
    for p in parts:
        try:
            nums.append(int(p))
        except ValueError:
            nums.append(0)
    # Pad to 3 components
    while len(nums) < 3:
        nums.append(0)
    # Pre-releases sort earlier than release
    is_release = 1 if not pre else 0
    return (*nums, is_release, pre[0] if pre else "")


# -------------------------------------------------------------------- #
# Release fetch                                                        #
# -------------------------------------------------------------------- #
@dataclass
class ReleaseAsset:
    name: str
    url: str           # browser_download_url — what we publish to index.json
    api_url: str       # api.github.com/.../releases/assets/{id} — what we fetch with
    size: int

    def fetch_text(self, token: Optional[str]) -> str:
        """
        Pull asset contents using the API endpoint with `Accept:
        application/octet-stream`. This path works for BOTH public and
        private repos with a token, whereas browser_download_url only
        works for public repos OR when the asset doesn't redirect to
        a signed URL. Using the API endpoint uniformly means the
        aggregator's auth path is identical for every source repo
        regardless of visibility.
        """
        return http_get(self.api_url, token, accept="application/octet-stream").decode(
            "utf-8", errors="replace"
        )


@dataclass
class Release:
    tag: str
    version: str  # tag stripped of leading 'v'
    html_url: str
    published_at: str
    assets: list[ReleaseAsset] = field(default_factory=list)

    def asset_by_name(self, name: str) -> Optional[ReleaseAsset]:
        for a in self.assets:
            if a.name == name:
                return a
        return None


def _release_from_api(data: dict) -> Release:
    assets = [
        ReleaseAsset(
            name=a["name"],
            url=a["browser_download_url"],
            api_url=a["url"],
            size=a["size"],
        )
        for a in data.get("assets", [])
    ]
    tag = data["tag_name"]
    return Release(
        tag=tag,
        version=tag.lstrip("v"),
        html_url=data["html_url"],
        published_at=data["published_at"],
        assets=assets,
    )


def fetch_latest_release(owner: str, repo: str, token: Optional[str]) -> Release:
    data = fetch_json(
        f"https://api.github.com/repos/{owner}/{repo}/releases/latest", token
    )
    return _release_from_api(data)


def fetch_release_by_tag(owner: str, repo: str, tag: str, token: str) -> Optional[Release]:
    """Returns None if the tag doesn't have a release yet."""
    try:
        data = fetch_json(
            f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}", token
        )
        return _release_from_api(data)
    except RuntimeError as e:
        if "HTTP 404" in str(e):
            return None
        raise


# -------------------------------------------------------------------- #
# Mirror: copy private source releases into public appmarket releases  #
# -------------------------------------------------------------------- #
def _mirror_tag(source_repo: str, version: str) -> str:
    """
    The appmarket release tag for a mirrored upstream release.
    Example: 'paper-trading-v0.1.2', 'tradesurface-v1.0.0'.
    Collapses underscores/slashes so the tag stays URL-safe.
    """
    safe = source_repo.replace("/", "-").replace("_", "-").lower()
    return f"{safe}-v{version}"


def create_appmarket_release(
    tag: str, source_release: Release, source_repo: str, token: str
) -> dict:
    """Create a new release on Desk-Modal/appmarket. Returns the API payload."""
    body = json.dumps(
        {
            "tag_name": tag,
            "target_commitish": "main",
            "name": f"{source_repo} {source_release.tag}",
            "body": (
                f"Mirrored from upstream `Desk-Modal/{source_repo}` release "
                f"[`{source_release.tag}`]({source_release.html_url}).\n\n"
                f"This release exists purely as the public distribution surface "
                f"for the DeskModal app market. Source code, issues, and build "
                f"history live in the upstream repo.\n\n"
                f"Mirrored at: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}"
            ),
            "draft": False,
            "prerelease": False,
        }
    ).encode("utf-8")
    resp = http_request(
        f"https://api.github.com/repos/{APPMARKET_OWNER}/{APPMARKET_REPO}/releases",
        method="POST",
        token=token,
        body=body,
    )
    return json.loads(resp)


def upload_asset_to_appmarket(
    release_data: dict, asset_name: str, asset_bytes: bytes, token: str
) -> None:
    """Upload a single asset to an existing appmarket release."""
    # upload_url has the RFC-6570 template suffix `{?name,label}` — strip it.
    upload_url = release_data["upload_url"]
    if "{" in upload_url:
        upload_url = upload_url[: upload_url.index("{")]
    url = f"{upload_url}?name={urllib.parse.quote(asset_name)}"
    # Guess content-type from extension, default to octet-stream
    ctype = "application/gzip" if asset_name.endswith(".gz") else "application/octet-stream"
    if asset_name.endswith(".toml"):
        ctype = "application/toml"
    if asset_name.endswith(".txt"):
        ctype = "text/plain"
    http_request(url, method="POST", token=token, body=asset_bytes, content_type=ctype)


def mirror_source_release(
    source_owner: str,
    source_repo: str,
    source_release: Release,
    token: str,
    dry_run: bool = False,
) -> Release:
    """
    Ensure Desk-Modal/appmarket has a release tagged {source_repo}-v{version}
    containing every asset from the upstream source release. Idempotent:
    - If the target release doesn't exist, creates it.
    - If it exists but is missing assets, uploads the missing ones.
    - If it has everything, no-ops.
    Returns the appmarket-side Release object (URLs now point at appmarket).
    """
    if source_owner != APPMARKET_OWNER:
        print(
            f"  [warn] source owner '{source_owner}' differs from APPMARKET_OWNER '{APPMARKET_OWNER}' — mirroring anyway",
            file=sys.stderr,
        )

    target_tag = _mirror_tag(source_repo, source_release.version)
    print(f"  [mirror] target tag: {APPMARKET_OWNER}/{APPMARKET_REPO}@{target_tag}")

    existing = fetch_release_by_tag(APPMARKET_OWNER, APPMARKET_REPO, target_tag, token)
    existing_names: set[str] = set()
    if existing:
        existing.version = source_release.version
        existing_names = {a.name for a in existing.assets}
        print(f"  [mirror] existing release found, {len(existing_names)} assets present")
    else:
        if dry_run:
            print(f"  [mirror] (dry-run) would create release {target_tag}")
            # Synthetic Release so downstream URL construction still works
            # with the (upstream) source assets while pretending they live
            # on the appmarket side.
            return Release(
                tag=target_tag,
                version=source_release.version,
                html_url=f"https://github.com/{APPMARKET_OWNER}/{APPMARKET_REPO}/releases/tag/{target_tag}",
                published_at=source_release.published_at,
                assets=[
                    ReleaseAsset(
                        name=a.name,
                        url=f"https://github.com/{APPMARKET_OWNER}/{APPMARKET_REPO}/releases/download/{target_tag}/{a.name}",
                        # Pass the SOURCE api_url through so dry-run still
                        # lets the entry builders fetch plugin.toml etc.
                        api_url=a.api_url,
                        size=a.size,
                    )
                    for a in source_release.assets
                ],
            )
        created = create_appmarket_release(target_tag, source_release, source_repo, token)
        existing = _release_from_api(created)
        existing.version = source_release.version
        print(f"  [mirror] created release {target_tag}")

    # Upload any assets that aren't already on the target
    missing = [a for a in source_release.assets if a.name not in existing_names]
    if not missing:
        print(f"  [mirror] all {len(source_release.assets)} assets already mirrored")
    else:
        print(f"  [mirror] uploading {len(missing)} missing assets")
        for a in missing:
            if dry_run:
                print(f"    (dry-run) would upload {a.name} ({a.size} bytes)")
                continue
            print(f"    upload {a.name} ({a.size} bytes)")
            raw = fetch_binary(a.api_url, token)
            # Find the fresh upload_url from the latest existing payload.
            # We need the raw API data, not our Release dataclass, so re-fetch.
            fresh = fetch_json(
                f"https://api.github.com/repos/{APPMARKET_OWNER}/{APPMARKET_REPO}/releases/tags/{target_tag}",
                token,
            )
            upload_asset_to_appmarket(fresh, a.name, raw, token)

    # Re-fetch the final release state so callers get the real appmarket URLs
    if not dry_run:
        final_data = fetch_json(
            f"https://api.github.com/repos/{APPMARKET_OWNER}/{APPMARKET_REPO}/releases/tags/{target_tag}",
            token,
        )
        mirrored = _release_from_api(final_data)
    else:
        mirrored = existing

    # Preserve the ORIGINAL source version — the entry builders use it to
    # substitute `{version}` into asset name templates, and that template
    # must match the upstream asset filenames (we copy them byte-for-byte).
    # `_release_from_api` sets version by stripping a leading 'v' from the
    # tag, which on a tag like `paper-trading-v0.1.2` leaves the full tag
    # intact and breaks downstream template substitution.
    mirrored.version = source_release.version
    return mirrored


# -------------------------------------------------------------------- #
# Entry builders                                                       #
# -------------------------------------------------------------------- #
def build_platforms_map(
    release: Release,
    asset_name_template: str,
    substitutions: dict[str, str],
    checksums: dict[str, str],
) -> dict[str, Optional[dict]]:
    """
    Walk the release assets and resolve each PLATFORMS[] slot to either
    a concrete {url,asset_name,sha256,size_bytes} block or None.
    """
    out: dict[str, Optional[dict]] = {}
    for plat in PLATFORMS:
        subs = dict(substitutions)
        subs["platform"] = plat
        expected = asset_name_template.format(**subs)
        asset = release.asset_by_name(expected)
        if asset is None:
            out[plat] = None
            continue
        out[plat] = {
            "url": asset.url,
            "asset_name": asset.name,
            "sha256": checksums.get(asset.name),
            "size_bytes": asset.size,
        }
    return out


def capability_metadata(
    manifest_data: dict, cfg: dict
) -> tuple[str, Optional[dict]]:
    """
    Resolve the §27 capability tier + §27.11 resource footprint for an entry.

    Tier comes from `plugin.toml [bundle] tier` (or a sources.json
    `capability_tier` override), lowercased, defaulting to "optional" when
    undeclared (the most conservative footprint-budget bucket, matching the
    plugin-index `CapabilityTier::default`). Resources come from `[resources]`
    (or a sources.json `resources` override MERGED over the manifest, so a
    partial override augments rather than destroys the manifest footprint) and
    are emitted ONLY when the merged block is complete + numeric — a
    partial/absent block yields `None` (never a zero-filled placeholder), so
    consumers read absent footprint as "unknown".

    Normalization here is intentionally LENIENT (lowercase/strip tier, coerce
    invalid → "optional", truncate float disk/ram to the plugin-index u32
    shape) — the STRICT publisher gate (`verification_gateway`) rejects the same
    malformed values at publish time; the aggregator never emits a broken entry.
    """
    bundle = manifest_data.get("bundle")
    raw_tier = cfg.get("capability_tier")
    if raw_tier is None and isinstance(bundle, dict):
        raw_tier = bundle.get("tier")
    tier = str(raw_tier).strip().lower() if isinstance(raw_tier, str) else "optional"
    if tier not in ("required", "recommended", "optional"):
        tier = "optional"

    # Merge a sources.json override over the manifest block — a partial override
    # (e.g. just disk_mb) refines the manifest footprint instead of replacing
    # and silently dropping it.
    merged: dict = {}
    if isinstance(manifest_data.get("resources"), dict):
        merged.update(manifest_data["resources"])
    if isinstance(cfg.get("resources"), dict):
        merged.update(cfg["resources"])
    raw_res: Optional[dict] = merged or None
    resources: Optional[dict] = None
    if isinstance(raw_res, dict):
        fields = ("disk_mb", "ram_mb_idle", "ram_mb_peak", "cpu_pct_steady")
        vals = {f: raw_res.get(f) for f in fields}
        if all(
            isinstance(v, (int, float)) and not isinstance(v, bool) and v >= 0
            for v in vals.values()
        ):
            resources = {
                "disk_mb": int(vals["disk_mb"]),
                "ram_mb_idle": int(vals["ram_mb_idle"]),
                "ram_mb_peak": int(vals["ram_mb_peak"]),
                "cpu_pct_steady": float(vals["cpu_pct_steady"]),
            }
    return tier, resources


# Lowercase to match the plugin-index ScriptKind serde repr + the gateway.
_SCRIPT_KINDS = ("indicator", "algo", "screener", "alert", "drawing")
_CONFORMANCE = ("pass", "compile-only", "absent")
_SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


def script_pack_metadata(
    manifest_data: dict, cfg: dict
) -> Optional[dict]:
    """
    Resolve the L7 `script_pack` block for a content_type=script entry.

    Source precedence mirrors `capability_metadata`: a sources.json `script_pack`
    override (cfg) takes precedence over the manifest. Because `parse_toml_minimal`
    does NOT parse `[[scripts]]` array-of-tables, the canonical producer path is a
    `script_pack` table in sources.json (or a manifest `script_pack`/`scripts`
    table when a richer TOML parser populated it). The block is emitted ONLY when
    well-formed (≥1 script, each with a valid kind + 64-hex source_sha256 + known
    conformance) — a partial/absent block yields `None` (never zero-filled), so
    consumers read absent script_pack as "no reference scripts declared". The
    STRICT publisher gate (`verification_gateway.validate_script_pack`) rejects
    the same malformed values at publish time; the aggregator never emits a
    broken block.
    """
    raw = cfg.get("script_pack")
    if not isinstance(raw, dict):
        raw = manifest_data.get("script_pack")
    if not isinstance(raw, dict):
        # A manifest may carry a top-level `scripts` list (TOML [[scripts]]).
        scripts_list = manifest_data.get("scripts")
        if isinstance(scripts_list, list):
            bundle = manifest_data.get("bundle")
            eng = bundle.get("engine_min_version") if isinstance(bundle, dict) else None
            raw = {"engine_min_version": eng, "scripts": scripts_list}
        else:
            return None

    scripts_in = raw.get("scripts")
    if not isinstance(scripts_in, list) or not scripts_in:
        return None

    cleaned: list[dict] = []
    for s in scripts_in:
        if not isinstance(s, dict):
            return None
        kind = s.get("kind")
        sha = s.get("source_sha256")
        rel = s.get("path")
        conf = s.get("conformance")
        if (
            kind not in _SCRIPT_KINDS
            or not isinstance(sha, str)
            or not _SHA256_RE.match(sha)
            or not isinstance(rel, str)
            or not rel.strip()
            or conf not in _CONFORMANCE
        ):
            return None
        intents = s.get("intents_handled") or []
        broadcasts = s.get("broadcasts") or []
        if not (isinstance(intents, list) and isinstance(broadcasts, list)):
            return None
        cleaned.append(
            {
                "path": rel,
                "kind": kind,
                "display_name": str(s.get("display_name") or rel),
                "intents_handled": [str(x) for x in intents],
                "broadcasts": [str(x) for x in broadcasts],
                "source_sha256": sha.lower(),
                "conformance": conf,
            }
        )

    eng = raw.get("engine_min_version")
    return {
        "engine_min_version": str(eng) if isinstance(eng, str) and eng else "0.0.0",
        "scripts": cleaned,
    }


# Lowercase to match the plugin-index `LicenseModel` serde kebab-case repr + the
# plugin.toml `[license.commercial] model` field + the gateway frozenset.
_OFFERING_MODELS = (
    "subscription",
    "per-seat",
    "per-api-call",
    "one-time",
    "trial",
)


def offering_metadata(
    manifest_data: dict, cfg: dict
) -> Optional[dict]:
    """
    Resolve the §27.12 `offering` SELLING-metadata block for a catalog entry.

    DeskModal-MANAGED licensing: the catalog `offering` block is the "price tag"
    DeskModal SELLS at (model/price/trial_days/required_grants) — the
    publisher-LISTED terms, like an App-Store price tag. It is NOT a licensing
    authority. License issuance, verification, and entitlement are ALWAYS the
    DeskModal backend (core-server-api): it ISSUES the Ed25519 token
    (POST /api/licenses), VERIFIES it (POST /api/licenses/verify-anonymous +
    GET /api/licenses/status-list), and SERVES entitlement
    (GET /api/entitlements + /api/entitlements/stream). The client/runtime
    (platform deskmodal-license) checks DeskModal, NEVER a publisher endpoint.

    Therefore the catalog carries NO publisher `license_check_endpoint`: a
    publisher must not declare where its license is checked. The DeskModal
    backend base is client-config (the runtime already knows its core-server-api
    base) — it is never a per-entry catalog field. A publisher-supplied
    `license_check_endpoint` in the manifest is IGNORED here (never emitted) and
    REJECTED at the publisher gate (`verification_gateway.validate_offering` +
    dmpkg `validate_offering`).

    Distinct from the runtime `[license] spdx` string (already carried as catalog
    `license`). Mirrors `plugin.toml [license.commercial]` (model/price/
    trial_days/required_grants). Source precedence mirrors
    `capability_metadata`/`script_pack_metadata`: a sources.json `offering`
    override (cfg) takes precedence over the manifest `[license.commercial]`
    sub-table (`parse_toml_minimal` populates `manifest_data["license"]["commercial"]`
    via its dotted-section stack).

    DORMANT-vs-LIVE is keyed PURELY on `price`: a paid offering has a price. An
    empty-price block is a DORMANT community-tier placeholder (matching the
    discovery-feed comment "Fields stay empty so the marketplace Verification
    Gateway treats this plugin as community-tier") — it is DROPPED so the entry
    carries NO `offering` ("no commercial offering"). A non-empty price is a LIVE
    offering, emitted so "is this a paid App?" is answerable from the catalog
    alone. A publisher endpoint can NEVER make an offering "LIVE". Normalization
    is LENIENT (lowercase/strip model, coerce trial_days→int, drop the block when
    model is not in the enum) — the STRICT publisher gate
    (`verification_gateway.validate_offering`) rejects the same malformed values
    at publish time; the aggregator never emits a broken block.
    """
    raw = cfg.get("offering")
    if not isinstance(raw, dict):
        raw = cfg.get("license_commercial")
    if not isinstance(raw, dict):
        lic = manifest_data.get("license")
        raw = lic.get("commercial") if isinstance(lic, dict) else None
    if not isinstance(raw, dict):
        return None

    raw_model = raw.get("model")
    model = (
        raw_model.strip().lower() if isinstance(raw_model, str) else None
    )
    if model not in _OFFERING_MODELS:
        return None

    price = raw.get("price")
    price = price if isinstance(price, str) else ""

    # DORMANT placeholder — empty price = community-tier, no purchase surface.
    # Drop it so the catalog entry carries no `offering`. A publisher
    # `license_check_endpoint` is deliberately IGNORED — it never participates in
    # liveness (licensing is DeskModal-managed; a publisher does not declare the
    # license-check authority).
    if not price.strip():
        return None

    raw_trial = raw.get("trial_days")
    trial_days = (
        int(raw_trial)
        if isinstance(raw_trial, (int, float)) and not isinstance(raw_trial, bool) and raw_trial >= 0
        else 0
    )

    grants_in = raw.get("required_grants") or []
    grants = (
        [str(g) for g in grants_in] if isinstance(grants_in, list) else []
    )

    # NOTE: NO `license_check_endpoint` is emitted — licensing is DeskModal-
    # managed via core-server-api; the publisher does not control the license
    # check. `required_grants` is DISPLAY-only ("this paid App needs grants X,Y");
    # the enforcement path is runtime ServiceClient::has_grant + DeskModal
    # /api/entitlements, never this catalog field.
    return {
        "model": model,
        "price": price,
        "trial_days": trial_days,
        "required_grants": grants,
    }


def build_entry_single(
    source: dict,
    release: Release,
    token: Optional[str],
    publisher_keys: Optional[dict] = None,
) -> Optional[dict]:
    """Build a catalog entry for a repo that ships ONE plugin per release."""
    owner = source["owner"]
    repo = source["repo"]

    # Pull plugin.toml
    manifest_asset = release.asset_by_name("plugin.toml")
    manifest_data: dict[str, Any] = {}
    manifest_url: Optional[str] = None
    if manifest_asset:
        manifest_url = manifest_asset.url
        try:
            manifest_data = parse_toml_minimal(manifest_asset.fetch_text(token))
        except Exception as e:
            print(f"  [warn] {owner}/{repo}: failed to parse plugin.toml: {e}", file=sys.stderr)

    # Pull checksums.txt — keep the RAW bytes (the SIGNATURE is over the exact
    # bytes; a lossy utf-8 decode would break verification) AND the parsed map.
    checksums: dict[str, str] = {}
    checksums_raw: Optional[bytes] = None
    checksums_asset = release.asset_by_name("checksums.txt")
    if checksums_asset:
        try:
            checksums_raw = fetch_binary(checksums_asset.api_url, token)
            checksums = parse_checksums(checksums_raw.decode("utf-8", errors="replace"))
        except Exception as e:
            print(f"  [warn] {owner}/{repo}: failed to fetch checksums.txt: {e}", file=sys.stderr)

    # Build platforms map
    platforms = build_platforms_map(
        release,
        source["asset_name_template"],
        {"version": release.version},
        checksums,
    )

    if not any(v for v in platforms.values()):
        print(f"  [drop] {owner}/{repo}: no installable platform assets in release {release.tag}", file=sys.stderr)
        return None

    sig_asset = release.asset_by_name("SIGNATURE")

    # Genuine Ed25519 gate: the detached SIGNATURE must cryptographically verify
    # over checksums.txt using the TRUSTED registry key for this publisher.
    # Fail-closed — an unsigned/tampered release, or one from a publisher with no
    # trusted key, is DROPPED (it may never appear as "signed" in the catalog).
    key_id = source.get("publisher_key_id") or DESKMODAL_PRIMARY_KEY_ID
    sig_raw: Optional[bytes] = None
    if sig_asset:
        try:
            sig_raw = fetch_binary(sig_asset.api_url, token)
        except Exception as e:
            print(f"  [warn] {owner}/{repo}: failed to fetch SIGNATURE: {e}", file=sys.stderr)
    ok, reason = verify_release_signature(
        checksums_bytes=checksums_raw,
        signature_bytes=sig_raw,
        publisher_keys=publisher_keys or {},
        key_id=key_id,
    )
    if not ok:
        print(f"  [drop] {owner}/{repo}: signature verification failed — {reason}", file=sys.stderr)
        return None

    # Extract optional manifest fields with safe fallbacks
    min_dm = (
        manifest_data.get("compat", {}).get("min_deskmodal")
        if isinstance(manifest_data.get("compat"), dict)
        else None
    ) or "0.0.0"

    _cap_tier_single, _resources_single = capability_metadata(manifest_data, source)
    _script_pack_single = script_pack_metadata(manifest_data, source)
    _offering_single = offering_metadata(manifest_data, source)

    return {
        "id": source["id"],
        "owner": owner,
        "repo": repo,
        "name": source["display_name"],
        "tagline": source.get("tagline", ""),
        "description": source.get("description") or manifest_data.get("description", ""),
        "content_type": source["content_type"],
        "categories": source.get("categories", []),
        "tags": source.get("tags", []),
        "featured": bool(source.get("featured", False)),
        "publisher": {
            "display_name": owner,
            "verified": True,
            "key_id": key_id,
        },
        "latest_version": release.version,
        "min_deskmodal_version": min_dm,
        "published_at": release.published_at,
        "release_url": release.html_url,
        "changelog_url": f"https://github.com/{owner}/{repo}/releases",
        "icon": {
            "market": f"https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/{source['id']}-market.svg",
            "toolbar": f"https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/{source['id']}-toolbar.svg",
        },
        "icon_url": f"https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/{source['id']}-market.svg",
        "screenshots": source.get("screenshots", []),
        "homepage": f"https://github.com/{owner}/{repo}",
        "license": source.get("license") or "Proprietary",
        "dependencies": source.get("dependencies", []),
        "capabilities": source.get("capabilities", {}),
        "capability_tier": _cap_tier_single,
        **({"resources": _resources_single} if _resources_single else {}),
        **({"script_pack": _script_pack_single} if _script_pack_single else {}),
        **({"offering": _offering_single} if _offering_single else {}),
        "platforms": platforms,
        "manifest": {
            "url": manifest_url,
            "sha256": checksums.get("plugin.toml"),
        },
        "signature": {
            "algorithm": "ed25519",
            "publisher_key_id": key_id,
            "checksums_url": checksums_asset.url if checksums_asset else None,
            "signature_url": sig_asset.url if sig_asset else None,
            "verified": True,
        },
    }


def build_entries_multi(
    source: dict,
    release: Release,
    token: Optional[str],
    publisher_keys: Optional[dict] = None,
) -> list[dict]:
    """
    Build one catalog entry PER declared plugin for a monorepo-style
    release (like tradesurface) where a single release tag carries
    multiple independent plugin bundles distinguished by `{slug}`.
    """
    owner = source["owner"]
    repo = source["repo"]
    entries: list[dict] = []

    for plugin in source["plugins"]:
        slug = plugin["slug"]
        subs = {"version": release.version, "slug": slug}

        # Per-plugin checksums — keep RAW bytes for signature verification plus
        # the parsed map (see build_entry_single for why the raw bytes matter).
        cs_name = source.get("per_plugin_checksums_template", "{slug}-checksums.txt").format(**subs)
        cs_asset = release.asset_by_name(cs_name)
        checksums: dict[str, str] = {}
        checksums_raw: Optional[bytes] = None
        if cs_asset:
            try:
                checksums_raw = fetch_binary(cs_asset.api_url, token)
                checksums = parse_checksums(checksums_raw.decode("utf-8", errors="replace"))
            except Exception as e:
                print(f"  [warn] {owner}/{repo}/{slug}: failed to fetch {cs_name}: {e}", file=sys.stderr)

        # Per-plugin manifest
        mf_name = source.get("per_plugin_manifest_template", "{slug}-plugin.toml").format(**subs)
        mf_asset = release.asset_by_name(mf_name)
        manifest_data: dict[str, Any] = {}
        if mf_asset:
            try:
                manifest_data = parse_toml_minimal(mf_asset.fetch_text(token))
            except Exception as e:
                print(f"  [warn] {owner}/{repo}/{slug}: failed to parse {mf_name}: {e}", file=sys.stderr)

        # Per-plugin signature
        sig_name = source.get("per_plugin_signature_template", "{slug}-SIGNATURE").format(**subs)
        sig_asset = release.asset_by_name(sig_name)

        platforms = build_platforms_map(
            release, source["asset_name_template"], subs, checksums
        )

        if not any(v for v in platforms.values()):
            print(
                f"  [drop] {owner}/{repo}/{slug}: no installable platform assets in {release.tag}",
                file=sys.stderr,
            )
            continue

        # Genuine Ed25519 gate (per-plugin) — fail-closed, same contract as the
        # single-release path: drop any bundle whose SIGNATURE does not verify
        # over its checksums against a trusted registry key.
        key_id = plugin.get("publisher_key_id") or source.get("publisher_key_id") or DESKMODAL_PRIMARY_KEY_ID
        sig_raw: Optional[bytes] = None
        if sig_asset:
            try:
                sig_raw = fetch_binary(sig_asset.api_url, token)
            except Exception as e:
                print(f"  [warn] {owner}/{repo}/{slug}: failed to fetch {sig_name}: {e}", file=sys.stderr)
        ok, reason = verify_release_signature(
            checksums_bytes=checksums_raw,
            signature_bytes=sig_raw,
            publisher_keys=publisher_keys or {},
            key_id=key_id,
        )
        if not ok:
            print(
                f"  [drop] {owner}/{repo}/{slug}: signature verification failed — {reason}",
                file=sys.stderr,
            )
            continue

        min_dm = (
            manifest_data.get("compat", {}).get("min_deskmodal")
            if isinstance(manifest_data.get("compat"), dict)
            else None
        ) or "0.0.0"

        _cap_tier_multi, _resources_multi = capability_metadata(manifest_data, plugin)
        _script_pack_multi = script_pack_metadata(manifest_data, plugin)
        _offering_multi = offering_metadata(manifest_data, plugin)

        entries.append({
            "id": plugin["id"],
            "owner": owner,
            "repo": repo,
            "name": plugin["display_name"],
            "tagline": plugin.get("tagline", ""),
            "description": plugin.get("description") or manifest_data.get("description", ""),
            "content_type": plugin.get("content_type", source.get("content_type", "app")),
            "categories": plugin.get("categories", []),
            "tags": plugin.get("tags", []),
            "featured": bool(plugin.get("featured", False)),
            "publisher": {
                "display_name": owner,
                "verified": True,
                "key_id": key_id,
            },
            "latest_version": release.version,
            "min_deskmodal_version": min_dm,
            "published_at": release.published_at,
            "release_url": release.html_url,
            "changelog_url": f"https://github.com/{owner}/{repo}/releases",
            "icon": {
                "market": f"https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/{plugin['id']}-market.svg",
                "toolbar": f"https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/{plugin['id']}-toolbar.svg",
            },
            "icon_url": f"https://raw.githubusercontent.com/Desk-Modal/appmarket/main/icons/{plugin['id']}-market.svg",
            "screenshots": plugin.get("screenshots", []),
            "homepage": f"https://github.com/{owner}/{repo}",
            "license": plugin.get("license") or "Proprietary",
            "dependencies": plugin.get("dependencies", []),
            "capabilities": plugin.get("capabilities", {}),
            "capability_tier": _cap_tier_multi,
            **({"resources": _resources_multi} if _resources_multi else {}),
            **({"script_pack": _script_pack_multi} if _script_pack_multi else {}),
            **({"offering": _offering_multi} if _offering_multi else {}),
            "platforms": platforms,
            "manifest": {
                "url": mf_asset.url if mf_asset else None,
                "sha256": checksums.get(mf_name),
            },
            "signature": {
                "algorithm": "ed25519",
                "publisher_key_id": key_id,
                "checksums_url": cs_asset.url if cs_asset else None,
                "signature_url": sig_asset.url if sig_asset else None,
                "verified": True,
            },
        })

    return entries


# -------------------------------------------------------------------- #
# Orchestration                                                        #
# -------------------------------------------------------------------- #
def aggregate(sources_path: str, out_path: str, token: Optional[str], mirror: bool = True, dry_run: bool = False) -> bool:
    """
    Walks sources.json, mirrors each source repo's latest release into
    the public appmarket repo (when `mirror=True`), then assembles a
    catalog entry whose platform URLs point at the APPMARKET-side
    mirrored assets.

    Returns True if the output file changed (or was newly created),
    False otherwise. Callers use this to decide whether to commit.
    """
    # Fail loud (never a silent pass) if the Ed25519 backend is missing: a
    # catalog whose entries cannot be cryptographically verified must not be
    # built. Honest gate — registered ⇔ runnable.
    if not SIGNATURE_TOOL_AVAILABLE:
        print(
            "[FATAL] Ed25519 signature verification is unavailable — the 'cryptography' "
            "package is not importable. Refusing to build a catalog whose release "
            "signatures cannot be verified. Install it: pip install cryptography",
            file=sys.stderr,
        )
        raise SystemExit(3)

    with open(sources_path, "r", encoding="utf-8") as f:
        sources_doc = json.load(f)

    # Catalog-side trust anchor: publisher_key_id -> {algorithm, public_key_hex}.
    # The genuine SIGNATURE-over-checksums verify resolves keys from here.
    publisher_keys: dict = sources_doc.get("publisher_keys", {})
    if not isinstance(publisher_keys, dict):
        publisher_keys = {}

    catalog: list[dict] = []
    seen_ids: set[str] = set()

    for src in sources_doc.get("sources", []):
        owner = src["owner"]
        repo = src["repo"]
        mode = src.get("mode", "single_release")

        print(f"[{mode}] {owner}/{repo}")
        try:
            source_release = fetch_latest_release(owner, repo, token)
        except Exception as e:
            print(f"  [skip] no latest release: {e}", file=sys.stderr)
            continue

        print(f"  source tag={source_release.tag} assets={len(source_release.assets)}")

        # Mirror step — copy every asset from the source release to an
        # appmarket release tagged {repo}-v{version}. After this, every
        # URL we publish to index.json points at the public appmarket
        # repo, and the DeskModal client never needs to read the
        # private source repos.
        if mirror:
            if not token:
                print(
                    "  [skip] mirror requested but no GITHUB_TOKEN — set a token with repo:write on appmarket",
                    file=sys.stderr,
                )
                continue
            try:
                release = mirror_source_release(owner, repo, source_release, token, dry_run=dry_run)
            except Exception as e:
                print(f"  [skip] mirror failed: {e}", file=sys.stderr)
                continue
        else:
            release = source_release

        if mode == "single_release":
            entry = build_entry_single(src, release, token, publisher_keys)
            entries = [entry] if entry else []
        elif mode == "multi_plugin_release":
            entries = build_entries_multi(src, release, token, publisher_keys)
        else:
            print(f"  [skip] unknown mode '{mode}'", file=sys.stderr)
            continue

        for e in entries:
            if e["id"] in seen_ids:
                print(f"  [skip] duplicate id '{e['id']}' — already in catalog", file=sys.stderr)
                continue
            seen_ids.add(e["id"])
            catalog.append(e)
            platforms_available = [p for p, v in e["platforms"].items() if v]
            print(f"  [+] {e['id']} @ {e['latest_version']} platforms={platforms_available}")

    # Bundled packs — content shipped inside the DeskModal binary itself
    # (e.g. the default brand theme under platform/branding/themes/). They
    # have no GitHub release; the platform resolves them locally via
    # install_root()/branding/. Surface them in the catalog so they appear
    # in the marketplace UI as "installed / bundled" first-class entries.
    for bp in sources_doc.get("bundled_packs", []):
        if bp["id"] in seen_ids:
            print(f"  [skip] duplicate id '{bp['id']}' — already in catalog", file=sys.stderr)
            continue
        seen_ids.add(bp["id"])
        publisher = bp.get("publisher", {})
        _cap_tier_bp, _resources_bp = capability_metadata({}, bp)
        catalog.append({
            "id": bp["id"],
            "owner": publisher.get("id", "deskmodal"),
            "repo": "deskmodal",
            "name": bp.get("name", bp["id"]),
            "tagline": bp.get("tagline", ""),
            "description": bp.get("description", ""),
            "content_type": bp.get("type", "theme"),
            "categories": bp.get("categories", []),
            "tags": bp.get("tags", []),
            "featured": bool(bp.get("featured", False)),
            "bundled": True,
            "publisher": {
                "display_name": publisher.get("name", "DeskModal Technologies"),
                "verified": bool(publisher.get("verified", True)),
                "key_id": "deskmodal-primary",
            },
            "latest_version": bp.get("version", "1.0.0"),
            "min_deskmodal_version": bp.get("min_deskmodal_version", "0.0.0"),
            "published_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "license": bp.get("license") or "Proprietary",
            "capability_tier": _cap_tier_bp,
            **({"resources": _resources_bp} if _resources_bp else {}),
            "platforms": {"win-x64": True, "darwin-arm64": True, "linux-x64": True},
        })
        print(f"  [+] {bp['id']} @ {bp.get('version', '1.0.0')} (bundled)")

    # Sort for stable output
    catalog.sort(key=lambda e: e["id"])

    doc = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator": {
            "name": AGGREGATOR_NAME,
            "version": AGGREGATOR_VERSION,
            "source_commit": os.environ.get("GITHUB_SHA", "unknown")[:7],
        },
        "publisher_keys": sources_doc.get("publisher_keys", {}),
        "categories": sources_doc.get("categories", []),
        "catalog": catalog,
    }

    new_bytes = json.dumps(doc, indent=2, sort_keys=False).encode("utf-8") + b"\n"

    existing_bytes = b""
    if os.path.exists(out_path):
        with open(out_path, "rb") as f:
            existing_bytes = f.read()

    # Compare byte-for-byte EXCLUDING generated_at (otherwise every run
    # would look like a change). We do this by parsing and zeroing it.
    def normalize(b: bytes) -> bytes:
        try:
            obj = json.loads(b)
            obj["generated_at"] = ""
            if "generator" in obj and "source_commit" in obj.get("generator", {}):
                obj["generator"]["source_commit"] = ""
            return json.dumps(obj, indent=2, sort_keys=False).encode("utf-8") + b"\n"
        except Exception:
            return b

    changed = normalize(new_bytes) != normalize(existing_bytes)

    # Safety guard: refuse to overwrite a non-empty catalog with an
    # empty one. An empty result almost always means the aggregator
    # couldn't reach its sources (missing token, network hiccup, 404s
    # on private repos) — NOT that every plugin was intentionally
    # delisted. Emitting zero entries under those conditions would
    # nuke the public catalog for every DeskModal session on the next
    # CDN refresh. Fail loud instead.
    existing_catalog_count = 0
    try:
        existing_catalog_count = len(json.loads(existing_bytes).get("catalog", []))
    except Exception:
        pass
    if len(catalog) == 0 and existing_catalog_count > 0:
        print(
            f"\n[REFUSE] aggregator produced 0 entries but the existing index.json "
            f"has {existing_catalog_count}. Not overwriting.",
            file=sys.stderr,
        )
        print(
            "[REFUSE] this almost always means the aggregator lost access to its "
            "source repos (missing GITHUB_TOKEN, expired PAT, or source repos "
            "flipped private). Fix the access and rerun.",
            file=sys.stderr,
        )
        raise SystemExit(2)

    if changed:
        with open(out_path, "wb") as f:
            f.write(new_bytes)
        print(f"\n[write] {out_path} ({len(catalog)} entries)")
    else:
        print(f"\n[noop] {out_path} unchanged ({len(catalog)} entries)")

    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate appmarket index.json from sources.json")
    parser.add_argument("--sources", default="sources.json")
    parser.add_argument("--out", default="index.json")
    parser.add_argument(
        "--no-mirror",
        action="store_true",
        help="Skip the mirror step and build URLs directly from upstream source releases "
        "(useful only for debugging — the resulting index.json will 404 for any private upstream).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't create appmarket releases or upload assets — just print what would happen "
        "and synthesize the appmarket-side URLs in the output.",
    )
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("[info] running without GITHUB_TOKEN — using anonymous API (60 req/hr)", file=sys.stderr)

    changed = aggregate(
        args.sources,
        args.out,
        token,
        mirror=not args.no_mirror,
        dry_run=args.dry_run,
    )

    # Exit 0 whether changed or not; CI workflow uses git status to decide commit.
    return 0


if __name__ == "__main__":
    sys.exit(main())
