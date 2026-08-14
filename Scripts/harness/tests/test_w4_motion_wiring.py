#!/usr/bin/env python3
"""W4 — live-path motion reads sealed tokens; legacy literals registered."""
from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GENERATED = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"
TOKENS_HASH = ROOT / "artifacts" / "harness" / "tokens.hash"
LUMINA_TOKENS = ROOT / "Lumina" / "Design" / "LuminaTokens.swift"
LEGACY = ROOT / "artifacts" / "harness" / "motion_legacy_allowlist.txt"


class MotionWiringTests(unittest.TestCase):
    def test_tokens_hash_matches_generated_header(self) -> None:
        header = GENERATED.read_text(encoding="utf-8")
        import re

        m = re.search(r"tokens-hash: ([0-9a-f]+)", header)
        self.assertIsNotNone(m)
        stored = TOKENS_HASH.read_text(encoding="utf-8")
        self.assertIn(m.group(1), stored)

    def test_live_motion_tokens_sealed(self) -> None:
        text = LUMINA_TOKENS.read_text(encoding="utf-8")
        for token in (
            "HiFiTokens.Motion.photoFocusMs",
            "HiFiTokens.Motion.routeTransitionMs",
            "HiFiTokens.Motion.travelMs",
        ):
            self.assertIn(token, text)
        self.assertNotIn("durationMs: 280", text)
        self.assertNotIn("durationMs: 240", text)

    def test_p0_uses_lumina_spring_animation_helpers(self) -> None:
        p0_dir = ROOT / "Lumina" / "Views" / "P0"
        p0 = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(p0_dir.glob("*.swift"))
        )
        self.assertIn("LuminaSpringAnimation.transform", p0)
        self.assertIn("HiFiTokens.Motion.photoFocusMs", p0)
        self.assertIn("HiFiTokens.Motion.routeTransitionMs", p0)
        self.assertNotIn("durationMs: 280", p0)
        self.assertNotIn("durationMs: 240", p0)

    def test_legacy_debt_registered(self) -> None:
        self.assertTrue(LEGACY.is_file())
        body = LEGACY.read_text(encoding="utf-8")
        self.assertIn("ProjectViewModel.swift 400", body)

    def test_lumina_spring_reads_f07_seal_tokens(self) -> None:
        spring = (ROOT / "Lumina" / "Design" / "LuminaSpring.swift").read_text(
            encoding="utf-8"
        )
        for token in (
            "HiFiTokens.Motion.placeReturnMs",
            "HiFiTokens.Motion.springTrajectorySampleRateHz",
            "HiFiTokens.Motion.springMaxOvershoot",
            "HiFiTokens.Motion.springReducedMotionOvershoot",
        ):
            self.assertIn(token, spring)

    def test_swift_token_refs_lint(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/harness/lint/swift_token_refs.py")],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr or proc.stdout)

    def test_spring_physics_f07(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/harness/tests/test_f07_spring_physics.py")],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr or proc.stdout)


if __name__ == "__main__":
    unittest.main()
