#!/usr/bin/env python3
"""W5 — single P0 key-routing owner and Esc ladder."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OWNER = ROOT / "Lumina" / "Views" / "P0" / "P0KeyRoutingModifier.swift"
LEGACY = ROOT / "Lumina" / "Views" / "Workspace" / "CommandHandlingModifier.swift"
LADDER = ROOT / "Lumina" / "Views" / "P0" / "P0EscLadder.swift"
P0_VIEWS = ROOT / "Lumina" / "Views" / "P0"


class KeyRoutingTests(unittest.TestCase):
    def test_single_owner_header_claim(self) -> None:
        text = OWNER.read_text(encoding="utf-8")
        self.assertIn("Sole owner of P0 live-path", text)

    def test_legacy_owner_not_p0_live_path(self) -> None:
        text = LEGACY.read_text(encoding="utf-8")
        self.assertIn("not on the P0 live path", text)
        self.assertNotIn("Sole owner of workspace", text)

    def test_p0_views_have_no_on_key_press(self) -> None:
        hits: list[str] = []
        for path in sorted(P0_VIEWS.rglob("*.swift")):
            if path.name in {"P0KeyRoutingModifier.swift"}:
                continue
            if ".onKeyPress" in path.read_text(encoding="utf-8"):
                hits.append(str(path.relative_to(ROOT)))
        self.assertEqual(hits, [], f"onKeyPress remains outside owner: {hits}")

    def test_owner_installs_and_removes_monitors(self) -> None:
        text = OWNER.read_text(encoding="utf-8")
        self.assertIn("addLocalMonitorForEvents", text)
        self.assertIn("removeMonitor", text)
        self.assertRegex(text, r"func attach\(")
        self.assertRegex(text, r"func detach\(")

    def test_decision_keys_swallow_repeat(self) -> None:
        text = OWNER.read_text(encoding="utf-8")
        for key in ('lower == "p"', 'lower == "x"'):
            idx = text.index(key)
            window = text[idx : idx + 120]
            self.assertIn("isARepeat", window, f"{key} must swallow autorepeat")

    def test_esc_ladder_single_file(self) -> None:
        text = LADDER.read_text(encoding="utf-8")
        self.assertIn("enum P0EscLadder", text)
        self.assertIn("static func handle", text)

    def test_root_applies_modifier(self) -> None:
        root = (ROOT / "Lumina" / "Views" / "P0" / "P0RootView.swift").read_text(encoding="utf-8")
        self.assertIn(".p0KeyRouting(session:", root)


if __name__ == "__main__":
    unittest.main()
