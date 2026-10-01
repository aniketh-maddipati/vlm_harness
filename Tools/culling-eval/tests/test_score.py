import csv
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import score  # noqa: E402


def photo(n, date="2026-05-19", sec="10:00:00", **kw):
    p = {"path": f"shoot/DSC{n:05d}.ARW", "date": date, "sec": sec, "row": 0, "gid": f"g{n}", "kind": "single", "bn": 1, "rank": 1,
         "peak": False, "sug": True, "soft": False, "slight": False, "blown": False, "shake": False, "dark": False}
    p.update(kw)
    return p


class ScoreTests(unittest.TestCase):
    def test_a_pick_needs_the_name_and_the_capture_second(self):
        with tempfile.TemporaryDirectory() as d:
            ex = os.path.join(d, "exports.csv")
            with open(ex, "w", newline="") as f:
                w = csv.writer(f)
                w.writerow(["SourceFile", "FileName", "RawFileName", "DateTimeOriginal"])
                w.writerow(["a/x.jpg", "x.jpg", "DSC00001.ARW", "2026:05:19 10:00:00"])
                w.writerow(["a/y.jpg", "y.jpg", "", "2026:05:19 10:00:05"])           # a camera JPEG: no RAW named
            picks = score.load_picks(ex)
            self.assertEqual(picks, {("DSC00001", "2026-05-19 10:00:00")})
        photos = [photo(1), photo(1, date="2025-01-01"), photo(2)]                      # the same file number on another card
        labeled = score.label(photos, picks)
        self.assertEqual([p["pick"] for p in photos], [True, False, False])
        self.assertEqual(len(labeled), 2, "only the day with a pick is scored")

    def test_recall_flags_and_burst_rank(self):
        burst = [photo(10 + i, row=1, gid="g10", kind="burst", bn=4, rank=r, sug=(r == 1), peak=(i == 2)) for i, r in enumerate([2, 1, 3, 4])]
        photos = [photo(1), photo(2, soft=True, sug=False), photo(3, sug=False)] + burst
        for p in photos:
            p["pick"] = False
        photos[0]["pick"] = True            # a suggested single
        photos[1]["pick"] = True            # a pick flagged soft and not suggested
        burst[1]["pick"] = True             # the burst's rank 1
        s = score.score(photos)
        self.assertEqual(s["picks"], 3)
        self.assertAlmostEqual(s["suggested"]["recallOnPicks"], 2 / 3)
        self.assertEqual(s["flags"]["soft"]["picksFlagged"], 1)
        self.assertAlmostEqual(s["flags"]["soft"]["pickRateIfFlagged"], 1.0)
        st = s["stacks"]
        self.assertEqual((st["bursts"], st["burstsWithAPick"]), (1, 1))
        self.assertEqual(st["pickIsRank1"], 1.0)
        self.assertAlmostEqual(st["chanceRank1"], 0.25)
        self.assertAlmostEqual(st["chanceTop3"], 0.75)
        self.assertEqual(st["pickIsPeak"], 0.0)
        self.assertEqual(s["rows"]["rows"], 2)

    def test_report_runs_end_to_end_and_names_no_files(self):
        with tempfile.TemporaryDirectory() as d:
            run = os.path.join(d, "pool-a", "dump-decisions")
            os.makedirs(run)
            json.dump({"photos": [photo(1), photo(2, sug=False)]}, open(os.path.join(run, "decisions.json"), "w"))
            ex = os.path.join(d, "exports.csv")
            with open(ex, "w") as f:
                f.write("SourceFile,FileName,RawFileName,DateTimeOriginal\na,b,DSC00001.ARW,2026:05:19 10:00:00\na,c,DSC09999.ARW,2026:05:19 11:00:00\n")
            out = os.path.join(d, "report.md")
            self.assertEqual(score.main([os.path.join(run, "decisions.json"), "--exports", ex, "--out", out]), 0)
            text = open(out).read()
            self.assertIn("| pool-a | 1 | 2 | 1 |", text)
            self.assertIn("not found in these folders: 1", text)
            self.assertNotIn("DSC0", text)


if __name__ == "__main__":
    unittest.main()
