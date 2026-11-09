"""Tools/exposeval on synthetic data (numpy; Pillow only for the end-to-end case). Linux too."""
import datetime
import io
import math
import os
import pickle
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import adacg  # noqa: E402
import rule  # noqa: E402
import score  # noqa: E402
import target  # noqa: E402

try:
    import PIL  # noqa: F401
    HAVE_PIL = True
except ImportError:
    HAVE_PIL = False


def flat(level, h=18, w=32):
    return np.full((h, w, 3), level, dtype=np.uint8)


class Rule(unittest.TestCase):
    def test_tables(self):
        t = rule.level_table("rec709")
        self.assertEqual(t[0], 0.0)
        self.assertAlmostEqual(t[255], 1.0)
        self.assertAlmostEqual(t[10], (10 / 255) / 12.92)
        s = rule.level_table("slog3")
        # S-Log3: 18 % grey sits at code 420 of 1023; code 95 is black
        self.assertAlmostEqual(float(rule.slog3_to_linear(420.0)), 0.18)
        self.assertAlmostEqual(float(rule.slog3_to_linear(95.0)), 0.0)
        self.assertTrue(np.all(np.diff(s) >= 0))
        g = rule.level_table("rec709", gamma=2.4)
        self.assertAlmostEqual(g[128], (128 / 255) ** 2.4)

    def test_upper_median(self):
        self.assertEqual(rule.upper_median([3, 1, 2, 4]), 3.0)  # a[len >> 1] of [1,2,3,4]
        self.assertEqual(rule.upper_median([5, 1, 3]), 3.0)
        self.assertEqual(rule.upper_median([]), 0.0)

    def test_scene_sl_samples_every_8th_pixel(self):
        f = flat(0, 4, 16)
        f.reshape(-1, 3)[::8] = 255  # only the sampled pixels are white
        self.assertAlmostEqual(rule.scene_sl(f, rule.level_table()), 1.0)
        f2 = flat(255, 4, 16)
        f2.reshape(-1, 3)[::8] = 0
        self.assertEqual(rule.scene_sl(f2, rule.level_table()), 0.0)

    def test_scene_sl_rgba_and_luma(self):
        f = np.zeros((2, 8, 4), np.uint8)
        f[..., 1] = 255  # pure green
        self.assertAlmostEqual(rule.scene_sl(f, rule.level_table()), 0.7152)
        with self.assertRaises(ValueError):
            rule.scene_sl(f.astype(np.float32), rule.level_table())

    def test_ev_auto_map(self):
        m = rule.ev_auto_map({"a": 0.1, "b": 0.2, "c": 0.4, "d": 0.8, "e": 0.05, "z": None, "y": 0})
        # mid = upper median of [0.05, .1, .2, .4, .8] = 0.2
        self.assertEqual(m["b"], 0.0)
        self.assertEqual(m["a"], 1.0)
        self.assertEqual(m["c"], -1.0)
        self.assertEqual(m["d"], -1.0)  # −2 clamped
        self.assertEqual(m["e"], 1.0)   # +2 clamped
        self.assertNotIn("z", m)
        self.assertNotIn("y", m)
        free = rule.ev_auto_map({"a": 0.1, "b": 0.2, "d": 0.8}, clamp=None, round_to=None)
        self.assertAlmostEqual(free["d"], -2.0)

    def test_rounding_is_javascripts(self):
        # Math.round(0.125 * 100) / 100 = 0.13 (Python's round would give 0.12)
        mid, v = 1.0, 2 ** -0.125
        self.assertAlmostEqual(rule.ev_auto_map({"m": mid, "v": v, "w": 4.0})["v"], 0.13)

    def test_clip_value(self):
        self.assertEqual(rule.clip_value([0.1, 0.3]), 0.3)  # upper of two
        self.assertIsNone(rule.clip_value([0, 0]))


class Pickle(unittest.TestCase):
    def test_loads_numpy_and_datetime(self):
        db = {"root": "x", "choice86400.tif": {
            "set": {r: [0.0, 1.0] for r in adacg.REGIONS},
            "reg": {"darkest": [0.1, -10], "dark": [0.4, -5], "light": [0.5, 5], "lightest": [0.9, 10]},
            "hist": np.arange(256, dtype=np.float64), "thumb": np.frombuffer(b"\xff\xd8\xff", np.uint8).copy(),
            "labels": ["utah"], "time": datetime.datetime(2026, 1, 2)}}
        for proto in (3, 4):  # the label file is protocol 4; 2 (_codecs) and 5 (_frombuffer) name globals the whitelist refuses
            out = adacg.loads(pickle.dumps(db, protocol=proto))
            e = adacg.entries(out)["choice86400.tif"]
            self.assertEqual(adacg.pivots(e), [0.1, 0.4, 0.5, 0.9])
            self.assertEqual(adacg.falloffs(e), [-10, -5, 5, 10])
            self.assertEqual(float(e["hist"][255]), 255.0)
            self.assertEqual(e["time"].year, 2026)

    def test_refuses_other_globals(self):
        ran = []

        class Evil:
            def __reduce__(self):
                return (ran.append, ("ran",))

        with self.assertRaises(pickle.UnpicklingError):
            adacg.loads(pickle.dumps({"x": Evil()}))
        self.assertEqual(ran, [])
        # the classic: os.system by name
        payload = b"cos\nsystem\n(S'true'\ntR."
        with self.assertRaises(adacg.RefusedGlobal):
            adacg.loads(payload)

    def test_shot_of(self):
        self.assertEqual(adacg.shot_of("choice86400.tif"), adacg.shot_of("choice86401.tif"))
        self.assertNotEqual(adacg.shot_of("choice86401.tif"), adacg.shot_of("choice86402.tif"))


