"""calibrate.py on synthetic skim runs: a cue that marks the bad frames is found and the rule holds on a test run."""
import json
import os
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import calibrate  # noqa: E402

H, W, N = 40, 60, 40


def box(x0, y0=10, w=20, h=20):
    m = np.zeros((H, W), bool)
    m[y0:y0 + h, x0:x0 + w] = True
    return m


def save(folder, n, m):
    os.makedirs(folder, exist_ok=True)
    Image.fromarray(m.astype(np.uint8) * 255).save(os.path.join(folder, f"{n:06d}.png"))


def make(evid, name, rivals_on, look_far=frozenset()):
    """A clip where the track takes a look-alike (IoU 0) on the frames in rivals_on, which also have 2 rivals;
    the app called every frame sure."""
    run = os.path.join(evid, "runs", name, "skim")
    clip = os.path.join(run, "clip")
    cues, states = [], []
    for n in range(N):
        save(os.path.join(evid, "labels", "clip"), n, box(5))
        wrong = n in rivals_on
        merged = n in look_far  # the shape takes in a neighbour: IoU 0.5 against the truth, and it looks unlike the start
        save(clip, n, box(5, w=40) if merged else box(35) if wrong else box(5))
        cues.append({"tracker": 0.9, "agree": 0.8, "area": 0.1, "last": 0.1, "refound": False, "score": 0.9,
                     "rivals": 2 if wrong else 1, "lost": 0, "look": 0.7 if merged else 0.1})
        states.append("sure")
    with open(os.path.join(clip, "timing.json"), "w") as f:
        json.dump({"tracker": "skim", "start_frame": 0, "frames": N, "total_ms": 1000.0,
                   "sure_frames": states, "cues_frames": cues}, f)
    return run


class CalibrateTests(unittest.TestCase):
    def test_rivals_mark_the_wrong_frames(self):
        with tempfile.TemporaryDirectory() as evid:
            train = make(evid, "train", set(range(10, 25)))
            test = make(evid, "test", set(range(0, 8)))
            rs = calibrate.rows(*calibrate.parse_run(train))
            self.assertEqual(len(rs), N)
            today = calibrate.measure(rs, [r["today"] == "sure" for r in rs])
            self.assertAlmostEqual(today["sure_share"], 1.0)
            self.assertAlmostEqual(today["bad_share"], 15 / 40)
            rule, m = calibrate.fit(rs)
            self.assertEqual(rule["rivals"], 1)
            self.assertAlmostEqual(m["iou_sure"], 1.0)
            self.assertAlmostEqual(m["sure_share"], 25 / 40)
            held = calibrate.rows(*calibrate.parse_run(test))
            t = calibrate.measure(held, [calibrate.sure(r, rule) for r in held])
            self.assertEqual(t["bad_share"], 0.0)
            out = os.path.join(evid, "rule.json")
            self.assertEqual(calibrate.main(["--fit", train, "--test", test, "--out", out]), 0)
            self.assertEqual(json.load(open(out))["rule"]["rivals"], 1)

    def test_a_frame_without_a_shape_is_never_sure(self):
        r = {"found": False, "refound": False, "tracker": None, "agree": None, "rivals": 0, "start": None, "jump": None,
             "look": None}
        self.assertFalse(calibrate.sure(r, {k: v[0] for k, v in calibrate.GRID.items()}))

    def test_the_look_cue_marks_a_merged_shape(self):
        with tempfile.TemporaryDirectory() as evid:
            train = make(evid, "train", set(), look_far=set(range(5, 20)))
            rs = calibrate.rows(*calibrate.parse_run(train))
            rule, m = calibrate.fit(rs)
            self.assertLessEqual(rule["look"], 0.4)
            self.assertAlmostEqual(m["sure_share"], 25 / 40)
            self.assertAlmostEqual(m["iou_sure"], 1.0)


if __name__ == "__main__":
    unittest.main()
