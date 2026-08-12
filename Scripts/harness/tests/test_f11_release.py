#!/usr/bin/env python3
"""Unit tests for F11.4–F11.7 release integrity gates."""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RELEASE = ROOT / "Scripts" / "harness" / "release"
sys.path.insert(0, str(RELEASE))


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, RELEASE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


a7 = _load("f11_a7", "f11_a7_expiry.py")
licensing = _load("f11_no_lic", "f11_no_licensing.py")
read_manifest = _load("f11_read", "f11_read_manifest.py")


class A7ExpiryTests(unittest.TestCase):
    def test_wave_build_passes_without_beta_diagnostics(self) -> None:
        manifest = {"marketingVersion": "0.1.0", "betaDiagnostics": None}
        ok, errors = a7.check_manifest(manifest)
        self.assertTrue(ok, errors)

    def test_fails_at_1_0_with_beta_diagnostics(self) -> None:
        manifest = {
            "marketingVersion": "1.0",
            "betaDiagnostics": {
                "kind": "testflight_crash_reporting",
                "path": "Lumina/Core/BetaDiagnosticsSocket.swift",
                "expiresAtMarketingVersion": "1.0",
            },
        }
        ok, errors = a7.check_manifest(manifest)
        self.assertFalse(ok)
        self.assertTrue(any("1.0" in e for e in errors))


class ReadManifestTests(unittest.TestCase):
    def test_validate_required_fields(self) -> None:
        ok_manifest = {
            "gitSha": "abc",
            "tokensHash": "def",
            "fixtureManifestVersion": "1.0",
            "contractVersion": "6.2",
            "buildDate": "2026-08-12T00:00:00Z",
            "marketingVersion": "0.1.0",
        }
        self.assertEqual(read_manifest.validate_manifest(ok_manifest), [])


class NoLicensingTests(unittest.TestCase):
    def test_tokens_beta_licensing_none(self) -> None:
        self.assertTrue(licensing.beta_licensing_none())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
