#!/usr/bin/env python3
"""Parser tests for non-vacuous progressive render live gates."""
from __future__ import annotations

import sys
import hashlib
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from run_live_progressive_focus import validate as validate_focus  # noqa: E402
from run_live_raw_render import validate as validate_raw  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "fixtures"))
from verify_raw_fixture_bundle import verify as verify_fixture  # noqa: E402


class RenderGateParserTests(unittest.TestCase):
    def test_raw_report_requires_live_materialization_and_hits(self) -> None:
        report = {
            "failures": 0,
            "fleet": [
                {
                    "fixture": "sony.ARW",
                    "live": {
                        "interactiveStageMaterialized": True,
                        "fidelity": {
                            "status": "measured",
                            "deltaE2000Mean": 1,
                            "deltaE2000P95": 4,
                            "ssimLuma": 0.98,
                            "maeR_8bit": 2,
                            "maeG_8bit": 1,
                            "maeB_8bit": 1,
                            "clippedFractionPreview": 0.35,
                            "clippedFractionExport": 0.34,
                        },
                    },
                }
            ],
            "live": {
                "interactiveColdMs": 120,
                "settledMs": 180,
                "interactiveScrub": {
                    "count": 20,
                    "rawStageCacheHits": 20,
                    "p95Ms": 12,
                },
                "interactiveExposureReusesRawStage": True,
                "interactiveWBReusesRawStage": True,
                "interactiveNRInvalidates": True,
                "settledRawIntentInvalidates": True,
                "interactiveStageMaterialized": True,
                "authoritativeStageStayedLazy": True,
                "fidelity": {
                    "status": "measured",
                    "deltaE2000Mean": 1,
                    "deltaE2000P95": 4,
                    "ssimLuma": 0.98,
                    "maeR_8bit": 2,
                    "maeG_8bit": 1,
                    "maeB_8bit": 1,
                    "clippedFractionPreview": 0.35,
                    "clippedFractionExport": 0.34,
                },
            },
        }
        self.assertEqual(validate_raw(report)["rawStageCacheHits"], 20)

    def test_blocked_raw_report_is_failure(self) -> None:
        with self.assertRaises(RuntimeError):
            validate_raw(
                {
                    "failures": 0,
                    "live": {"status": "blocked", "reason": "no fixture"},
                }
            )

    def test_focus_report_requires_gpu_samples_and_stability(self) -> None:
        report = {
            "status": "passed",
            "failures": 0,
            "rapidScrub": {
                "blankSeen": False,
                "draw3Seconds": {
                    "sampleCount": 180,
                    "p95Ms": 8,
                    "window": "n=180, full run",
                },
            },
            "navigation": {"blankAfterWait": False, "p95Ms": 40},
            "focusStability": {
                "identityStable": True,
                "fidelityMonotonic": True,
                "geometryStable": True,
                "authoritativeReachedDrawable": True,
            },
        }
        self.assertEqual(validate_focus(report)["drawSampleCount"], 180)

    def test_empty_draw_capture_is_failure(self) -> None:
        with self.assertRaises(RuntimeError):
            validate_focus(
                {
                    "status": "passed",
                    "failures": 0,
                    "rapidScrub": {
                        "blankSeen": False,
                        "draw3Seconds": {"sampleCount": 0, "p95Ms": 0},
                    },
                    "navigation": {"blankAfterWait": False},
                    "focusStability": {},
                }
            )

    def test_fixture_bundle_requires_matching_per_file_checksums(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lines = []
            for name in ("sony.ARW", "canon.CR3", "phone.DNG"):
                data = f"fixture:{name}".encode()
                (root / name).write_bytes(data)
                lines.append(f"{hashlib.sha256(data).hexdigest()}  {name}")
            (root / "checksums.sha256").write_text(
                "\n".join(lines) + "\n",
                encoding="utf-8",
            )
            checked = verify_fixture(
                root,
                "hosted",
                {
                    "checksums": "checksums.sha256",
                    "tiers": {
                        "hosted": {
                            "required_extensions": [".ARW", ".CR3", ".DNG"],
                            "minimum_photos": 3,
                        }
                    },
                },
            )
            self.assertEqual(checked, 3)


if __name__ == "__main__":
    unittest.main()
