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
    def test_parse_and_pass(self):
        events = trace.parse_trace(SAMPLE)
        self.assertEqual(len(events), 6)
        report = trace.evaluate(events)
        self.assertTrue(report["ok"], report)
        by = {r["name"]: r for r in report["results"]}
        self.assertTrue(by["crossfade_same_rect"]["pass"])
        self.assertTrue(by["settle"]["pass"])

    def test_fail_on_layout_passes(self):
        bad = "signpost end lumina.accept.crossfade id=1 duration_ms=120 layout_passes=2\n"
        # include others as missing → overall fail
        report = trace.evaluate(trace.parse_trace(bad))
        self.assertFalse(report["ok"])
        cross = next(r for r in report["results"] if r["name"] == "crossfade_same_rect")
        self.assertFalse(cross["pass"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
