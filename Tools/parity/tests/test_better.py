import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import better  # noqa: E402
import delta_e  # noqa: E402


def ramp(h=64, w=256):
    """A grey ramp, 0 → 1 left to right, as sRGB-encoded values."""
    return np.tile(np.linspace(0.0, 1.0, w)[None, :, None], (h, 1, 3))


def gamma(img, g):
    return np.clip(img, 0, 1) ** g


def scene(h=96, w=192, seed=0):
    """Blocks of skin, sky and grey on a mid background, with hard edges between them."""
    rng = np.random.default_rng(seed)
    img = np.full((h, w, 3), 0.45)
    img[:40, :] = [0.45, 0.62, 0.86]          # sky, upper part of the frame
    img[50:90, 20:80] = [0.85, 0.62, 0.50]    # skin
    img[50:90, 110:170] = [0.25, 0.25, 0.25]  # dark grey (neutral)
    img[60:80, 120:160] = [0.80, 0.80, 0.80]  # light grey inside it: strong edges
    return np.clip(img + rng.normal(0, 0.002, img.shape), 0, 1)


def unsharp(img, r=3, amount=0.8):
    out = np.empty_like(img)
    for c in range(3):
        out[..., c] = img[..., c] + amount * (img[..., c] - better._box(img[..., c], r))
    return np.clip(out, 0, 1)


class ColourTests(unittest.TestCase):
    def test_oklab_white_and_grey(self):
        ok = better.oklab(np.array([[[1.0, 1.0, 1.0], [0.5, 0.5, 0.5]]]), "srgb")
        self.assertAlmostEqual(ok[0, 0, 0], 1.0, places=2)
        self.assertLess(np.abs(ok[0, :, 1:]).max(), 2e-3)
        okp = better.oklab(np.array([[[0.5, 0.5, 0.5]]]), "prophoto")
        self.assertLess(np.abs(okp[0, 0, 1:]).max(), 2e-3, "ProPhoto grey stays grey after D50 → D65")

    def test_masks_find_their_blocks(self):
        m = better.masks(delta_e.to_lab(scene(), "srgb"))
        self.assertTrue(m["sky"][10, 50] and m["skin"][70, 50] and m["neutral"][70, 140])
        self.assertFalse(m["skin"][10, 50] or m["sky"][70, 50])


class IsolationTests(unittest.TestCase):
    def test_highlights_only_change_scores_low_outside(self):
        base = ramp()
        out = base.copy()
        bright = delta_e.to_lab(base, "srgb")[..., 0] > 70
        out[bright] = out[bright] * 0.85
        iso = better.isolation(delta_e.to_lab(base, "srgb"), delta_e.to_lab(out, "srgb"), "Highlights")
        self.assertLess(iso["outside"], 0.05)
        self.assertGreater(iso["inside"], 1.0)
        self.assertLess(iso["leak"], 0.05)

    def test_a_global_change_leaks(self):
        base = ramp()
        iso = better.isolation(delta_e.to_lab(base, "srgb"), delta_e.to_lab(gamma(base, 0.8), "srgb"), "Highlights")
        self.assertGreater(iso["outside"], 1.0)
        self.assertGreater(iso["leak"], 0.5)

    def test_no_band_sliders(self):
        lab = delta_e.to_lab(ramp(), "srgb")
        self.assertIsNone(better.isolation(lab, lab, "Exposure"))


class HueTests(unittest.TestCase):
    def test_brightening_keeps_hue_rotation_drifts(self):
        base = scene()
        ok0 = better.oklab(base, "srgb")
        m = better.masks(delta_e.to_lab(base, "srgb"))
        same = better.hue_drift(ok0, better.oklab(gamma(base, 0.9), "srgb"), m)
        self.assertLess(same["skin"]["abs"], 2.0)
        self.assertLess(same["sky"]["abs"], 2.0)
        self.assertLess(abs(same["neutral"]["chroma"]), 0.1)
        warm = base * np.array([1.08, 1.0, 0.90])  # a warming cast: skin and sky hue move, greys gain chroma
        drift = better.hue_drift(ok0, better.oklab(np.clip(warm, 0, 1), "srgb"), m)
        self.assertGreater(drift["sky"]["abs"], 2.0)
        self.assertGreater(drift["neutral"]["chroma"], 1.0)


