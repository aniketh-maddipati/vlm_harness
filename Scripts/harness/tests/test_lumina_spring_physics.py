#!/usr/bin/env python3
"""Headless unit tests for owned spring physics (no F07 seal required)."""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "Scripts" / "harness"
sys.path.insert(0, str(HARNESS))

from physics.lumina_spring import (  # noqa: E402
    LuminaSpringRetarget,
    params,
    params_reduced_motion,
    trajectory,
    value_at,
)


class LuminaSpringPhysicsTests(unittest.TestCase):
    def test_starts_at_initial_value(self) -> None:
        p = params(180, curve="easeOut")
        self.assertAlmostEqual(value_at(0, p, initial_value=0.2), 0.2)

    def test_converges_toward_target(self) -> None:
        p = params(180, curve="easeOut")
        end = value_at(2.0, p)
        self.assertAlmostEqual(end, 1.0, delta=0.02)

    def test_retarget_preserves_state(self) -> None:
        p = params(200, curve="easeOut")
        mid = 0.1
        before = trajectory(mid, p)
        after = trajectory(0.2, p, retargets=[LuminaSpringRetarget(time=mid, target=0.5)])
        before_at = before[-1]
        after_at = next(s for s in after if abs(s.time - mid) < 1e-9)
        self.assertAlmostEqual(after_at.value, before_at.value, places=6)
        self.assertAlmostEqual(after_at.velocity, before_at.velocity, places=6)

    def test_reduced_motion_peak_near_target(self) -> None:
        p = params_reduced_motion(200)
        samples = trajectory(0.5, p)
        peak = max(s.value for s in samples)
        self.assertLessEqual(peak, 1.0 + 1e-6)

    def test_sample_count_matches_rate(self) -> None:
        p = params(180, curve="easeOut")
        hz = 120.0
        horizon = 0.325
        samples = trajectory(horizon, p, sample_rate_hz=hz)
        expected = int(math.floor(horizon * hz)) + 1
        self.assertEqual(len(samples), expected)


if __name__ == "__main__":
    unittest.main()
