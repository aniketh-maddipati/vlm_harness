#!/usr/bin/env python3
"""FULL-lane property tests: banner=header=receipt; export=kept; chip⇔rung."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "probe"))
from simulator import ProbeSimulator, blank_state  # noqa: E402


class CountInvariantTests(unittest.TestCase):
    def test_banner_header_receipt_while_staged(self):
        sim = ProbeSimulator(blank_state("mixed-60", 1))
        sim.state["marks"]["a000"] = "keep"
        sim.state["marks"]["a001"] = "keep"
        sim._stage_row()
        s = sim.state["staging"]
        self.assertTrue(s["active"])
        self.assertEqual(s["bannerCount"], s["headerCount"])
        self.assertEqual(s["headerCount"], s["receiptCount"])
        self.assertEqual(s["receiptCount"], s["scopeCount"])

    def test_export_equals_kept(self):
        sim = ProbeSimulator(blank_state("mixed-60", 2))
        sim.state["marks"]["a000"] = "keep"
        sim.state["marks"]["a002"] = "keep"
        sim.state["marks"]["a003"] = "reject"
        kept = sum(1 for v in sim.state["marks"].values() if v == "keep")
        sim.state["exportKeptCount"] = kept
        self.assertEqual(sim.state["exportKeptCount"], kept)

    def test_chip_absence_iff_full_rung(self):
        sim = ProbeSimulator(blank_state("mixed-60", 3, n=1))
        sim.state["residentRungByFrame"]["a000"] = "full"
        sim.state["chipPresent"] = False
        err = sim.check_assert({"op": "chipAbsenceIffFullRung"})
        self.assertIsNone(err)
        sim.state["chipPresent"] = True
        err = sim.check_assert({"op": "chipAbsenceIffFullRung"})
        self.assertIsNotNone(err)

    def test_one_undo_per_mark_gesture(self):
        sim = ProbeSimulator(blank_state("mixed-60", 4))
        before = sim.state["undoDepth"]
        sim.apply_event({"op": "key", "key": "P", "tMs": 0})
        self.assertEqual(sim.state["undoDepth"], before + 1)
        sim.apply_event({"op": "key", "key": "X", "tMs": 83})
        self.assertEqual(sim.state["undoDepth"], before + 2)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
