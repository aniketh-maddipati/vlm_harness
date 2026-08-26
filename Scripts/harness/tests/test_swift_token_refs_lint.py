#!/usr/bin/env python3
"""Unit tests for swift_token_refs lint."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "Scripts" / "harness"
sys.path.insert(0, str(HARNESS / "lint"))

import swift_token_refs as lint  # noqa: E402


class SwiftTokenRefsLintTests(unittest.TestCase):
    def test_parse_motion_members(self) -> None:
        text = (ROOT / "DesignTokens" / "HiFiTokens.generated.swift").read_text(
            encoding="utf-8"
        )
        members = lint.parse_token_members(text)
        self.assertIn("Motion", members)
        self.assertIn("placeReturnMs", members["Motion"])
        self.assertIn("springReducedMotionOvershoot", members["Motion"])

    def test_live_lumina_spring_refs_resolve(self) -> None:
        spring = (ROOT / "Lumina" / "Design" / "LuminaSpring.swift").read_text(
            encoding="utf-8"
        )
        for member in lint.REQUIRED_MOTION_MEMBERS:
            self.assertIn(f"HiFiTokens.Motion.{member}", spring)

    def test_missing_member_detected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            generated = tmp / "HiFiTokens.generated.swift"
            generated.write_text(
                "enum HiFiTokens {\n    enum Motion {\n        static let travelMs: Int = 180\n    }\n}\n",
                encoding="utf-8",
            )
            swift = tmp / "Sample.swift"
            swift.write_text(
                "let x = HiFiTokens.Motion.placeReturnMs\n", encoding="utf-8"
            )
            members = lint.parse_token_members(generated.read_text(encoding="utf-8"))
            refs = [("Sample.swift", 1, "Motion", "placeReturnMs")]
            self.assertNotIn("placeReturnMs", members["Motion"])
            for _, _, enum_name, member in refs:
                self.assertNotIn(member, members[enum_name])

    def test_main_ok_on_repo(self) -> None:
        self.assertEqual(lint.main(), 0)

    def test_main_fails_when_generated_missing(self) -> None:
        with mock.patch.object(lint, "GENERATED", Path("/nonexistent/HiFiTokens.generated.swift")):
            self.assertEqual(lint.main(), 1)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
