import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import sweep_photos as sp  # noqa: E402


def solid(r, g, b, h=64, w=96):
    return np.tile(np.array([r, g, b], dtype=np.float64), (h, w, 1))


def grid(h=96, w=96, step=12):
    im = np.full((h, w, 3), 0.8)
    im[::step, :, :] = 0.1
    im[:, ::step, :] = 0.1
    return im


def photo(stem, pool="dv", **m):
    base = sp.measures(solid(0.45, 0.45, 0.45))
    return {"stem": stem, "pool": pool, "raw": None, **{**base, **m}}


class MeasureTests(unittest.TestCase):
    def test_hue_shares_land_in_lightrooms_bands(self):
        for rgb, band in (((0.8, 0.1, 0.1), "Red"), ((0.9, 0.5, 0.1), "Orange"), ((0.1, 0.7, 0.1), "Green"),
                          ((0.1, 0.7, 0.7), "Aqua"), ((0.1, 0.3, 0.8), "Blue"), ((0.5, 0.1, 0.8), "Purple"), ((0.8, 0.1, 0.5), "Magenta")):
            m = sp.measures(solid(*rgb))
            self.assertAlmostEqual(m["hue"][band], 1.0, msg=band)
        grey = sp.measures(solid(0.5, 0.5, 0.5))
        self.assertEqual(sum(grey["hue"].values()), 0)
        self.assertEqual(grey["detail"], 0)

    def test_lines_and_entropy(self):
        self.assertGreater(sp.measures(grid())["lines"], 0.5)
        stripes = np.full((96, 96, 3), 0.8)
        stripes[::12, :, :] = 0.1   # horizontal lines only
        self.assertLess(sp.measures(stripes)["lines"], 0.1)
        two = np.concatenate([solid(0.8, 0.1, 0.1), solid(0.1, 0.3, 0.8)], axis=1)
        self.assertAlmostEqual(sp.measures(two)["hueEntropy"], np.log(2) / np.log(8), places=3)


class PickTests(unittest.TestCase):
    def test_spread_takes_the_ends_and_evenly_between(self):
        items = [{"stem": f"{i:03d}", "v": i} for i in range(101)]
        self.assertEqual([it["v"] for it in sp.spread(items, lambda it: it["v"], 5)], [0, 25, 50, 75, 100])
        self.assertEqual(len(sp.spread(items[:3], lambda it: it["v"], 5)), 3)

    def test_every_sweep_gets_its_list_and_is_deterministic(self):
        rnd = np.random.default_rng(1)
        photos = []
        for i in range(60):
            hue = {name: float(rnd.uniform(0, 0.3)) for name, _ in sp.BANDS}
            photos.append(photo(f"D{i:03d}", luma=float(rnd.uniform(0.1, 0.8)), detail=float(rnd.uniform(0, 0.1)),
                                lines=float(rnd.uniform(0, 0.3)), hue=hue, hueEntropy=float(rnd.uniform(0, 1))))
        for i in range(10):
            photos.append(photo(f"P{i:03d}", pool="portraits", luma=float(rnd.uniform(0.2, 0.7)), detail=float(rnd.uniform(0, 0.1))))
        picks = sp.pick(photos)
        self.assertEqual(picks, sp.pick(list(reversed(photos))))
        sizes = {k: len(v) for k, v in picks.items()}
        self.assertEqual(sizes["sweep04"], 40)
        self.assertEqual(sizes["sweep06"], 20)
        self.assertEqual(sizes["sweep11"], 30)
        self.assertEqual(sizes["sweep12"], 10)
        self.assertEqual(sum(s.startswith("P") for s, _ in picks["sweep06"]), 5)
        self.assertEqual(sum(s.startswith("P") for s, _ in picks["sweep08"]), 2)
        self.assertTrue(all(s.startswith("D") for s, _ in picks["sweep04"] + picks["sweep07"]))
        for name, _ in sp.BANDS:
            chosen = picks[f"sweep05-{name.lower()}"]
            self.assertEqual(len(chosen), 4)
            self.assertEqual([v for _, v in chosen], sorted((v for _, v in chosen), reverse=True))
        self.assertNotIn("sweep09", picks)   # the ISO ladder is shot, not picked

    def test_lists_and_links_are_written(self):
        with tempfile.TemporaryDirectory() as d:
            raw = os.path.join(d, "A.ARW")
            open(raw, "wb").close()
            photos = [photo("A", raw=raw), photo("B")]
            sp.write(os.path.join(d, "out"), photos, {"sweep04": [("A", 0.1), ("B", 0.2)]}, [{"stem": "C", "why": "cropped"}])
            with open(os.path.join(d, "out", "sweep04.txt")) as f:
                self.assertEqual(f.read(), "A.ARW\nB.ARW\n")
            self.assertEqual(os.listdir(os.path.join(d, "out", "sweep04")), ["A.ARW"])
            self.assertEqual(os.readlink(os.path.join(d, "out", "sweep04", "A.ARW")), raw)


if __name__ == "__main__":
    unittest.main()
