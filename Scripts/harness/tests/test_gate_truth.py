#!/usr/bin/env python3
"""Unit tests for W1 gate-truth lint gates."""
from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts" / "harness" / "lint"))

from magic_number_literals import (  # noqa: E402
    compile_literal_pattern,
    extract_forbidden_literals,
    index_literal_skipped,
    literal_in_line,
)


class MagicNumberLiteralTests(unittest.TestCase):
    def test_derives_layout_tokens(self) -> None:
        literals = extract_forbidden_literals()
        self.assertIn("1280", literals)
        self.assertIn("800", literals)
        self.assertIn("252", literals)

    def test_excludes_zero_and_one(self) -> None:
        literals = extract_forbidden_literals()
        self.assertNotIn("0", literals)
        self.assertNotIn("1", literals)

    def test_excludes_small_indices(self) -> None:
        literals = extract_forbidden_literals()
        for n in range(2, 10):
            self.assertNotIn(str(n), literals)

    def test_no_bare_dot_prefix_false_positive(self) -> None:
        self.assertFalse(literal_in_line("0.1", "opacity(0.12)"))

    def test_index_subscript_skipped(self) -> None:
        self.assertTrue(index_literal_skipped("items[3]", "3"))

    def test_combined_matcher_preserves_boundaries_and_longest_form(self) -> None:
        pattern = compile_literal_pattern(["12", "12.5", "0.1"])
        self.assertEqual(
            [match.group(0) for match in pattern.finditer("12.5, 12, 0.12, 0.1")],
            ["12.5", "12", "0.1"],
        )


class OrphanSymbolGateTests(unittest.TestCase):
    def test_gate_passes_with_register(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/harness/lint/orphan_symbols.py")],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("orphan_symbols.py: OK", proc.stdout)

    def test_expected_orphans_registered(self) -> None:
        reg = (ROOT / "artifacts/harness/orphan_register.txt").read_text(encoding="utf-8")
        for needle in (
            "Lumina/Core/CullGrammarMachine.swift CullGrammarMachine",
            "Lumina/Design/LuminaSpring.swift LuminaSpringRetarget",
            "Lumina/Core/BetaDiagnosticsSocket.swift BetaDiagnosticsSocket",
            "Lumina/Views/Components/RecoveryFactsChip.swift RecoveryFactsChip",
        ):
            self.assertIn(needle, reg)

    def test_decision_dock_deleted_not_in_register(self) -> None:
        dock = ROOT / "Lumina/Views/Components/DecisionDock.swift"
        self.assertFalse(dock.is_file(), "W8 deleted DecisionDock — file must be absent")
        reg = (ROOT / "artifacts/harness/orphan_register.txt").read_text(encoding="utf-8")
        self.assertNotIn("DecisionDock.swift DecisionDock", reg)

    def test_unreferenced_deadweight_deleted(self) -> None:
        gone = [
            "Lumina/Views/PhotoGridView.swift",
            "Lumina/Views/PhotoImageView.swift",
            "Lumina/Views/UnifiedCanvasView.swift",
            "Lumina/Views/Components/WorkspaceCommandBar.swift",
            "Lumina/Services/SourceCatalog.swift",
            "Lumina/Testing/ProbeV2/AcceptanceSignposts.swift",
        ]
        for rel in gone:
            self.assertFalse((ROOT / rel).is_file(), f"{rel} must stay deleted (zero callers)")
        compare = (ROOT / "Lumina/Views/CompareAndSoftViews.swift").read_text(encoding="utf-8")
        self.assertIn("struct DynamicSortBar", compare)
        self.assertNotIn("struct GradedCompareView", compare)
        self.assertNotIn("struct CompareOverlayView", compare)


class HeavyStubHonestyTests(unittest.TestCase):
    def test_ram_tiers_script_present(self) -> None:
        path = ROOT / "Scripts/harness/heavy/ram_tiers.sh"
        self.assertTrue(path.is_file(), "W6 implements ram_tiers.sh")

    def test_heavy_registry_marks_ram_active(self) -> None:
        text = (ROOT / "Scripts/harness/heavy_placeholders.py").read_text(encoding="utf-8")
        self.assertIn('"status": "active"', text)
        self.assertIn("ram_tier_runs", text)
        self.assertIn("Scripts/harness/heavy/ram_tiers.sh", text)


if __name__ == "__main__":
    unittest.main()