class Target(unittest.TestCase):
    def test_mid_and_absolute(self):
        p = [0.05, 0.4, 0.5, 0.9]
        self.assertAlmostEqual(target.mid_code(p), 0.45)
        self.assertAlmostEqual(target.mid_code(p, "light"), 0.5)
        code18 = 0.18 ** (1 / 2.4)
        self.assertAlmostEqual(target.absolute_ev([0, code18, code18, 1]), 0.0)
        # a middle one stop darker than 18 % asks for +1
        c = (0.09) ** (1 / 2.4)
        self.assertAlmostEqual(target.absolute_ev([0, c, c, 1]), 1.0)

    def test_relative(self):
        rel = target.relative_ev({"a": -3.0, "b": -2.0, "c": -1.0})
        self.assertEqual(rel, {"a": 1.0, "b": 0.0, "c": -1.0})


class Score(unittest.TestCase):
    def test_perfect_and_none(self):
        t = np.array([-1.0, -0.5, 0.0, 0.5, 1.0])
        m = score.metrics(t, t)
        self.assertEqual(m["median_abs"], 0.0)
        self.assertAlmostEqual(m["pearson"], 1.0)
        self.assertAlmostEqual(m["spearman"], 1.0)
        self.assertEqual(m["sign"], 1.0)
        self.assertEqual(m["sign_n"], 4)
        z = score.metrics(np.zeros(5), t)
        self.assertEqual(z["sign"], 0.0)  # no change never gets the direction
        self.assertAlmostEqual(z["median_abs"], 0.5)

    def test_spearman_ties(self):
        self.assertAlmostEqual(score.spearman([1, 2, 2, 3], [1, 2, 2, 3]), 1.0)

    def test_strength(self):
        rng = np.random.default_rng(1)
        x = rng.normal(size=300)
        y = 0.4 * x
        g = np.repeat(["a", "b", "c"], 100)
        pred, ks = score.cv_strength(g, x, y)
        for k in ks.values():
            self.assertAlmostEqual(k, 0.4)
        self.assertTrue(np.allclose(pred, y))
        a, b = score.fit_line(x, 1.0 + 2.0 * x)
        self.assertAlmostEqual(a, 1.0)
        self.assertAlmostEqual(b, 2.0)


@unittest.skipUnless(HAVE_PIL, "Pillow not installed")
class EndToEnd(unittest.TestCase):
    """A synthetic label file: flat grey thumbnails, an annotator whose middle moves half a stop per stop of the
    image's median. The eval should find slope ≈ 0.5 and k ≈ 0.5."""

    def make(self, path):
        from PIL import Image
        rng = np.random.default_rng(7)
        db = {"root": "synthetic"}
        n = 0
        for loc in ("utah", "alaska", "seattle"):
            for _ in range(20):
                lv = int(rng.integers(30, 230))
                lin = rule.level_table()[lv] * 1.0  # flat grey: luminance = the level's linear value
                mid_lin = 0.18 * (lin / 0.18) ** 0.5
                mid = float(mid_lin ** (1 / 2.4))  # a Python float: numpy scalars pickle as a global the whitelist refuses
                for _ in range(2):
                    buf = io.BytesIO()
                    Image.fromarray(flat(lv, 54, 102)).save(buf, "PNG")  # lossless stand-in for the JPEG
                    db["choice%05d.tif" % n] = {
                        "set": {r: [0.0, 0.0] for r in adacg.REGIONS},
                        "reg": {"darkest": [max(mid - 0.3, 0), -10], "dark": [mid - 0.05, -5], "light": [mid + 0.05, 5], "lightest": [min(mid + 0.3, 1), 10]},
                        "hist": np.ones(256), "thumb": np.frombuffer(buf.getvalue(), np.uint8).copy(),
                        "labels": [loc], "time": datetime.datetime(2026, 1, 1)}
                    n += 1
        with open(path, "wb") as f:
            pickle.dump(db, f, protocol=4)

    def test_run(self):
        import tempfile
        import run
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "labels.pkl")
            self.make(p)
            res, rows = run.run(p)
            self.assertEqual(res["shots"], 60)
            # the proxy is symmetric around mid in encoded levels, so mid_lin is close to (not exactly) the model
            self.assertAlmostEqual(res["follow"]["median"]["mid"]["slope"], 0.5, delta=0.05)
            self.assertAlmostEqual(res["relative"]["location"]["strength_k_all"], 0.5, delta=0.05)
            self.assertLess(res["relative"]["location"]["strength_cv"]["median_abs"], 0.05)
            md = run.report(res, "labels.pkl", "2026-01-01")
            self.assertIn("⇧E as shipped", md)
            self.assertNotIn("nan", md)


if __name__ == "__main__":
    unittest.main()
