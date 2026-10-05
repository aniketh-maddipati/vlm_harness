import json
import os
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import lookmath as lm  # noqa: E402

RULES = os.path.join(HERE, "..", "..", "..", "Lumina", "Sets", "Look", "rules-v1.json")
AS_SHOT = (5500.0, 0.0)


class LookMathMirrorTests(unittest.TestCase):
    """The same properties LookMathTests.swift checks, on the numpy copy."""

    @classmethod
    def setUpClass(cls):
        with open(RULES) as f:
            cls.rules = json.load(f)
        cls.ramp = np.stack([np.linspace(0, 1.2, 61)] * 3, axis=-1)

    def sweep(self):
        for s in lm.LR_SLIDERS:
            vals = {"Exposure": [-5, -2, -0.5, 0.5, 2, 5], "Temperature": [2000, 3200, 4500, 6500, 9000, 50000],
                    "Tint": [-150, -40, 40, 150], "Sharpness": [10, 50, 150]}.get(s, [-100, -50, -10, 10, 50, 100])
            for v in vals:
                yield s, v

    def test_rules_file_names_every_stage(self):
        self.assertEqual(self.rules["order"], ["rawDevelop"] + lm.STAGES + ["outputTransform"])
        for s in lm.STAGES:
            self.assertIn(s, self.rules["stages"])
        self.assertAlmostEqual(sum(self.rules["luma"]), 1.0, places=3)

    def test_reset_is_identity(self):
        np.testing.assert_allclose(lm.flat(self.ramp, lm.parse_look(""), AS_SHOT, self.rules), self.ramp, atol=1e-12)

    def test_monotonic_and_neutral(self):
        for s, v in self.sweep():
            out = lm.flat(self.ramp, lm.single(s, v, AS_SHOT), AS_SHOT, self.rules)
            y = lm.luma(out, self.rules)
            self.assertTrue(np.all(np.diff(y) >= -1e-9), f"{s} {v} not monotonic")
            self.assertTrue(np.all(np.isfinite(out)) and np.all(out >= 0), f"{s} {v} out of range")
            if s not in ("Temperature", "Tint"):
                self.assertTrue(np.all(np.abs(out[:, 0] - out[:, 1]) <= 1e-3 * np.maximum(1, out[:, 1])), f"{s} {v} tinted a grey")

    def test_signs(self):
        r = self.rules
        g = lambda look, v: float(lm.luma(lm.flat(np.array([v, v, v]), look, AS_SHOT, r), r))
        # Exposure: a scene gain through a sigmoid tone curve. Shadows take the full gain,
        # highlights roll off, +1 then -1 is nothing.
        G = lm.exposure_gain(1, r)
        self.assertAlmostEqual(g(lm.single("Exposure", 1), 1e-5) / 1e-5, G, places=2)
        self.assertGreater(g(lm.single("Exposure", 1), 0.18) / 0.18, g(lm.single("Exposure", 1), 0.8) / 0.8)
        for x in (-0.02, 0.0, 0.18, 0.6, 1.4):
            self.assertAlmostEqual(float(lm.exposure(lm.exposure(x, 1, r), -1, r)), x)
        ys = lm.exposure(np.linspace(-0.2, 4, 400), -2, r)
        self.assertTrue(np.all(np.diff(ys) > 0))
        self.assertLess(g(lm.single("Contrast", 60), 0.02), 0.02)
        self.assertGreater(g(lm.single("Contrast", 60), 0.7), 0.7)
        self.assertGreater(g(lm.single("Shadows", 80), 0.02) / 0.02, g(lm.single("Shadows", 80), 0.7) / 0.7)
        self.assertLess(g(lm.single("Highlights", -80), 0.7), 0.7)
        # Highlights − lowers the lights much more than the darks (Lightroom's own −100 moves a dark
        # grey by half a stop, so "never touches the darks" was the wrong invariant).
        self.assertLess(g(lm.single("Highlights", -80), 0.7) / 0.7, g(lm.single("Highlights", -80), 0.02) / 0.02)
        self.assertLessEqual(g(lm.single("Highlights", -80), 0.02), 0.02)
        self.assertGreater(g(lm.single("Whites", 80), 0.7), 0.7)
        self.assertLess(g(lm.single("Blacks", -80), 0.02), 0.02)
        warm = lm.flat(np.array([0.5, 0.5, 0.5]), lm.single("Temperature", 8000, AS_SHOT), AS_SHOT, r)
        self.assertGreater(warm[0] / warm[2], 1)
        # Temperature holds green (Lightroom does); the cast fades toward white through the tone curve.
        if lm.k(r, "whiteBalance", "preserveLuma", 1) < 0.5:
            self.assertAlmostEqual(float(warm[1]), 0.5)
        else:
            self.assertAlmostEqual(float(lm.luma(warm, r)), 0.5)
        shift = lambda v: float(np.log2(lm.flat(np.array([v, v, v]), lm.single("Temperature", 8000, AS_SHOT), AS_SHOT, r)[0] / v))
        self.assertGreater(shift(0.02), shift(0.5))
        self.assertGreater(shift(0.5), shift(0.95))
        mag = lm.flat(np.array([0.5, 0.5, 0.5]), lm.single("Tint", 50, AS_SHOT), AS_SHOT, r)
        self.assertLess(mag[1], mag[0])

    def test_colour(self):
        r = self.rules
        red, skin = np.array([0.5, 0.2, 0.2]), np.array([0.6, 0.35, 0.25])
        chroma = lambda c: float(np.hypot(*lm.to_oklab(c)[1:]))
        grey = lm.flat(red, lm.single("Saturation", -100), AS_SHOT, r)
        self.assertLess(np.ptp(grey), 1e-3)
        self.assertGreater(chroma(lm.flat(red, lm.single("Saturation", 30), AS_SHOT, r)), chroma(red))
        vib = chroma(lm.flat(skin, lm.single("Vibrance", 80), AS_SHOT, r)) / chroma(skin)
        sat = chroma(lm.flat(skin, lm.single("Saturation", 80), AS_SHOT, r)) / chroma(skin)
        self.assertLess(vib, sat)
        np.testing.assert_allclose(lm.from_oklab(lm.to_oklab(skin)), skin, atol=1e-6)
        bw = lm.parse_look("bw:1")
        self.assertLess(np.ptp(lm.flat(skin, bw, AS_SHOT, r)), 1e-3)

    def test_vibrance_floor_and_down_strength(self):
        r = json.loads(json.dumps(self.rules))
        r["stages"]["colour"]["coefficients"].update(vibrancePerUnit=0.008, vibranceDownPerUnit=0.012, vibranceChromaMax=0.3, vibranceFloor=0.0,
                                                     skinProtect=0.8, skinHue=30.0, skinWidth=40.0)
        f = lambda C, h, v: float(lm.chroma_factor(np.array([C]), np.array([h]), v, 0.0, False, r)[0])
        self.assertAlmostEqual(f(0.3, 200.0, 50.0), 1.0, places=12)
        r["stages"]["colour"]["coefficients"]["vibranceFloor"] = 0.25
        self.assertAlmostEqual(f(0.3, 200.0, 50.0), 1 + 50 * 0.008 * 0.25 * (1 - 0.8 * np.exp(-(170.0 / 40) ** 2)), places=12)
        self.assertAlmostEqual(f(0.5, 200.0, 50.0), f(0.3, 200.0, 50.0), places=12)
        self.assertAlmostEqual(f(0.0, 30.0, -50.0), 1 - 50 * 0.012, places=12)
        self.assertAlmostEqual(f(0.15, 30.0, -50.0), f(0.15, 200.0, -50.0), places=12)
        for v in (-100.0, -50.0, 50.0, 100.0):
            C = np.arange(0, 0.61, 0.01)
            out = C * lm.chroma_factor(C, np.full_like(C, 200.0), v, 0.0, False, r)
            self.assertTrue(np.all(np.diff(out) >= -1e-12), f"vibrance {v}")
        del r["stages"]["colour"]["coefficients"]["vibranceDownPerUnit"]
        self.assertAlmostEqual(f(0.0, 30.0, -50.0), 1 - 50 * 0.008, places=12)

    def test_vignette_and_local_stages(self):
        r = self.rules
        self.assertAlmostEqual(lm.vignette_gain(0.0, -100, r), 1.0)
        self.assertLess(lm.vignette_gain(1.0, -100, r), 1.0)
        self.assertGreater(lm.vignette_gain(1.0, 60, r), 1.0)
        for q in (0.0, 0.2, 0.5, 0.9):
            self.assertAlmostEqual(float(lm.clarity(np.array(q), np.array(q), 100, r)), q)
            self.assertAlmostEqual(float(lm.sharpen(np.array(q), np.array(q), 150, r)), q)
        self.assertGreater(float(lm.clarity(np.array(0.55), np.array(0.45), 60, r)), 0.55)
        self.assertGreater(float(lm.sharpen(np.array(0.55), np.array(0.50), 100, r)), 0.55)
        self.assertAlmostEqual(float(lm.sharpen(np.array(0.5001), np.array(0.5), 100, r)), 0.5001)

    def test_vignette_shape(self):
        """The vignette's four shape sliders (LookMathTests.testVignetteShape and the reset test)."""
        r = self.rules
        v = lambda n: r["stages"]["vignette"]["coefficients"][n]
        # at reset the look has no shape and the stage is the one it was, exactly
        for text in ("vig:-100", "vig:-37", "vig:+60", "vig:-37 vigs:50,0,50,0"):
            look = lm.parse_look(text)
            self.assertEqual(look["vigs"], lm.VIGNETTE_SHAPE)
            for d in np.arange(0.0, 1.25, 0.05):
                t = min(1.0, max(0.0, (d - (v("midpoint") - v("feather") / 2)) / v("feather")))
                want = self.ramp * 2.0 ** (look["vig"] * v("stopsPerUnit") * (t * t * (3 - 2 * t)))
                np.testing.assert_allclose(lm.flat(self.ramp, look, AS_SHOT, r, vignette_r=float(d)), want, rtol=1e-14, atol=0)
        # the shaped form meets it there
        for aspect in (1.5, 1.0, 0.6667, 2.4):
            form = lm.vignette_form(lm.VIGNETTE_SHAPE, -50, aspect, r)
            self.assertEqual((form["edge0"], form["edge1"]), (v("midpoint") - v("feather") / 2, v("midpoint") + v("feather") / 2))
            self.assertEqual(form["keep"], 0.0)
            for u, w in ((0, 0), (1, 1), (1, 0), (0, 1), (0.3, -0.8)):
                self.assertAlmostEqual(float(lm.vignette_distance(u, w, form)), float(np.hypot(u * aspect, w) / np.hypot(aspect, 1)), places=12)
        # roundness: corners at 1 for every shape; with roundAtReset 100, -50 is the frame's ellipse and -100 its rectangle
        for rnd in (-100, -75, -50, -25, 0, 40, 100):
            form = lm.vignette_form((50, rnd, 50, 0), -60, 1.5, r)
            self.assertAlmostEqual(float(lm.vignette_distance(1, -1, form)), 1.0, places=12)
            self.assertAlmostEqual(float(lm.vignette_distance(0, 0, form)), 0.0, places=12)
        if v("roundAtReset") == 100:
            ellipse, rect = lm.vignette_form((50, -50, 50, 0), -60, 1.5, r), lm.vignette_form((50, -100, 50, 0), -60, 1.5, r)
            self.assertAlmostEqual(float(lm.vignette_distance(1, 0, ellipse)), float(np.sqrt(0.5)), places=12)
            self.assertAlmostEqual(float(lm.vignette_distance(0, 1, ellipse)), float(np.sqrt(0.5)), places=12)
            self.assertGreater(float(lm.vignette_distance(1, 0, rect)), 0.9)
            self.assertEqual(lm.vignette_form((50, 100, 50, 0), -60, 1.5, r), lm.vignette_form((50, 0, 50, 0), -60, 1.5, r))
        # highlights: white spared in full at 100, only when darkening; monotonic and grey on a ramp for any shape
        white = lm.flat(np.array([1.0, 1.0, 1.0]), lm.parse_look("vig:-100 vigs:50,0,50,100"), AS_SHOT, r, vignette_r=1.0)
        np.testing.assert_allclose(white, 1.0, atol=1e-12)
        self.assertEqual(lm.vignette_form((50, 0, 50, 100), 60, 1.5, r)["keep"], 0.0)
        for text in ("vig:-100 vigs:50,0,50,100", "vig:-100 vigs:0,-100,100,60", "vig:-45 vigs:80,-50,0,30", "vig:+100 vigs:20,-30,80,100"):
            for d in (0.0, 0.4, 0.7, 1.0, 1.3):
                out = lm.flat(self.ramp, lm.parse_look(text), AS_SHOT, r, vignette_r=d)
                self.assertTrue(np.all(np.diff(out[:, 1]) >= 0), f"{text} d={d} not monotonic")
                self.assertTrue(np.all(out[:, 0] == out[:, 1]) and np.all(out[:, 1] == out[:, 2]), f"{text} d={d} tinted a grey")
        # the whole image: the corner of a flat frame is the flat chain at the corner's distance
        look = lm.parse_look("vig:-80 vigs:30,-50,70,40")
        img = np.zeros((40, 60, 3)) + np.array([0.6, 0.35, 0.25])
        out = lm.apply_image(img, look, AS_SHOT, r)
        form = lm.vignette_form(look["vigs"], -80, 60 / 40, r)
        d = float(lm.vignette_distance((0.5 - 30) / 30, (39.5 - 20) / 20, form))
        np.testing.assert_allclose(out[0, 0], lm.flat(np.array([0.6, 0.35, 0.25]), look, AS_SHOT, r, vignette_r=d, aspect=1.5), atol=1e-9)
        np.testing.assert_allclose(out[20, 30], [0.6, 0.35, 0.25], atol=1e-3)
        # the string
        s = lm.parse_look("vig:-30 vigs:40,-20,70,25")
        self.assertEqual(s["vigs"], (40.0, -20.0, 70.0, 25.0))
        self.assertTrue(lm.format_look(s).endswith("vig:-30 vigs:40,-20,70,25"))
        self.assertEqual(lm.parse_look(lm.format_look(s)), s)
        self.assertEqual(lm.parse_look("vigs:-5,-500,400,101")["vigs"], (0.0, -100.0, 100.0, 100.0))
        with self.assertRaises(ValueError):
            lm.parse_look("vigs:50,0,50")

    def test_tone_curve(self):
        """The tone curve (LookMathTests' curve tests): the page's spline, repaired, as a table."""
        r = self.rules
        f = lm.curve_spline([(0, 0), (0.5, 0.6), (1, 1)])
        np.testing.assert_allclose(f(np.array([0.0, 0.25, 0.5, 0.75, 1.0])), [0.0, 0.3125, 0.6, 0.8125, 1.0], atol=1e-12)
        line = lm.curve_spline([(0.2, 0.1), (0.8, 0.9)])
        np.testing.assert_allclose(line(np.array([0.1, 0.5, 0.95])), [0.1, 0.5, 0.9], atol=1e-12)
        # a point below its left neighbour is raised to it: the dip is a flat span
        np.testing.assert_allclose(lm.curve_spline([(0, 0), (0.3, 0.8), (0.6, 0.2), (1, 1)])(np.array([0.3, 0.45, 0.6])), 0.8, atol=1e-12)
        # whatever the points, the spline and the tables never fall
        rng = np.random.default_rng(7)
        x = np.linspace(0, 1, 2001)
        for _ in range(200):
            n = int(rng.integers(2, 11))
            xs = np.unique(np.round(rng.random(n), 4))
            if len(xs) < 2:
                continue
            pts = lambda: [(float(a), float(rng.random() * 2 - 0.5 if rng.random() < 0.15 else rng.random())) for a in xs]
            y = lm.curve_spline(pts())(x)
            self.assertTrue(np.all(np.diff(y) >= -1e-12) and y.min() >= 0 and y.max() <= 1)
            look = lm.parse_look("")
            look.update({"crv": pts(), "crvr": pts(), "crvb": pts()})
            t = lm.curve_tables(look, r)
            self.assertEqual(t.shape, (3, lm.CURVE_NODES))
            self.assertTrue(np.all(np.diff(t, axis=1) >= 0) and t.min() >= 0 and t.max() <= 1)
        # the stage: identity without a curve, the region sliders at a quarter / a half / three quarters
        np.testing.assert_allclose(lm.curve_tables(lm.parse_look(""), r)[1], np.linspace(0, 1, lm.CURVE_NODES), atol=1e-15)
        per = r["stages"]["curve"]["coefficients"]["regionPerUnit"]
        g = lambda text, p: float(lm.perceptual(lm.flat(np.array([p, p, p]) ** lm.gamma(r), lm.parse_look(text), AS_SHOT, r), r)[1])
        self.assertAlmostEqual(g("tc:0,+20,0", 0.5), 0.5 + 20 * per, delta=2e-3)
        self.assertAlmostEqual(g("tc:-30,0,0", 0.25), 0.25 - 30 * per, delta=2e-3)
        self.assertAlmostEqual(g("crv:0,0/0.5,0.6/1,1", 0.25), 0.3125, delta=2e-3)
        self.assertAlmostEqual(g("crv:0,0.1/1,0.9", 0.0), 0.1, places=9)
        self.assertAlmostEqual(g("crv:0,0.1/1,0.9", 1.1), 1.0, places=9)
        # with all-channels points set, the region sliders are a read-out (as on the page)
        a = lm.flat(self.ramp, lm.parse_look("tc:+40,-30,+10 crv:0,0/0.5,0.6/1,1"), AS_SHOT, r)
        np.testing.assert_array_equal(a, lm.flat(self.ramp, lm.parse_look("crv:0,0/0.5,0.6/1,1"), AS_SHOT, r))
        # monotonic on a grey ramp whatever the curve; grey stays grey except under a channel curve
        for text, grey in (("tc:+50,+50,+50", True), ("tc:+50,-50,+50", True), ("crv:0,1/1,0", True), ("crv:0,0/0.3,0.8/0.6,0.2/1,1", True),
                           ("crv:0,0/0.02,1/0.04,0/0.06,1/1,1", True), ("crvr:0,0.05/1,1", False),
                           ("crv:0,0/0.5,0.6/1,1 crvr:0,0/0.3,0.9/0.6,0.1/1,1 crvb:0,0.3/1,0.7", False)):
            out = lm.flat(self.ramp, lm.parse_look(text), AS_SHOT, r)
            self.assertTrue(np.all(np.diff(out, axis=0) >= -1e-12), f"{text} not monotonic")
            if grey:
                self.assertTrue(np.all(out[:, 0] == out[:, 1]) and np.all(out[:, 1] == out[:, 2]), f"{text} tinted a grey")
        # the whole image goes through the same stage
        look = lm.parse_look("tc:+20,-10,+15 crvb:0,0.1/1,0.9")
        img = np.zeros((8, 12, 3)) + np.array([0.6, 0.35, 0.25])
        np.testing.assert_allclose(lm.apply_image(img, look, AS_SHOT, r)[3, 5], lm.flat(np.array([0.6, 0.35, 0.25]), look, AS_SHOT, r), atol=1e-12)
        # the string
        s = lm.parse_look("tc:+10,0,-8 crv:0,0/0.25,0.2/0.6,0.7125/1,1 crvr:0,0.05/1,1")
        self.assertEqual(s["tc"], (10.0, 0.0, -8.0))
        self.assertEqual(s["crv"], ((0.0, 0.0), (0.25, 0.2), (0.6, 0.7125), (1.0, 1.0)))
        self.assertTrue(lm.format_look(s).endswith("vig:0 tc:+10,0,-8 crv:0,0/0.25,0.2/0.6,0.7125/1,1 crvr:0,0.05/1,1"))
        self.assertEqual(lm.parse_look(lm.format_look(s)), s)
        self.assertEqual(lm.format_look(lm.parse_look("tc:0,0,0 crv:0,0/1,1 crvg:0,0/0.5,0.5/1,1")), lm.format_look(lm.parse_look("")))
        for bad in ("tc:1,2", "crv:0,0", "crv:0,0/0.6,0.5/0.4,0.7/1,1", "crv:0,0/0.5/1,1"):
            with self.assertRaises(ValueError):
                lm.parse_look(bad)

    def test_colour_mixer(self):
        """The colour mixer (LookMathTests' mixer tests): band weights sum to 1, a grey is untouched."""
        r = self.rules
        cen = lm.mixer_centres(r)
        self.assertTrue(np.all(np.diff(cen) > 0) and len(cen) == len(lm.MIXER_COLOURS))
        h = np.arange(0, 360, 0.1)
        i, j, w = lm.mixer_band(h, cen)
        self.assertTrue(np.all((w >= 0) & (w <= 1)) and np.all(j == (i + 1) % 8))
        own = lm.mixer_band(cen, cen)
        np.testing.assert_array_equal(own[0], np.arange(8)); np.testing.assert_allclose(own[2], 0.0, atol=1e-12)
        self.assertTrue(np.max(np.abs(np.diff(np.where(i == 0, 1 - w, np.where(j == 0, w, 0.0))))) < 0.02, "red's weight is smooth across 0 degrees")
        rng = np.random.default_rng(11)
        greys = np.concatenate([self.ramp, np.array([[1e-6] * 3, [2.5] * 3, [40.0] * 3])])
        for _ in range(40):
            look = lm.parse_look("")
            for key in lm.MIXER_KEYS:
                look[key] = tuple(float(v) for v in rng.integers(-100, 101, 8))
            np.testing.assert_array_equal(lm.flat(greys, look, AS_SHOT, r), greys)
            out = lm.flat(np.array([[1.0, 0, 0], [0, 0, 1.0], [0.004, 0.002, 0.006], [1.3, 0.9, 0.2], [0, 0, 0]]), look, AS_SHOT, r)
            self.assertTrue(np.all(np.isfinite(out)) and np.all(out >= 0))
        # one band at its own centre: the hue turns, the chroma scales, the lightness moves; the opposite band stays
        k_ = lambda n: r["stages"]["mixer"]["coefficients"][n]
        col = lambda hue: lm.from_oklab(np.array([0.7, 0.08 * np.cos(np.radians(hue)), 0.08 * np.sin(np.radians(hue))]))
        for b in range(8):
            c, other = col(cen[b]), col(cen[(b + 4) % 8])
            one = lambda key, v: {**lm.parse_look(""), key: tuple(v if n == b else 0.0 for n in range(8))}
            h0, c0 = self.hue(c)
            h1, c1 = self.hue(lm.mixer(c, one("mixh", 50.0), r))
            self.assertAlmostEqual(self.hue_shift(h1, h0 + 50 * k_("hueDegreesPerUnit")), 0.0, delta=0.05)
            self.assertAlmostEqual(c1, c0, places=5)
            self.assertAlmostEqual(self.hue(lm.mixer(c, one("mixs", 40.0), r))[1], c0 * (1 + 40 * k_("saturationPerUnit")), places=5)
            up = lm.to_oklab(lm.mixer(c, one("mixl", 60.0), r))[0]
            self.assertAlmostEqual(up / 0.7 - 1, 60 * k_("luminancePerUnit") * c0 / (c0 + k_("luminanceChromaKnee")), places=5)
            for key in lm.MIXER_KEYS:
                np.testing.assert_allclose(lm.mixer(other, one(key, 100.0), r), other, atol=1e-5)
        # the whole image, and the string
        look = lm.parse_look("mixh:0,+10,0,0,0,-25,0,0 mixs:+40,0,0,-100,0,0,0,+5 mixl:0,0,0,0,0,-30,0,0")
        img = np.zeros((8, 12, 3)) + np.array([0.6, 0.35, 0.25])
        np.testing.assert_allclose(lm.apply_image(img, look, AS_SHOT, r)[3, 5], lm.flat(np.array([0.6, 0.35, 0.25]), look, AS_SHOT, r), atol=1e-12)
        self.assertTrue(lm.format_look(look).endswith("vig:0 mixh:0,+10,0,0,0,-25,0,0 mixs:+40,0,0,-100,0,0,0,+5 mixl:0,0,0,0,0,-30,0,0"))
        self.assertEqual(lm.parse_look(lm.format_look(look)), look)
        self.assertEqual(lm.format_look(lm.parse_look("mixh:0,0,0,0,0,0,0,0")), lm.format_look(lm.parse_look("")))
        self.assertEqual(lm.parse_look("mixl:-500,0,0,0,0,0,0,+101")["mixl"], (-100.0, 0, 0, 0, 0, 0, 0, 100.0))
        with self.assertRaises(ValueError):
            lm.parse_look("mixh:0,0,0")
        # every added key in one string, canonical order
        s = ("ev:+0.30 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:-30 vigs:40,-20,70,25 tc:+10,0,-8 crv:0,0/0.25,0.2/1,1 crvr:0,0.05/1,1 "
             "mixh:0,+10,0,0,0,0,0,0 mixs:0,0,0,0,0,+20,0,0 mixl:0,0,0,0,0,-15,0,0 nr:20 crop:0.1000,0.1000,0.8000,0.8000/1.50 rot:90")
        self.assertEqual(lm.format_look(lm.parse_look(s)), s)

    def test_look_string_round_trip(self):
        s = "ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0"
        self.assertEqual(lm.format_look(lm.parse_look(s)), s)
        self.assertEqual(lm.format_look(lm.parse_look("")), "ev:0.00 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:0")
        c = lm.parse_look("crop:0.1,0.2,0.5,0.6/-1.5 bw:1")
        self.assertEqual(c["crop"], (0.1, 0.2, 0.5, 0.6, -1.5))
        self.assertTrue(lm.format_look(c).endswith("bw:1 crop:0.1000,0.2000,0.5000,0.6000/-1.50"))
        with self.assertRaises(ValueError):
            lm.parse_look("exposure:1")
        # rot: a quarter turn, written last and only when set; geometry, so the maths ignores it
        t = lm.parse_look("rot:-90 crop:0.1,0.2,0.5,0.6")
        self.assertEqual(t["rot"], 270)
        self.assertTrue(lm.format_look(t).endswith("crop:0.1000,0.2000,0.5000,0.6000 rot:270"))
        self.assertEqual(lm.parse_look(lm.format_look(t)), t)
        self.assertNotIn("rot", lm.format_look(lm.parse_look("rot:360")))
        with self.assertRaises(ValueError):
            lm.parse_look("rot:45")
        np.testing.assert_allclose(lm.flat(self.ramp, lm.parse_look("rot:90"), AS_SHOT, self.rules), self.ramp, atol=1e-12)

    def test_apply_image_matches_flat_on_a_flat_patch(self):
        r = self.rules
        look = lm.parse_look("ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0")
        img = np.zeros((40, 60, 3)) + np.array([0.6, 0.35, 0.25])
        out = lm.apply_image(img, look, AS_SHOT, r)
        # A flat patch is its own photo: its tone anchor is its own luma.
        want = lm.flat(np.array([0.6, 0.35, 0.25]), look, AS_SHOT, r, anchor=lm.tone_anchor(img, r))
        np.testing.assert_allclose(out[20, 30], want, atol=1e-6)

    def test_tone_is_relative_to_the_photo(self):
        # Lightroom's Highlights −100 pulls a 0.4 pixel ~4 stops in a night scene and ~0.2 in a bright
        # one: the same pixel value, read against the photo's own brightness.
        r = self.rules
        hl = lm.single("Highlights", -100)
        px = np.array([0.4, 0.4, 0.4])
        dark = float(lm.luma(lm.flat(px, hl, AS_SHOT, r, anchor={'mean': 0.005}), r))
        bright = float(lm.luma(lm.flat(px, hl, AS_SHOT, r, anchor={'mean': 0.4}), r))
        self.assertLess(dark, bright)
        self.assertLess(bright, 0.4)
        sh = lm.single("Shadows", 100)
        px = np.array([0.1, 0.1, 0.1])
        if lm.k(r, "tone", "shadowsAdapt", 0.0) > 0:   # the Shadows mask follows the mean only when the rules say so (else the bright end, below)
            self.assertGreater(float(lm.luma(lm.flat(px, sh, AS_SHOT, r, anchor={'mean': 0.4}), r)), float(lm.luma(lm.flat(px, sh, AS_SHOT, r, anchor={'mean': 0.02}), r)))
        self.assertGreater(lm.k(r, "tone", "shadowsAdapt", 0.0) + lm.k(r, "tone", "shadowsHighAdapt", 0.0), 0, "Shadows must be read against the photo one way or the other")
        flat = lm.tone_anchor(np.zeros((4, 4, 3)) + 0.18, r)
        self.assertAlmostEqual(flat["mean"], 0.18); self.assertAlmostEqual(flat["spread"], 0.0); self.assertEqual(flat["bright"], 0.0)
        self.assertEqual(lm.tone_anchor(np.zeros((4, 4, 3)), r)["mean"], 1e-3)
        two = lm.tone_anchor(np.array([[[0.1] * 3, [0.8] * 3]]), r)
        self.assertAlmostEqual(two["mean"], (0.1 * 0.8) ** 0.5); self.assertAlmostEqual(two["spread"], 1.5); self.assertEqual(two["bright"], 0.5)
        # the bright end: the 95th percentile of luma (LookMath.toneAnchor interpolates the same way)
        self.assertAlmostEqual(flat["high"], 0.18); self.assertAlmostEqual(two["high"], 0.1 + 0.7 * 0.95)
        ramp = lm.tone_anchor(np.repeat(np.linspace(0, 1, 101)[None, :, None], 3, axis=2), r)
        self.assertAlmostEqual(ramp["high"], 0.95)
        # the Shadows mask sits against the bright end; a missing one changes nothing
        self.assertAlmostEqual(lm.tone_normalisers({"mean": 0.18}, r)[0], lm.tone_normalisers({"mean": 0.18, "high": 2.0 ** lm.k(r, "tone", "highCentre", 0.0)}, r)[0])
        if lm.k(r, "tone", "shadowsHighAdapt", 0.0) > 0:
            self.assertGreater(float(lm.luma(lm.flat(px, sh, AS_SHOT, r, anchor={'mean': 0.18, 'high': 1.0}), r)),
                               float(lm.luma(lm.flat(px, sh, AS_SHOT, r, anchor={'mean': 0.18, 'high': 0.3}), r)))
        # strengths: at the rules' centre the factor is 1; kept within [0.25, 4]
        t = lambda n, d: lm.k(r, "tone", n, d)
        centre = {"mean": 2.0 ** t("meanCentre", np.log2(0.18)), "spread": t("spreadCentre", 1.5), "bright": t("brightCentre", 0.2)}
        self.assertAlmostEqual(lm.tone_normalisers(centre, r)[2], 1.0); self.assertAlmostEqual(lm.tone_normalisers(centre, r)[3], 1.0)
        wild = lm.tone_normalisers({"mean": 0.001, "spread": 9.0, "bright": 1.0}, r)
        self.assertLessEqual(wild[2], 4.0); self.assertLessEqual(wild[3], 4.0)

    def test_check_against_a_consistent_dump(self):
        r = self.rules
        look = "ev:-0.50 con:+30 sat:+20 wh:+20 bl:-10 hl:-30 sh:+30"
        patches = []
        for c in ([0.1, 0.1, 0.1], [0.5, 0.2, 0.2], [0.9, 0.9, 0.9]):
            v = lm.flat(np.array(c), lm.parse_look(look), AS_SHOT, r)
            patches.append({"in": c, "graph": list(v + 0.001), "math": list(v)})
        dump = {"look": look, "asShot": {"kelvin": AS_SHOT[0], "tint": AS_SHOT[1]}, "rules": {s: r["stages"][s]["coefficients"] for s in r["stages"]},
                "perceptualGamma": r["perceptualGamma"], "order": r["order"], "patches": patches}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(dump, f)
        worst, rows = lm.check(f.name)
        os.unlink(f.name)
        self.assertLess(worst, 0.002)
        self.assertEqual(len(rows), 3)


    # ---- outputTransform (the display mapper) ----

    def sigmoid_rules(self):
        r = json.loads(json.dumps(self.rules))
        r["stages"]["outputTransform"]["mapper"] = "sigmoid"
        return r

    @staticmethod
    def hue(rgb):
        lab = lm.to_oklab(np.asarray(rgb, dtype=np.float64))
        return float(np.degrees(np.arctan2(lab[2], lab[1]))), float(np.hypot(lab[1], lab[2]))

    @staticmethod
    def hue_shift(a, b):
        d = abs(a - b) % 360.0
        return 360.0 - d if d > 180.0 else d

    def test_shipped_mapper_is_the_clamp(self):
        self.assertEqual(lm.mapper(self.rules), "clamp")
        np.testing.assert_allclose(lm.output_transform([1.5, 0.5, -0.1], self.rules), [1.0, 0.5, 0.0])
        self.assertEqual(lm.mapper(self.sigmoid_rules()), "sigmoid")
        self.assertEqual(lm.mapper({"stages": {}}), "clamp")

    def test_mapper_matrices(self):
        for inset, rotate in ((0.2, 0.0), (0.2, 7.0), (0.35, -4.0), (0.0, 0.0)):
            m, o = lm.mapper_matrices(inset, rotate)
            np.testing.assert_allclose(o @ m, np.eye(3), atol=1e-12)
            np.testing.assert_allclose(m.sum(axis=1), 1.0, atol=1e-12)
            np.testing.assert_allclose(o.sum(axis=1), 1.0, atol=1e-12)

    def test_mapper_identity_below_the_knee(self):
        r = self.sigmoid_rules()
        c = np.array([[0, 0, 0], [0.02] * 3, [0.18] * 3, [0.6] * 3, [0.6, 0.35, 0.25], [0.5, 0.2, 0.2], [0.15, 0.2, 0.6], [0.004, 0.002, 0.006]])
        np.testing.assert_allclose(lm.output_transform(c, r), c, atol=1e-12)

    def test_mapper_rolls_off_smoothly(self):
        r = self.sigmoid_rules()
        knee_ev, max_ev = lm.display_mapper(r)[:2]
        g = np.linspace(0, 20, 4001)
        out = lm.output_transform(np.stack([g] * 3, axis=-1), r)
        self.assertTrue(np.all(np.diff(out[:, 1]) >= 0) and np.all(out <= 1.0))
        self.assertLess(float(np.max(np.abs(out[:, 0] - out[:, 2]))), 1e-9)
        knee, top, h = lm.GREY * 2.0 ** knee_ev, lm.GREY * 2.0 ** max_ev, 1e-5
        f = lambda x: float(lm.shoulder(x, knee_ev, max_ev))
        self.assertAlmostEqual((f(knee) - f(knee - h)) / h, 1.0, places=6)
        self.assertAlmostEqual((f(knee + h) - f(knee)) / h, 1.0, places=3)
        self.assertAlmostEqual(f(top), 1.0); self.assertAlmostEqual(f(top * 8), 1.0)
        self.assertLess(f(4.0), 1.0)
        self.assertTrue(0.85 < f(1.0) < 0.95)
        x = knee * 1.01 ** np.arange(0, int(np.log(top / knee) / np.log(1.01)))
        slopes = (lm.shoulder(x * 1.01, knee_ev, max_ev) - lm.shoulder(x, knee_ev, max_ev)) / (x * 0.01)
        self.assertTrue(np.all(np.diff(slopes) <= 1e-9), "the slope only falls from the knee up")

    def test_mapper_keeps_hue_and_fades_to_white(self):
        r = self.sigmoid_rules()
        for base in ([1, 0.5, 0.05], [1, 0.08, 0.03], [0.2, 0.4, 1], [0.2, 1, 0.1]):
            base = np.array(base, dtype=np.float64)
            h0 = self.hue(base * 0.5)[0]
            chroma = np.inf
            for gain in (1, 2, 4, 8, 16):
                h, C = self.hue(lm.output_transform(base * gain, r))
                if gain <= 4:
                    self.assertLess(self.hue_shift(h, h0), 10.0, f"{base} x {gain}")
                self.assertLessEqual(C, chroma + 1e-9, f"{base} x {gain} gained colour")
                chroma = C
            self.assertLess(chroma, 0.02, f"{base} x 16 is nearly white")
            self.assertGreater(float(lm.output_transform(base * 64, r).min()), 0.98)
        orange, h0 = np.array([4, 2, 0.2]), self.hue([0.5, 0.25, 0.025])[0]
        self.assertGreater(self.hue_shift(self.hue(lm.output_transform(orange, self.rules))[0], h0), 20.0, "the clamp turns it yellow")
        self.assertLess(self.hue_shift(self.hue(lm.output_transform(orange, r))[0], h0), 8.0)
        self.assertGreater(float(lm.output_transform([30.0, 0, 0], r)[1]), 0.95)

    def test_mapper_is_finite(self):
        r = self.sigmoid_rules()
        with np.errstate(all="ignore"):
            for v in (0.0, -0.5, 1e-30, 1e6, 1e30, sys.float_info.max, np.inf):
                for c in ([v, v, v], [v, 1, 0], [0, 0.3, v]):
                    out = lm.output_transform(np.array(c, dtype=np.float64), r)
                    self.assertTrue(np.all(np.isfinite(out)) and np.all(out >= 0) and np.all(out <= 1), f"{c} -> {out}")
        np.testing.assert_allclose(lm.output_transform([np.inf] * 3, r), 1.0)

    def test_check_covers_the_mapper(self):
        r = self.sigmoid_rules()
        display = []
        for c in ([0.18] * 3, [4, 2, 0.2], [30, 0, 0]):
            v = lm.output_transform(np.array(c, dtype=np.float64), r)
            display.append({"in": c, "graph": list(v + 0.001), "math": list(v)})
        dump = {"look": "", "asShot": {"kelvin": AS_SHOT[0], "tint": AS_SHOT[1]}, "rules": {s: r["stages"][s]["coefficients"] for s in r["stages"]},
                "perceptualGamma": r["perceptualGamma"], "order": r["order"], "patches": [], "mapper": "sigmoid", "display": display}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(dump, f)
        worst, rows = lm.check(f.name)
        dump["mapper"] = "clamp"
        with open(f.name, "w") as g:
            json.dump(dump, g)
        clamped, _ = lm.check(f.name)
        os.unlink(f.name)
        self.assertLess(worst, 0.002)
        self.assertEqual(len(rows), 3)
        self.assertGreater(clamped, 0.1, "a dump whose mapper differs from the values fails the check")


if __name__ == "__main__":
    unittest.main()
