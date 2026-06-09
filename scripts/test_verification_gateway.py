#!/usr/bin/env python3
"""Unit tests for the §27 Capability Verification Gateway + aggregator emission.

Run: python3 -m unittest discover -s scripts -p 'test_*.py'
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from aggregate import (  # noqa: E402
    capability_metadata,
    offering_metadata,
    script_pack_metadata,
)
from verification_gateway import (  # noqa: E402
    VALID_OFFERING_MODELS,
    validate_capability_entry,
    validate_capability_tier,
    validate_license,
    validate_manifest_capability,
    validate_manifest_script,
    validate_offering,
    validate_resources,
    validate_script_entry,
    validate_script_pack,
    validate_signature_presence,
)

GOOD_RESOURCES = {
    "disk_mb": 80,
    "ram_mb_idle": 200,
    "ram_mb_peak": 400,
    "cpu_pct_steady": 1.5,
}

# A well-formed entry-level Ed25519 signature pointer block (mirrors the catalog
# schema + the shape aggregate.py emits + index.json carries).
GOOD_SIG = {
    "algorithm": "ed25519",
    "publisher_key_id": "1c44bd0e9cf34e36",
    "checksums_url": "plugins/x/0.1.0/darwin-arm64/checksums.txt",
    "signature_url": "plugins/x/0.1.0/darwin-arm64/plugin.toml.sig",
}

_SHA = "a" * 64


def _good_script(**over):
    s = {
        "path": "indicators/rsi.opti",
        "kind": "indicator",
        "display_name": "RSI",
        "intents_handled": ["deskmodal.IndicatorRsi"],
        "broadcasts": ["deskmodal.indicator.rsi"],
        "source_sha256": _SHA,
        "conformance": "pass",
    }
    s.update(over)
    return s


def _good_pack(**over):
    p = {"engine_min_version": "0.1.0", "scripts": [_good_script()]}
    p.update(over)
    return p


class TestLicense(unittest.TestCase):
    def test_nonempty_passes(self):
        self.assertEqual(validate_license("MIT"), [])

    def test_empty_fails(self):
        self.assertTrue(validate_license(""))
        self.assertTrue(validate_license("   "))
        self.assertTrue(validate_license(None))
        self.assertTrue(validate_license(123))


class TestTier(unittest.TestCase):
    def test_valid_lowercase(self):
        for t in ("required", "recommended", "optional"):
            self.assertEqual(validate_capability_tier(t, required=True), [])

    def test_uppercase_rejected(self):
        self.assertTrue(validate_capability_tier("REQUIRED", required=True))

    def test_absent_required_fails_optional_passes(self):
        self.assertTrue(validate_capability_tier(None, required=True))
        self.assertEqual(validate_capability_tier(None, required=False), [])

    def test_unknown_value_fails(self):
        self.assertTrue(validate_capability_tier("core", required=False))


class TestResources(unittest.TestCase):
    def test_complete_passes(self):
        self.assertEqual(validate_resources(GOOD_RESOURCES, required=True), [])

    def test_absent_required_fails_optional_passes(self):
        self.assertTrue(validate_resources(None, required=True))
        self.assertEqual(validate_resources(None, required=False), [])

    def test_missing_field_fails(self):
        partial = dict(GOOD_RESOURCES)
        del partial["ram_mb_peak"]
        self.assertTrue(validate_resources(partial, required=True))

    def test_negative_fails(self):
        bad = dict(GOOD_RESOURCES, disk_mb=-1)
        self.assertTrue(validate_resources(bad, required=False))

    def test_bool_rejected_as_number(self):
        bad = dict(GOOD_RESOURCES, disk_mb=True)
        self.assertTrue(validate_resources(bad, required=False))

    def test_non_object_fails(self):
        self.assertTrue(validate_resources("80mb", required=False))


class TestEntry(unittest.TestCase):
    def test_legacy_entry_passes_lenient(self):
        # license + signature present, no tier/resources → passes index-mode.
        entry = {"license": "Proprietary", "signature": dict(GOOD_SIG)}
        self.assertEqual(
            validate_capability_entry(entry, require_footprint=False), []
        )

    def test_legacy_entry_fails_strict(self):
        entry = {"license": "Proprietary", "signature": dict(GOOD_SIG)}
        self.assertTrue(validate_capability_entry(entry, require_footprint=True))

    def test_full_entry_passes_strict(self):
        entry = {
            "license": "MIT",
            "signature": dict(GOOD_SIG),
            "capability_tier": "optional",
            "resources": GOOD_RESOURCES,
        }
        self.assertEqual(
            validate_capability_entry(entry, require_footprint=True), []
        )

    def test_malformed_tier_fails_even_lenient(self):
        entry = {"license": "MIT", "signature": dict(GOOD_SIG), "capability_tier": "OPTIONAL"}
        self.assertTrue(validate_capability_entry(entry, require_footprint=False))

    def test_missing_signature_fails_even_lenient(self):
        # Self-contained gate: a valid license but no signature fail-closes.
        entry = {"license": "MIT", "capability_tier": "optional", "resources": GOOD_RESOURCES}
        self.assertTrue(validate_capability_entry(entry, require_footprint=False))


class TestManifestGate(unittest.TestCase):
    def _manifest(self, **over):
        base = {
            "license": {"spdx": "MIT", "notice": "(c) 2026", "terms_url": "https://x"},
            "bundle": {"tier": "recommended"},
            "resources": dict(GOOD_RESOURCES),
        }
        base.update(over)
        return base

    def test_complete_manifest_passes(self):
        self.assertEqual(validate_manifest_capability(self._manifest()), [])

    def test_missing_license_block_fails(self):
        m = self._manifest()
        del m["license"]
        self.assertTrue(validate_manifest_capability(m))

    def test_missing_tier_fails(self):
        m = self._manifest(bundle={})
        self.assertTrue(validate_manifest_capability(m))

    def test_missing_resources_fails(self):
        m = self._manifest()
        del m["resources"]
        self.assertTrue(validate_manifest_capability(m))

    def test_bad_spdx_fails(self):
        m = self._manifest(license={"spdx": ""})
        self.assertTrue(validate_manifest_capability(m))


class TestSignaturePresence(unittest.TestCase):
    def test_complete_signature_passes(self):
        self.assertEqual(validate_signature_presence({"signature": dict(GOOD_SIG)}), [])

    def test_minimal_required_only_passes(self):
        # checksums_url / signature_url are optional pointers.
        sig = {"algorithm": "ed25519", "publisher_key_id": "abc123"}
        self.assertEqual(validate_signature_presence({"signature": sig}), [])

    def test_absent_signature_fails(self):
        self.assertTrue(validate_signature_presence({"license": "MIT"}))

    def test_non_dict_signature_fails(self):
        self.assertTrue(validate_signature_presence({"signature": "ed25519"}))
        self.assertTrue(validate_signature_presence({"signature": ["ed25519"]}))

    def test_non_dict_entry_rejected(self):
        self.assertTrue(validate_signature_presence("nope"))

    def test_missing_algorithm_fails(self):
        sig = dict(GOOD_SIG)
        del sig["algorithm"]
        self.assertTrue(validate_signature_presence({"signature": sig}))

    def test_wrong_algorithm_fails(self):
        sig = dict(GOOD_SIG, algorithm="rsa")
        self.assertTrue(validate_signature_presence({"signature": sig}))

    def test_missing_publisher_key_id_fails(self):
        sig = dict(GOOD_SIG)
        del sig["publisher_key_id"]
        self.assertTrue(validate_signature_presence({"signature": sig}))

    def test_empty_publisher_key_id_fails(self):
        sig = dict(GOOD_SIG, publisher_key_id="   ")
        self.assertTrue(validate_signature_presence({"signature": sig}))

    def test_malformed_pointer_url_fails(self):
        sig = dict(GOOD_SIG, checksums_url="")
        self.assertTrue(validate_signature_presence({"signature": sig}))
        sig2 = dict(GOOD_SIG, signature_url=123)
        self.assertTrue(validate_signature_presence({"signature": sig2}))


class TestAggregatorEmission(unittest.TestCase):
    def test_tier_from_manifest_bundle(self):
        tier, res = capability_metadata({"bundle": {"tier": "required"}}, {})
        self.assertEqual(tier, "required")
        self.assertIsNone(res)

    def test_tier_default_optional(self):
        tier, _ = capability_metadata({}, {})
        self.assertEqual(tier, "optional")

    def test_tier_uppercase_normalized(self):
        tier, _ = capability_metadata({"bundle": {"tier": "REQUIRED"}}, {})
        self.assertEqual(tier, "required")

    def test_tier_invalid_falls_to_optional(self):
        tier, _ = capability_metadata({"bundle": {"tier": "core"}}, {})
        self.assertEqual(tier, "optional")

    def test_source_override_wins(self):
        tier, _ = capability_metadata(
            {"bundle": {"tier": "required"}}, {"capability_tier": "optional"}
        )
        self.assertEqual(tier, "optional")

    def test_resources_emitted_when_complete(self):
        _, res = capability_metadata({"resources": dict(GOOD_RESOURCES)}, {})
        self.assertEqual(
            res,
            {
                "disk_mb": 80,
                "ram_mb_idle": 200,
                "ram_mb_peak": 400,
                "cpu_pct_steady": 1.5,
            },
        )

    def test_partial_resources_dropped(self):
        partial = dict(GOOD_RESOURCES)
        del partial["cpu_pct_steady"]
        _, res = capability_metadata({"resources": partial}, {})
        self.assertIsNone(res)

    def test_resources_coerced_types(self):
        _, res = capability_metadata(
            {"resources": {"disk_mb": 80.0, "ram_mb_idle": 200, "ram_mb_peak": 400, "cpu_pct_steady": 2}},
            {},
        )
        self.assertIsInstance(res["disk_mb"], int)
        self.assertIsInstance(res["cpu_pct_steady"], float)

    def test_partial_source_override_merges_over_manifest(self):
        # A partial sources override refines, not replaces, the manifest block.
        _, res = capability_metadata(
            {"resources": dict(GOOD_RESOURCES)}, {"resources": {"disk_mb": 9}}
        )
        self.assertEqual(res["disk_mb"], 9)
        self.assertEqual(res["ram_mb_idle"], 200)  # retained from manifest

    def test_complete_source_override_without_manifest(self):
        _, res = capability_metadata({}, {"resources": dict(GOOD_RESOURCES)})
        self.assertEqual(res["disk_mb"], 80)

    def test_whitespace_tier_normalized_by_aggregator(self):
        # Aggregator is lenient (strips); the strict gate rejects the raw value.
        tier, _ = capability_metadata({"bundle": {"tier": "  Optional  "}}, {})
        self.assertEqual(tier, "optional")
        self.assertTrue(validate_capability_tier("  Optional  ", required=True))


class TestUncoveredBranches(unittest.TestCase):
    def test_resources_cpu_missing_and_negative(self):
        missing = {k: v for k, v in GOOD_RESOURCES.items() if k != "cpu_pct_steady"}
        self.assertTrue(validate_resources(missing, required=True))
        neg = dict(GOOD_RESOURCES, cpu_pct_steady=-0.5)
        self.assertTrue(validate_resources(neg, required=False))

    def test_resources_cpu_zero_is_valid(self):
        ok = dict(GOOD_RESOURCES, cpu_pct_steady=0)
        self.assertEqual(validate_resources(ok, required=True), [])

    def test_entry_non_dict_rejected(self):
        self.assertTrue(validate_capability_entry("not-a-dict", require_footprint=False))

    def test_manifest_non_dict_rejected(self):
        self.assertTrue(validate_manifest_capability("not-a-dict"))

    def test_manifest_advisory_fields_must_be_nonempty_strings(self):
        m = {
            "license": {"spdx": "MIT", "notice": "   "},
            "bundle": {"tier": "optional"},
            "resources": dict(GOOD_RESOURCES),
        }
        self.assertTrue(validate_manifest_capability(m))

    def test_tier_as_list_rejected(self):
        self.assertTrue(validate_capability_tier(["optional"], required=False))


# --------------------------------------------------------------------- #
# L7 — script-pack gateway                                              #
# --------------------------------------------------------------------- #
class TestScriptPack(unittest.TestCase):
    def test_good_pack_passes_both_modes(self):
        self.assertEqual(
            validate_script_pack(_good_pack(), require=True, require_conformance=True), []
        )
        self.assertEqual(
            validate_script_pack(_good_pack(), require=False, require_conformance=False), []
        )

    def test_absent_required_fails_optional_passes(self):
        self.assertTrue(
            validate_script_pack(None, require=True, require_conformance=False)
        )
        self.assertEqual(
            validate_script_pack(None, require=False, require_conformance=False), []
        )

    def test_empty_scripts_fails(self):
        self.assertTrue(
            validate_script_pack(
                _good_pack(scripts=[]), require=False, require_conformance=False
            )
        )

    def test_bad_engine_version_fails(self):
        self.assertTrue(
            validate_script_pack(
                _good_pack(engine_min_version="latest"),
                require=False,
                require_conformance=False,
            )
        )

    def test_bad_kind_fails(self):
        p = _good_pack(scripts=[_good_script(kind="widget")])
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=False))

    def test_bad_sha_fails(self):
        p = _good_pack(scripts=[_good_script(source_sha256="xyz")])
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=False))

    def test_indicator_without_intents_fails(self):
        p = _good_pack(scripts=[_good_script(intents_handled=[])])
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=False))

    def test_drawing_without_intents_passes(self):
        p = _good_pack(scripts=[_good_script(kind="drawing", intents_handled=[])])
        self.assertEqual(
            validate_script_pack(p, require=False, require_conformance=False), []
        )

    def test_bad_conformance_value_fails_even_lenient(self):
        p = _good_pack(scripts=[_good_script(conformance="maybe")])
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=False))

    def test_compile_only_fails_publish_passes_index(self):
        p = _good_pack(scripts=[_good_script(conformance="compile-only")])
        # publish gate requires pass
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=True))
        # index gate accepts a declared-but-unverified verdict
        self.assertEqual(
            validate_script_pack(p, require=False, require_conformance=False), []
        )

    def test_duplicate_path_fails(self):
        p = _good_pack(scripts=[_good_script(), _good_script()])
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=False))

    def test_path_traversal_rejected(self):
        p = _good_pack(scripts=[_good_script(path="../evil.opti")])
        self.assertTrue(validate_script_pack(p, require=False, require_conformance=False))

    def test_non_object_pack_fails(self):
        self.assertTrue(
            validate_script_pack("scripts", require=False, require_conformance=False)
        )


class TestScriptEntry(unittest.TestCase):
    def test_full_entry_passes_strict(self):
        entry = {
            "license": "MIT",
            "signature": dict(GOOD_SIG),
            "content_type": "script",
            "script_pack": _good_pack(),
        }
        self.assertEqual(
            validate_script_entry(entry, require=True, require_conformance=True), []
        )

    def test_wrong_content_type_fails_strict(self):
        entry = {
            "license": "MIT",
            "signature": dict(GOOD_SIG),
            "content_type": "service",
            "script_pack": _good_pack(),
        }
        self.assertTrue(validate_script_entry(entry, require=True, require_conformance=True))

    def test_legacy_non_script_entry_passes_lenient(self):
        # An index-gate sweep over a non-script entry: no script_pack, license +
        # signature ok.
        entry = {"license": "Proprietary", "signature": dict(GOOD_SIG)}
        self.assertEqual(
            validate_script_entry(entry, require=False, require_conformance=False), []
        )

    def test_missing_license_fails(self):
        entry = {
            "content_type": "script",
            "signature": dict(GOOD_SIG),
            "script_pack": _good_pack(),
        }
        self.assertTrue(validate_script_entry(entry, require=True, require_conformance=True))

    def test_missing_signature_fails_even_lenient(self):
        # Self-contained gate: a script entry with no signature fail-closes.
        entry = {"license": "MIT", "content_type": "script", "script_pack": _good_pack()}
        self.assertTrue(validate_script_entry(entry, require=True, require_conformance=True))

    def test_non_dict_entry_rejected(self):
        self.assertTrue(
            validate_script_entry("nope", require=False, require_conformance=False)
        )


class TestManifestScriptGate(unittest.TestCase):
    def test_script_pack_table_passes(self):
        m = {"license": {"spdx": "MIT"}, "script_pack": _good_pack()}
        self.assertEqual(validate_manifest_script(m), [])

    def test_toml_scripts_list_normalized(self):
        # A manifest carrying a top-level [[scripts]] list + bundle engine floor.
        m = {
            "license": "MIT",
            "bundle": {"engine_min_version": "0.1.0"},
            "scripts": [_good_script()],
        }
        self.assertEqual(validate_manifest_script(m), [])

    def test_missing_scripts_fails(self):
        m = {"license": {"spdx": "MIT"}}
        self.assertTrue(validate_manifest_script(m))

    def test_compile_only_blocks_publish(self):
        m = {
            "license": {"spdx": "MIT"},
            "script_pack": _good_pack(
                scripts=[_good_script(conformance="compile-only")]
            ),
        }
        self.assertTrue(validate_manifest_script(m))

    def test_non_dict_manifest_rejected(self):
        self.assertTrue(validate_manifest_script("nope"))


class TestScriptPackAggregatorEmission(unittest.TestCase):
    def test_emits_from_source_override(self):
        sp = script_pack_metadata({}, {"script_pack": _good_pack()})
        self.assertIsNotNone(sp)
        self.assertEqual(sp["scripts"][0]["kind"], "indicator")
        self.assertEqual(sp["scripts"][0]["source_sha256"], _SHA)

    def test_emits_from_manifest_scripts_list(self):
        sp = script_pack_metadata(
            {"bundle": {"engine_min_version": "0.1.0"}, "scripts": [_good_script()]}, {}
        )
        self.assertIsNotNone(sp)
        self.assertEqual(sp["engine_min_version"], "0.1.0")

    def test_source_override_wins_over_manifest(self):
        sp = script_pack_metadata(
            {"script_pack": _good_pack(scripts=[_good_script(display_name="MANIFEST")])},
            {"script_pack": _good_pack(scripts=[_good_script(display_name="SOURCE")])},
        )
        self.assertEqual(sp["scripts"][0]["display_name"], "SOURCE")

    def test_absent_yields_none(self):
        self.assertIsNone(script_pack_metadata({}, {}))

    def test_malformed_script_drops_whole_block(self):
        # A single bad sha drops the block (never zero-filled) — the strict gate
        # would reject it at publish; the aggregator never emits a broken block.
        bad = _good_pack(scripts=[_good_script(source_sha256="zz")])
        self.assertIsNone(script_pack_metadata({}, {"script_pack": bad}))

    def test_bad_kind_drops_block(self):
        bad = _good_pack(scripts=[_good_script(kind="widget")])
        self.assertIsNone(script_pack_metadata({}, {"script_pack": bad}))

    def test_emitted_block_validates_clean(self):
        # End-to-end: what the aggregator emits passes the index gate.
        sp = script_pack_metadata({}, {"script_pack": _good_pack()})
        self.assertEqual(
            validate_script_pack(sp, require=False, require_conformance=False), []
        )

    def test_sha_lowercased_on_emit(self):
        sp = script_pack_metadata(
            {}, {"script_pack": _good_pack(scripts=[_good_script(source_sha256="A" * 64)])}
        )
        self.assertEqual(sp["scripts"][0]["source_sha256"], "a" * 64)


# A well-formed paid `offering` block (selling metadata; no endpoint).
GOOD_OFFERING = {
    "model": "subscription",
    "price": "$29/mo",
    "trial_days": 14,
    "required_grants": ["market-data"],
}


class TestOfferingValidator(unittest.TestCase):
    """validate_offering — DeskModal-managed SELLING metadata; no publisher authority."""

    def test_none_is_free_app(self):
        # A free App carries no offering — no findings.
        self.assertEqual(validate_offering(None), [])

    def test_good_block_passes(self):
        self.assertEqual(validate_offering(GOOD_OFFERING), [])

    def test_all_five_models_pass(self):
        for m in ("subscription", "per-seat", "per-api-call", "one-time", "trial"):
            self.assertEqual(validate_offering({"model": m}), [], m)

    def test_unknown_model_fails(self):
        self.assertTrue(validate_offering({"model": "freemium"}))

    def test_uppercase_model_fails(self):
        # kebab-case lowercase parity with dmpkg + plugin-index.
        self.assertTrue(validate_offering({"model": "Subscription"}))

    def test_non_string_price_fails(self):
        self.assertTrue(validate_offering({"model": "trial", "price": 29}))

    def test_empty_price_allowed_at_boundary(self):
        # Dormant placeholder — manifest may carry empty price; the aggregator
        # drops it before it reaches the catalog.
        self.assertEqual(validate_offering({"model": "trial", "price": ""}), [])

    def test_negative_trial_days_fails(self):
        self.assertTrue(validate_offering({"model": "trial", "trial_days": -1}))

    def test_bool_trial_days_fails(self):
        self.assertTrue(validate_offering({"model": "trial", "trial_days": True}))

    def test_required_grants_must_be_string_array(self):
        self.assertTrue(validate_offering({"model": "trial", "required_grants": [1, 2]}))
        self.assertEqual(
            validate_offering({"model": "trial", "required_grants": ["a", "b"]}), []
        )

    def test_publisher_endpoint_is_rejected(self):
        # THE security correction: a publisher MUST NOT declare a license-check
        # authority. A non-empty license_check_endpoint fail-closes.
        issues = validate_offering(
            {"model": "subscription", "license_check_endpoint": "https://evil.example/check"}
        )
        self.assertTrue(issues)
        self.assertTrue(
            any("DeskModal-managed" in i["message"] for i in issues),
            issues,
        )

    def test_empty_endpoint_ignored(self):
        # An empty/whitespace endpoint is not an authority claim — no finding for it.
        self.assertEqual(
            validate_offering({"model": "subscription", "license_check_endpoint": "  "}), []
        )

    def test_non_object_fails(self):
        self.assertTrue(validate_offering("subscription"))

    def test_wired_into_capability_entry(self):
        # A catalog entry's `offering` is validated by validate_capability_entry.
        entry = {
            "license": "MIT",
            "signature": dict(GOOD_SIG),
            "offering": {
                "model": "subscription",
                "license_check_endpoint": "https://evil.example/check",
            },
        }
        self.assertTrue(validate_capability_entry(entry, require_footprint=False))

    def test_wired_into_manifest_capability(self):
        # A publisher manifest's [license.commercial] endpoint is rejected.
        manifest = {
            "license": {
                "spdx": "MIT",
                "commercial": {
                    "model": "subscription",
                    "license_check_endpoint": "https://publisher.example/lic",
                },
            },
            "bundle": {"tier": "optional"},
            "resources": dict(GOOD_RESOURCES),
        }
        issues = validate_manifest_capability(manifest)
        self.assertTrue(
            any("license.commercial.license_check_endpoint" == i["path"] for i in issues),
            issues,
        )

    def test_clean_manifest_commercial_passes(self):
        manifest = {
            "license": {"spdx": "MIT", "commercial": dict(GOOD_OFFERING)},
            "bundle": {"tier": "optional"},
            "resources": dict(GOOD_RESOURCES),
        }
        self.assertEqual(validate_manifest_capability(manifest), [])


class TestOfferingModelParity(unittest.TestCase):
    """The 5-value model enum is the cross-repo parity contract."""

    def test_enum_is_the_five_canonical_values(self):
        self.assertEqual(
            VALID_OFFERING_MODELS,
            frozenset({"subscription", "per-seat", "per-api-call", "one-time", "trial"}),
        )


class TestOfferingAggregatorEmission(unittest.TestCase):
    """offering_metadata — emit SELLING metadata; drop dormant; never emit endpoint."""

    def test_emits_paid_offering_from_source_override(self):
        off = offering_metadata({}, {"offering": dict(GOOD_OFFERING)})
        self.assertIsNotNone(off)
        self.assertEqual(off["model"], "subscription")
        self.assertEqual(off["price"], "$29/mo")
        self.assertEqual(off["trial_days"], 14)
        self.assertEqual(off["required_grants"], ["market-data"])

    def test_legacy_license_commercial_cfg_key_still_resolves(self):
        # Source override may still use the old `license_commercial` cfg key.
        off = offering_metadata({}, {"license_commercial": dict(GOOD_OFFERING)})
        self.assertIsNotNone(off)
        self.assertEqual(off["model"], "subscription")

    def test_emits_from_manifest_license_commercial(self):
        off = offering_metadata(
            {"license": {"commercial": dict(GOOD_OFFERING)}}, {}
        )
        self.assertIsNotNone(off)
        self.assertEqual(off["model"], "subscription")

    def test_never_emits_license_check_endpoint(self):
        # The publisher endpoint is NEVER propagated into the catalog, even if a
        # manifest carries one alongside a valid price.
        off = offering_metadata(
            {},
            {
                "offering": {
                    "model": "subscription",
                    "price": "$29/mo",
                    "license_check_endpoint": "https://publisher.example/lic",
                }
            },
        )
        self.assertIsNotNone(off)
        self.assertNotIn("license_check_endpoint", off)

    def test_dormant_empty_price_dropped(self):
        # Re-keyed on price: empty price = dormant community-tier; drop the block.
        # A publisher endpoint can NEVER make an offering "LIVE".
        self.assertIsNone(
            offering_metadata(
                {},
                {"offering": {"model": "subscription", "price": "",
                              "license_check_endpoint": "https://publisher.example/lic"}},
            )
        )

    def test_absent_yields_none(self):
        self.assertIsNone(offering_metadata({}, {}))

    def test_bad_model_dropped(self):
        self.assertIsNone(
            offering_metadata({}, {"offering": {"model": "freemium", "price": "$1"}})
        )

    def test_source_override_wins_over_manifest(self):
        off = offering_metadata(
            {"license": {"commercial": {"model": "one-time", "price": "$99"}}},
            {"offering": {"model": "subscription", "price": "$29/mo"}},
        )
        self.assertEqual(off["model"], "subscription")

    def test_emitted_block_validates_clean(self):
        # End-to-end: what the aggregator emits passes the gateway validator.
        off = offering_metadata({}, {"offering": dict(GOOD_OFFERING)})
        self.assertEqual(validate_offering(off), [])


if __name__ == "__main__":
    unittest.main()
