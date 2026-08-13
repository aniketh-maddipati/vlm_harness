#!/usr/bin/env python3
"""Unit tests for vacuous-green inventory + platform gate (F1/F3)."""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from inventory import evaluate_inventory, format_lane_summary, load_manifest
from host_platform import check_lane_platform
from budget_breach import budget_breach_lines, slowest_test_rows


class InventoryTests(unittest.TestCase):
    def test_fast_manifest_has_zero_app_coupled(self):
        m = load_manifest()
        app = [t for t in m["lanes"]["fast"]["tests"] if t["kind"] == "app-coupled"]
        self.assertEqual(app, [])

    def test_manifest_rejects_duplicate_test_ids(self):
        manifest = {
            "lanes": {
                "fast": {
                    "tests": [
                        {"id": "same", "kind": "orchestration"},
                        {"id": "same", "kind": "orchestration"},
                    ]
                }
            }
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate test ids.*same"):
                load_manifest(path)

    def test_full_and_heavy_require_macos_as(self):
        m = load_manifest()
        self.assertEqual(m["lanes"]["full"]["platform"], "macos-apple-silicon")
        self.assertEqual(m["lanes"]["heavy"]["platform"], "macos-apple-silicon")

    def test_vacuous_green_incomplete_when_zero_app(self):
        # FULL with only orchestration ids executed → INCOMPLETE
        result = evaluate_inventory("full", ["worktree_snapshot", "ledger_orchestration_write"])
        self.assertEqual(result["verdict"], "INCOMPLETE")
        self.assertEqual(result["executed_app_coupled"], 0)
        self.assertGreater(result["expected_app_coupled"], 0)

    def test_fast_pass_with_full_orchestration_inventory(self):
        m = load_manifest()
        ids = [t["id"] for t in m["lanes"]["fast"]["tests"]]
        result = evaluate_inventory("fast", ids)
        self.assertEqual(result["verdict"], "PASS")
        self.assertEqual(result["executed_app_coupled"], 0)
        self.assertEqual(result["expected_app_coupled"], 0)

    def test_summary_line_shows_app_counts(self):
        inv = {
            "executed_app_coupled": 0,
            "expected_app_coupled": 6,
            "executed_orchestration": 2,
        }
        line = format_lane_summary("heavy", "PLATFORM-UNAVAILABLE", 280, inv)
        self.assertIn("0 app tests executed", line)
        self.assertIn("6 expected", line)
        self.assertIn("PLATFORM-UNAVAILABLE", line)


class PlatformTests(unittest.TestCase):
    def test_any_platform_ok(self):
        status, _ = check_lane_platform("any")
        self.assertEqual(status, "ok")

    def test_force_unavailable(self):
        with mock.patch.dict(os.environ, {"LUMINA_HARNESS_FORCE_PLATFORM_UNAVAILABLE": "1"}):
            status, reason = check_lane_platform("macos-apple-silicon")
        self.assertEqual(status, "platform-unavailable")
        self.assertIn("forced", reason)

    def test_linux_full_unavailable(self):
        # This cloud host is Linux — FULL must be unavailable.
        status, reason = check_lane_platform("macos-apple-silicon")
        if os.uname().sysname != "Darwin":
            self.assertEqual(status, "platform-unavailable")
            self.assertIn("Darwin", reason)


class BudgetBreachTests(unittest.TestCase):
    def test_slowest_rows_descending(self):
        rows = slowest_test_rows(
            [{"step": "a", "ms": 10}, {"step": "b", "ms": 50}, {"step": "c", "ms": 25}]
        )
        self.assertEqual([r["step"] for r in rows], ["b", "c", "a"])

    def test_breach_message_lists_ids_and_delete_or_demote_only(self):
        lines = budget_breach_lines(
            "fast",
            120_000,
            90_000,
            [{"step": "slow_lint", "ms": 40_000}, {"step": "fast_lint", "ms": 1000}],
        )
        text = "\n".join(lines)
        self.assertIn("BUDGET BREACH: FAST 120000ms > 90000ms ceiling", text)
        self.assertIn("slow_lint: 40000ms", text)
        self.assertIn("fast_lint: 1000ms", text)
        self.assertEqual(lines[-1], "delete or demote")
        for forbidden in ("hardware", "parallel", "parallelism", "raise the ceiling", "raised ceiling"):
            self.assertNotIn(forbidden, text.lower())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
