#!/usr/bin/env python3
from __future__ import annotations

import unittest

import parse_signposts as trace


SAMPLE = """
signpost begin lumina.accept.open id=1
signpost end   lumina.accept.open id=1 duration_ms=420
signpost begin lumina.accept.crossfade id=2
signpost end   lumina.accept.crossfade id=2 duration_ms=120 layout_passes=0
signpost begin lumina.accept.settle id=3
signpost end   lumina.accept.settle id=3 duration_ms=200 overshoot_pct=1.2
signpost begin lumina.accept.grab id=4
signpost end   lumina.accept.grab id=4 duration_ms=90
signpost begin lumina.accept.halo id=5
signpost end   lumina.accept.halo id=5 duration_ms=600
signpost begin lumina.accept.slider_to_photon id=6
signpost end   lumina.accept.slider_to_photon id=6 duration_ms=16.5
"""


class TraceParseTests(unittest.TestCase):
    def test_parser_unit_on_sample(self):
        """Sample log exercises the parser only — not a lane PASS (F4)."""
        events = trace.parse_trace(SAMPLE)
        self.assertEqual(len(events), 6)
        report = trace.evaluate(events)
        self.assertEqual(report["mode"], "measured")
        self.assertTrue(report["gates_active"])
        self.assertTrue(report["ok"], report)

    def test_fail_on_layout_passes(self):
        bad = "signpost end lumina.accept.crossfade id=1 duration_ms=120 layout_passes=2\n"
        report = trace.evaluate(trace.parse_trace(bad))
        self.assertFalse(report["ok"])
        cross = next(r for r in report["results"] if r["name"] == "crossfade_same_rect")
        self.assertFalse(cross["pass"])

    def test_orchestration_ledger_unmeasured(self):
        report = trace.orchestration_ledger()
        self.assertEqual(report["mode"], "orchestration-only")
        self.assertFalse(report["gates_active"])
        self.assertIsNone(report["ok"])
        self.assertTrue(report["results"])
        for entry in report["results"]:
            self.assertEqual(entry["status"], "UNMEASURED")
            self.assertEqual(entry["samples"], 0)
            self.assertIsNone(entry["pass"])
        names = {e["name"] for e in report["results"]}
        for required in (
            "open_usable",
            "crossfade_same_rect",
            "settle",
            "grab",
            "halo",
            "slider_to_photon",
        ):
            self.assertIn(required, names)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
