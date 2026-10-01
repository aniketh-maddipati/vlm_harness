import os
import random
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import rank_signals as rs  # noqa: E402


def photo(n, sec, pick, row=0, **kw):
    p = {"pool": "a", "row": row, "n": n, "date": "2026-05-19", "sec": sec, "pick": pick, "path": f"x/{n}"}
    p.update(kw)
    return p


class RankSignalTests(unittest.TestCase):
    def test_pair_accuracy_counts_pick_over_non_pick_and_skips_missing(self):
        g = [photo(0, "10:00:00", True, s=3.0), photo(1, "10:00:01", False, s=1.0), photo(2, "10:00:02", False, s=3.0), photo(3, "10:00:03", False)]
        self.assertEqual(rs.pair_stats(g, "s", 1), (1.5, 2))          # one win, one tie; the frame without the signal is left out
        self.assertEqual(rs.pair_stats(g, "s", -1), (0.5, 2))
        r = rs.evaluate([g], "s", 1, random.Random(1), boots=20)
        self.assertAlmostEqual(r["acc"], 0.75)
        self.assertEqual(r["top1Groups"], 0, "top-1 needs the signal on every frame")

    def test_runs_split_on_the_gap_and_mark_the_last_frame(self):
        P = [photo(0, "10:00:00", False), photo(1, "10:00:02", True), photo(2, "10:00:30", False), photo(3, "10:00:31", False)]
        rs.add_order(P, run_gap=4)
        self.assertEqual([p["run"][1] for p in P], [0, 0, 1, 1])
        self.assertEqual([p["lastOfRun"] for p in P], [0.0, 1.0, 0.0, 1.0])
        self.assertEqual(P[1]["gapAfter"], 28)
        self.assertEqual(len(rs.groups_of(P, "run")), 1, "only the run with a pick and a non-pick is a choice")
        self.assertEqual(len(rs.groups_of(P, "row")), 1)

    def test_a_perfect_signal_is_learned_and_scored_on_held_out_days(self):
        rng, P = random.Random(3), []
        for d in range(4):
            for row in range(6):
                best = rng.randrange(4)
                for i in range(4):
                    P.append({"pool": "a", "row": d * 10 + row, "n": len(P), "date": f"2026-05-{10 + d}", "sec": f"10:{row:02d}:{i:02d}",
                              "pick": i == best, "path": str(len(P)), "good": 5.0 if i == best else rng.random(), "noise": rng.random()})
        r, w = rs.combined(P, [("good", 1), ("noise", 1)], "row", rng)
        self.assertGreater(r["acc"], 0.95)
        self.assertGreater(w[0], abs(w[1]))


if __name__ == "__main__":
    unittest.main()
