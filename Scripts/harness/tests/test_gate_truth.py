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
            "Lumina/Design/LuminaSpring.swift LuminaSpring",
            "Lumina/Core/BetaDiagnosticsSocket.swift BetaDiagnosticsSocket",
            "Lumina/Views/Components/RecoveryFactsChip.swift RecoveryFactsChip",
        ):
            self.assertIn(needle, reg)

    def test_decision_dock_reported_dead_not_registered(self) -> None:
        reg = (ROOT / "artifacts/harness/orphan_register.txt").read_text(encoding="utf-8")
        self.assertNotIn("DecisionDock.swift DecisionDock", reg)
        proc = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/harness/lint/orphan_symbols.py")],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        self.assertIn("DecisionDock.swift · DecisionDock", proc.stderr)


class HeavyStubHonestyTests(unittest.TestCase):
    def test_ram_tiers_script_absent(self) -> None:
        path = ROOT / "Scripts/harness/heavy/ram_tiers.sh"
        self.assertFalse(path.is_file())

    def test_heavy_registry_marks_ram_stub(self) -> None:
        text = (ROOT / "Scripts/harness/heavy_placeholders.py").read_text(encoding="utf-8")
        self.assertIn('"status": "stub-missing"', text)
        self.assertIn("ram_tier_runs", text)


if __name__ == "__main__":
    unittest.main()
