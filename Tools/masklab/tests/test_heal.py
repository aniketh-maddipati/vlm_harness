import os, sys, tempfile, unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import heal_score, make_holes  # noqa: E402

H, W, N = 72, 128, 8


def scene(n):
    """A textured background that pans a pixel a frame."""
    y, x = np.mgrid[0:H, 0:W]
    g = 128 + 60 * np.sin((x + n) / 5.0) * np.cos(y / 7.0)
    return np.stack([g, g * 0.8, 255 - g], -1).clip(0, 255).astype(np.uint8)


def save(folder, n, a):
    os.makedirs(folder, exist_ok=True)
    Image.fromarray(a).save(os.path.join(folder, f"{n:05d}.png"))


class HealTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); r = self.tmp.name
        self.truth, self.holes = os.path.join(r, "truth"), os.path.join(r, "holes")
        for n in range(N):
            save(self.truth, n, scene(n))
        self.assertEqual(make_holes.make(self.truth, self.holes, area=0.08, seed="t"), N)
        self.root = r

    def tearDown(self):
        self.tmp.cleanup()

    def healed(self, name, fill):
        d = os.path.join(self.root, name)
        for n in range(N):
            hole = np.asarray(Image.open(os.path.join(self.holes, f"{n:05d}.png"))) >= 128
            out = scene(n).copy(); out[hole] = fill(n, hole)[hole]
            save(d, n, out)
        return d

    def test_holes_are_repeatable_moving_and_about_the_area(self):
        again = os.path.join(self.root, "again")
        make_holes.make(self.truth, again, area=0.08, seed="t")
        a = [np.asarray(Image.open(os.path.join(self.holes, f"{n:05d}.png"))) >= 128 for n in range(N)]
        b = np.asarray(Image.open(os.path.join(again, "00000.png"))) >= 128
        self.assertTrue((a[0] == b).all(), "the same seed, the same hole")
        self.assertTrue(0.02 < a[0].mean() < 0.3, a[0].mean())
        self.assertFalse((a[0] == a[-1]).all(), "it moves")
        still = os.path.join(self.root, "still")
        make_holes.make(self.truth, still, seed="t", still=True)
        s = [np.asarray(Image.open(os.path.join(still, f"{n:05d}.png"))) for n in (0, N - 1)]
        self.assertTrue((s[0] == s[1]).all(), "--still stays put")

    def test_a_perfect_fill_scores_perfect(self):
        r = heal_score.score(self.healed("perfect", lambda n, h: scene(n)), self.holes, self.truth, self.truth)
        self.assertEqual(r["frames"], N)
        self.assertGreaterEqual(r["psnr"], 99); self.assertAlmostEqual(r["ssim"], 1.0, places=6)
        self.assertAlmostEqual(r["leak"], 0.0)
        self.assertLess(abs(r["seam"] - 1), 0.5)

    def test_a_grey_fill_scores_badly_with_a_seam(self):
        grey = self.healed("grey", lambda n, h: np.full((H, W, 3), 128, np.uint8))
        r = heal_score.score(grey, self.holes, self.truth)
        self.assertLess(r["psnr"], 25); self.assertLess(r["ssim"], 0.9)
        perfect = heal_score.score(self.healed("perfect", lambda n, h: scene(n)), self.holes, self.truth)
        self.assertNotAlmostEqual(r["seam"], perfect["seam"], places=1)

    def test_a_boiling_fill_flickers(self):
        rng = np.random.default_rng(0)
        boil = self.healed("boil", lambda n, h: rng.integers(0, 255, (H, W, 3), dtype=np.uint8))
        steady = self.healed("steady", lambda n, h: scene(0))
        rb, rs = heal_score.score(boil, self.holes), heal_score.score(steady, self.holes)
        self.assertGreater(rb["flicker"], 3 * rs["flicker"])
        self.assertIsNone(rb["psnr"], "no truth, no PSNR")

    def test_a_fill_that_touches_the_rest_leaks(self):
        d = os.path.join(self.root, "leaky")
        for n in range(N):
            save(d, n, (scene(n).astype(int) + 20).clip(0, 255).astype(np.uint8))
        self.assertGreater(heal_score.score(d, self.holes, self.truth, self.truth)["leak"], 10)


if __name__ == "__main__":
    unittest.main()
