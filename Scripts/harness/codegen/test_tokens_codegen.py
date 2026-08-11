#!/usr/bin/env python3
"""Unit tests for tokens codegen (FAST lane)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tokens_codegen import (
    check_fresh,
    generate_swift,
    load_tokens,
    section_to_enum,
    snake_to_camel,
    tokens_hash,
    write_outputs,
)

ROOT = Path(__file__).resolve().parents[3]


class TokensCodegenTests(unittest.TestCase):
    def test_snake_to_camel(self):
        self.assertEqual(snake_to_camel("halo_width"), "haloWidth")
        self.assertEqual(snake_to_camel("warm_in_crossfade"), "warmInCrossfade")

    def test_type_section_avoids_swift_keyword(self):
        self.assertEqual(section_to_enum("type"), "Typography")
        self.assertEqual(section_to_enum("ring"), "Ring")

    def test_repo_tokens_generate_and_check(self):
        data, raw = load_tokens(ROOT / "design" / "tokens.yaml")
        digest = tokens_hash(raw)
        swift = generate_swift(data, digest)
        self.assertIn("enum HiFiTokens", swift)
        self.assertIn("tokens-hash:", swift)
        self.assertIn("enum Typography", swift)
        self.assertNotIn("enum Type {", swift)
        self.assertIn("static let haloWidth", swift)
        self.assertIn("warmInCrossfadeMs: Int = 120", swift)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "HiFiTokens.generated.swift"
            hash_out = Path(tmp) / "tokens.hash"
            write_outputs(data, raw, out, hash_out)
            self.assertEqual(check_fresh(data, raw, out), 0)
            self.assertTrue(hash_out.is_file())

    def test_checked_in_generated_file_is_fresh(self):
        data, raw = load_tokens(ROOT / "design" / "tokens.yaml")
        out = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"
        self.assertEqual(check_fresh(data, raw, out), 0)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