class StepTests(unittest.TestCase):
    def test_linear_steps_are_even_and_bunched_steps_are_not(self):
        base = ramp()
        lab = lambda img: delta_e.to_lab(img, "srgb")  # noqa: E731
        even = [(v, lab(np.clip(base + v * 0.002, 0, 1))) for v in (0, 25, 50, 75)]
        self.assertLess(better.evenness(even)["cv"], 0.1)
        bunched = [(v, lab(np.clip(base + 0.002 * 100 * (v / 100) ** 3, 0, 1))) for v in (0, 25, 50, 75)]
        self.assertGreater(better.evenness(bunched)["cv"], 0.5)

    def test_one_step_has_no_cv(self):
        lab = delta_e.to_lab(ramp(), "srgb")
        self.assertIsNone(better.evenness([(0, lab), (50, lab)])["cv"])


class ClipTests(unittest.TestCase):
    def test_added_clipping(self):
        base = ramp() * 0.9
        s = better.score_sweep(base, {50.0: np.clip(base * 1.3, 0, 1), 100.0: np.clip(base * 1.6, 0, 1)}, "Whites")
        self.assertAlmostEqual(s["positions"][50.0]["clipAdded"]["high"], 100 * (1 - 1 / (0.9 * 1.3)), delta=2.0)
        self.assertEqual(s["clipMid"], s["positions"][50.0]["clipAdded"]["high"] + s["positions"][50.0]["clipAdded"]["low"],
                         "100 is the slider's end; clip mid is the worst short of it")
        none = better.score_sweep(base, {50.0: gamma(base, 0.9)}, "Shadows")
        self.assertLess(none["clipMid"], 0.5)


class HaloTests(unittest.TestCase):
    def test_global_curve_has_no_halo_unsharp_does(self):
        base = scene()
        L0 = delta_e.to_lab(base, "srgb")[..., 0]
        flat = better.halo(L0, delta_e.to_lab(gamma(base, 0.8), "srgb")[..., 0])
        sharp = better.halo(L0, delta_e.to_lab(unsharp(base), "srgb")[..., 0])
        self.assertLess(abs(flat["overshoot"]), 0.5)
        self.assertGreater(sharp["overshoot"], 1.0)

    def test_no_edges_no_score(self):
        flat = np.full((64, 64), 50.0)
        self.assertIsNone(better.halo(flat, flat + 1))


class FolderTests(unittest.TestCase):
    def test_folder_run_end_to_end(self):
        from PIL import Image
        base = scene()
        with tempfile.TemporaryDirectory() as d:
            def save(name, img):
                Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, name))
            save("P1__base.png", base)
            save("P1__Clarity__50.lumina.png", unsharp(base, amount=0.5))
            save("P1__Clarity__100.png", unsharp(base, amount=1.0))
            save("P1__Highlights__-50.png", np.where(base > 0.7, base * 0.9, base))
            save("._P1__base.png", base)  # AppleDouble stub: ignored
            idx = better.index_folders([d])
            self.assertEqual(sorted(idx["P1"]["sweeps"]), ["Clarity", "Highlights"])
            self.assertEqual(sorted(idx["P1"]["sweeps"]["Clarity"]), [50.0, 100.0])
            out = os.path.join(d, "o.json")
            md = os.path.join(d, "o.md")
            better.main([d, "--px", "0", "--json", out, "--md", md, "--label", "t"])
            import json
            s = json.load(open(out))["summary"]
            self.assertGreater(s["Clarity"]["halo"], 1.0)
            self.assertIsNotNone(s["Clarity"]["evenness"])
            self.assertLess(s["Highlights"]["isolation"], 0.5)
            self.assertIn("| Clarity |", open(md).read())

    def test_a_base_exported_at_another_size_scores_no_change(self):
        """Lightroom CC's base export is 1968 px where its singles are 2048: the same picture at two
        sizes must score as no change, not as a halo or a leak."""
        from PIL import Image
        big = scene(h=192, w=384)
        small = np.asarray(Image.fromarray((big * 255 + 0.5).astype(np.uint8)).resize((369, 185), Image.LANCZOS)) / 255.0
        with tempfile.TemporaryDirectory() as d:
            Image.fromarray((small * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, "P__base.png"))
            Image.fromarray((big * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, "P__Highlights__-50.png"))
            s = better.summarise(better.run(better.index_folders([d]), px=160))["Highlights"]
            self.assertLess(abs(s["halo"]), 0.3)
            self.assertLess(s["isolation"], 0.5)


if __name__ == "__main__":
    unittest.main()
