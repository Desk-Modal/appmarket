#!/usr/bin/env python3
"""Unit tests for the §27 Capability Verification Gateway + aggregator emission.

Run: python3 -m unittest discover -s scripts -p 'test_*.py'
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from aggregate import capability_metadata  # noqa: E402
from verification_gateway import (  # noqa: E402
    validate_capability_entry,
    validate_capability_tier,
    validate_license,
    validate_manifest_capability,
    validate_resources,
)

GOOD_RESOURCES = {
    "disk_mb": 80,
    "ram_mb_idle": 200,
    "ram_mb_peak": 400,
    "cpu_pct_steady": 1.5,
}


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
        # license present, no tier/resources → passes index-mode (lenient).
        entry = {"license": "Proprietary"}
        self.assertEqual(
            validate_capability_entry(entry, require_footprint=False), []
        )

    def test_legacy_entry_fails_strict(self):
        entry = {"license": "Proprietary"}
        self.assertTrue(validate_capability_entry(entry, require_footprint=True))

    def test_full_entry_passes_strict(self):
        entry = {
            "license": "MIT",
            "capability_tier": "optional",
            "resources": GOOD_RESOURCES,
        }
        self.assertEqual(
            validate_capability_entry(entry, require_footprint=True), []
        )

    def test_malformed_tier_fails_even_lenient(self):
        entry = {"license": "MIT", "capability_tier": "OPTIONAL"}
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


if __name__ == "__main__":
    unittest.main()
