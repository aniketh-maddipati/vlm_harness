"""score.py on synthetic clips: a moving disc tracked exactly, one that drifts off, one that flickers.
Runs on Linux: python3 -m unittest discover -s Tools/masklab/tests (or pytest)."""
import json
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import score  # noqa: E402

H, W, R, N = 90, 160, 14, 60
LABELLED = list(range(0, N, 10)) + [N - 1]


def disc(cx, cy, r=R, h=H, w=W):
    y, x = np.mgrid[0:h, 0:w]
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def centre(n):
    """The object moves left to right across the clip."""
    return 30 + n * 1.5, 45


def write(folder, n, mask, pad=6):
    os.makedirs(folder, exist_ok=True)
    Image.fromarray(mask.astype(np.uint8) * 255).save(os.path.join(folder, f"{n:0{pad}d}.png"))


def write_timing(folder, frames, start=0, ms=10.0):
    with open(os.path.join(folder, "timing.json"), "w") as f:
        json.dump({"tracker": "synthetic", "start_frame": start, "frames": frames,
                   "total_ms": frames * ms * 2, "per_frame_ms": [ms] * frames,
                   "device": {"model": "test"}}, f)


class ScoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.labels = os.path.join(self.root, "labels")
        # Sparse labels: every 10th frame and the last, file names not zero-padded.
        for n in LABELLED:
            write(os.path.join(self.labels, "clip"), n, disc(*centre(n)), pad=1)

    def tearDown(self):
        self.tmp.cleanup()

    def run_dir(self, name, mask_of):
        folder = os.path.join(self.root, name, "clip")
        for n in range(N):
            write(folder, n, mask_of(n))
        write_timing(folder, N)
        return os.path.join(self.root, name)

    def clip(self, run):
        return score.score_runs([run], self.labels)["runs"][0]["clips"]["clip"]

    def test_moving_disc_tracked_exactly(self):
        c = self.clip(self.run_dir("exact", lambda n: disc(*centre(n))))
        self.assertEqual(c["labelled"], 7)
        self.assertEqual(c["missing"], 0)
        self.assertAlmostEqual(c["iou"], 1.0)
        self.assertAlmostEqual(c["bf"], 1.0)
        self.assertAlmostEqual(c["slope100"], 0.0)
        self.assertAlmostEqual(c["last10"], 1.0)
        self.assertAlmostEqual(c["fps"], 50.0)          # 60 frames in 1.2 s
        self.assertAlmostEqual(c["work_ms_median"], 10.0)
        # The object moves, so its labels never hold still: no still stretches to score.
        self.assertIsNone(c["flicker"])
        self.assertGreater(c["flicker_all"], 0)

    def test_volumetric_j_does_not_reward_empty_frames(self):
        # The object is hidden (empty label) on half the labelled frames; a tracker that gives up there and
        # everywhere else scores 0.5 per-frame J, but 0 volumetric J.
        for n in LABELLED[::2]:
            write(os.path.join(self.labels, "clip"), n, np.zeros((H, W), bool), pad=1)
        none = self.clip(self.run_dir("none", lambda n: np.zeros((H, W), bool)))
        self.assertGreater(none["iou"], 0.4)
        self.assertAlmostEqual(none["vj"], 0.0)
        exact = self.clip(self.run_dir("exact2", lambda n: disc(*centre(n)) if n not in LABELLED[::2] else np.zeros((H, W), bool)))
        self.assertAlmostEqual(exact["vj"], 1.0)

    def test_drifting_mask(self):
        # The mask slides off the object, a little more each frame.
        c = self.clip(self.run_dir("drift", lambda n: disc(centre(n)[0] + n * 0.5, 45)))
        self.assertLess(c["iou"], 0.9)
        self.assertLess(c["slope100"], -0.5, "IoU falls with time")
        self.assertLess(c["last10"], c["iou"])
        self.assertLess(c["bf"], 0.8)
        self.assertGreater(c["per_frame"][0]["iou"], 0.99)

    def test_flickering_mask_on_a_still_object(self):
        still = disc(80, 45)
        for n in LABELLED:
            write(os.path.join(self.labels, "clip"), n, still, pad=1)
        steady = self.clip(self.run_dir("steady", lambda n: still))
        flick = self.clip(self.run_dir("flick", lambda n: still if n % 2 == 0 else disc(80, 45, R + 3)))
        self.assertEqual(steady["flicker"], 0.0)
        self.assertEqual(steady["flicker_all"], 0.0)
        self.assertEqual(steady["still_pairs"], N - 1)  # every pair: the labels hold still throughout
        self.assertGreater(flick["flicker"], 0.3)
        self.assertAlmostEqual(flick["flicker"], flick["flicker_all"], places=6)
        # Flicker hardly moves the mean IoU: that is why it is measured on its own.
        self.assertGreater(flick["iou"], 0.8)

    def test_missing_and_lost_frames(self):
        folder = os.path.join(self.root, "lost", "clip")
        for n in range(N):
            if n < 30:
                write(folder, n, disc(*centre(n)))
            elif n < 45:
                write(folder, n, np.zeros((H, W), bool))  # lost: empty mask
        write_timing(folder, N)                            # asked for 60 frames, wrote 45
        c = self.clip(os.path.join(self.root, "lost"))
        self.assertEqual(c["empty"], 15)
        self.assertEqual(c["missing"], 2)                  # frames 50 and 59
        self.assertAlmostEqual(c["iou"], 3 / 7)
        self.assertEqual(c["last10"], 0.0)

    def test_the_skim_strip_is_scored_against_the_truth(self):
        # The app's track: exact while sure (0-29), off the object while it says shaky (30-44), empty while lost.
        folder = os.path.join(self.root, "skim", "clip")
        states = []
        for n in range(N):
            if n < 30:
                write(folder, n, disc(*centre(n))); states.append("sure")
            elif n < 45:
                write(folder, n, disc(*centre(n + 20))); states.append("shaky")
            else:
                write(folder, n, np.zeros((H, W), bool)); states.append("lost")
        with open(os.path.join(folder, "timing.json"), "w") as f:
            json.dump({"tracker": "skim", "start_frame": 0, "frames": N, "total_ms": N * 20.0, "per_frame_ms": [],
                       "sure_frames": states}, f)
        report = score.score_runs([os.path.join(self.root, "skim")], self.labels)
        c = report["runs"][0]["clips"]["clip"]
        self.assertAlmostEqual(c["sure_share"], 0.5)
        by = c["iou_by_sure"]
        self.assertEqual({k: v["n"] for k, v in by.items()}, {"sure": 3, "shaky": 2, "lost": 2})
        self.assertAlmostEqual(by["sure"]["iou"], 1.0)
        self.assertEqual(by["lost"]["iou"], 0.0)
        self.assertLess(by["shaky"]["iou"], 0.2)
        s = report["runs"][0]["summary"]
        self.assertAlmostEqual(s["sure_share"], 0.5)
        self.assertEqual(s["iou_by_sure"]["sure"]["n"], 3)
        self.assertIn("IoU when lost 0.000 (2)", score.table(report))

    def test_summary_is_the_mean_over_clips(self):
        run = self.run_dir("exact", lambda n: disc(*centre(n)))
        s = score.score_runs([run], self.labels)["runs"][0]["summary"]
        self.assertEqual(s["clips"], 1)
        self.assertAlmostEqual(s["iou"], 1.0)
        self.assertAlmostEqual(s["jf"], (s["iou"] + s["bf"]) / 2)
        self.assertIsNone(s["sure_share"])

    def test_run_at_another_size_is_resampled(self):
        folder = os.path.join(self.root, "half", "clip")
        for n in range(N):
            write(folder, n, disc(centre(n)[0] / 2, 22.5, R / 2, H // 2, W // 2))
        c = self.clip(os.path.join(self.root, "half"))
        self.assertGreater(c["iou"], 0.85)
        self.assertIsNone(c["fps"])                       # no timing.json

    def test_no_labels_still_reports_fps_and_flicker(self):
        run = self.run_dir("nolabels", lambda n: disc(*centre(n)))
        c = score.score_runs([run], None)["runs"][0]["clips"]["clip"]
        self.assertEqual(c["labelled"], 0)
        self.assertIsNone(c["iou"])
        self.assertIsNotNone(c["flicker_all"])
        self.assertAlmostEqual(c["fps"], 50.0)

    def test_a_clip_that_never_started_is_left_out(self):
        run = self.run_dir("partial", lambda n: disc(*centre(n)))
        os.makedirs(os.path.join(run, "background-clip", "frames"))   # the tracker stopped at its start frame
        self.assertEqual(list(score.score_runs([run], self.labels)["runs"][0]["clips"]), ["clip"])

    def test_cli_writes_report_and_table(self):
        run = self.run_dir("cli", lambda n: disc(*centre(n)))
        out = os.path.join(self.root, "report.json")
        self.assertEqual(score.main([run, "--labels", self.labels, "--out", out, "--quiet"]), 0)
        with open(out) as f:
            rep = json.load(f)
        self.assertEqual(rep["runs"][0]["run"], "cli")
        self.assertIn("clip", score.table(rep))

    def test_boundary_tolerance(self):
        a, b = disc(80, 45), disc(81, 45)
        self.assertLess(score.boundary_f(a, b, 0), 0.9)
        self.assertAlmostEqual(score.boundary_f(a, b, 1.5), 1.0)
        empty = np.zeros_like(a)
        self.assertEqual(score.boundary_f(empty, empty, 2), 1.0)
        self.assertEqual(score.boundary_f(a, empty, 2), 0.0)
        self.assertEqual(score.iou(empty, empty), 1.0)


if __name__ == "__main__":
    unittest.main()
