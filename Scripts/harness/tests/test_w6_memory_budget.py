#!/usr/bin/env python3
"""W6 — RAM tier gate and byte-budgeted PhotoImageCache."""
from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class MemoryBudgetTests(unittest.TestCase):
    def test_ram_tiers_script_exists(self) -> None:
        path = ROOT / "Scripts/harness/heavy/ram_tiers.sh"
        self.assertTrue(path.is_file())
        text = path.read_text(encoding="utf-8")
        self.assertIn("--ram-harness", text)

    def test_run_job_delegates_ram_tier(self) -> None:
        text = (ROOT / "Scripts/harness/heavy/run_job.py").read_text(encoding="utf-8")
        self.assertIn('"ram_tier_runs": "ram_tiers.sh"', text)

    def test_photo_cache_byte_budget_constants(self) -> None:
        text = (ROOT / "Lumina/Services/PhotoImageCacheBudget.swift").read_text(encoding="utf-8")
        for needle in (
            "gridTierCeilingBytes",
            "previewTierCeilingBytes",
            "proxyTierCeilingBytes",
            "totalCeilingBytes",
            "prefetchConcurrencyWidth",
            "proposal awaiting contract ruling",
        ):
            self.assertIn(needle, text)

    def test_photo_cache_uses_byte_budget(self) -> None:
        text = (ROOT / "Lumina/Services/PhotoImageCache.swift").read_text(encoding="utf-8")
        self.assertIn("PhotoImageCacheBudget.memoryCost", text)
        self.assertIn("prefetchConcurrencyWidth", text)
        self.assertIn("autoreleasepool", text)
        self.assertNotIn("memoryCap = 320", text)

    def test_shared_ci_context(self) -> None:
        awb = (ROOT / "Lumina/Services/AutoWhiteBalance.swift").read_text(encoding="utf-8")
        export = (ROOT / "Lumina/Services/ExportService.swift").read_text(encoding="utf-8")
        self.assertIn("DevelopRenderGraph.sharedContext", awb)
        self.assertIn("DevelopRenderGraph.sharedExportContext", export)
        self.assertNotIn("CIContext()", export)

    def test_heavy_registry_active(self) -> None:
        text = (ROOT / "Scripts/harness/heavy_placeholders.py").read_text(encoding="utf-8")
        self.assertIn('"id": "ram_tier_runs"', text)
        self.assertIn('"status": "active"', text)

    def test_ram_harness_runner_exists(self) -> None:
        path = ROOT / "Lumina/Develop/Lab/RamTierHarnessRunner.swift"
        self.assertTrue(path.is_file())
        self.assertIn("mixed-200", path.read_text(encoding="utf-8"))
        self.assertIn("card-clean-500", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
