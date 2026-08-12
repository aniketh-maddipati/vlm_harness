#!/usr/bin/env python3
"""Unit tests for build-for-testing cache keying (F04.1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HARNESS))

import build_cache  # noqa: E402


class BuildCacheTests(unittest.TestCase):
    def test_cache_key_format(self):
        key = build_cache.cache_key("a" * 64, "b" * 64)
        self.assertRegex(key, r"^[0-9a-f]{12}-[0-9a-f]{12}$")

    def test_source_and_tokens_hashes_are_hex(self):
        source = build_cache.compute_source_hash()
        tokens = build_cache.compute_tokens_hash()
        self.assertEqual(len(source), 64)
        self.assertEqual(len(tokens), 64)
        int(source, 16)
        int(tokens, 16)

    def test_cache_miss_without_products(self):
        derived = build_cache.derived_data_path("deadbeef" * 8, "cafebabe" * 8)
        self.assertFalse(build_cache.cache_hit(derived))

    def test_derived_path_under_artifacts(self):
        path = build_cache.derived_data_path()
        self.assertIn("artifacts/harness/build-cache", path.as_posix())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
