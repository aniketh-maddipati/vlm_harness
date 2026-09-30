import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import delta_e  # noqa: E402


class DeltaETests(unittest.TestCase):
    def test_sharma_reference_pairs(self):
        self.assertTrue(delta_e.selftest())

    def test_lab_whites_and_greys(self):
        for space in ("srgb", "prophoto"):
            lab = delta_e.to_lab(np.array([[[1.0, 1.0, 1.0]], [[0.0, 0.0, 0.0]], [[0.5, 0.5, 0.5]]]), space)
            self.assertAlmostEqual(lab[0, 0, 0], 100, places=1)
            self.assertAlmostEqual(lab[1, 0, 0], 0, places=3)
            self.assertLess(abs(lab[2, 0, 1]) + abs(lab[2, 0, 2]), 0.05, f"{space} grey has chroma")

    def test_prophoto_transfer_round_trips(self):
        x = np.linspace(0, 1, 101)
        np.testing.assert_allclose(delta_e.decode_prophoto(delta_e.encode_prophoto(x)), x, atol=1e-9)
        np.testing.assert_allclose(delta_e.decode_srgb(delta_e.encode_srgb(x)), x, atol=1e-9)

    def test_working_linear_of_prophoto_grey_is_grey(self):
        lin = delta_e.to_working_linear(np.array([[[0.5, 0.5, 0.5]]]), "prophoto")
        self.assertLess(np.ptp(lin), 0.01)

    def test_regions_and_sample(self):
        h, w = 40, 60
        ramp = np.tile(np.linspace(0, 1, w)[None, :, None], (h, 1, 3))
        m = delta_e.measure(ramp, np.clip(ramp * 1.05, 0, 1), "srgb", sample=500)
        self.assertEqual(m["sample"].shape, (500,))
        self.assertEqual(m["map"].shape, (h, w))
        self.assertGreater(m["shadows"]["n"], 0)
        self.assertGreater(m["highlights"]["n"], 0)
        self.assertEqual(m["skin"]["n"], 0, "a grey ramp has no skin")
        self.assertEqual(len(m["byL"]), 10)
        skin = np.zeros((8, 8, 3)) + np.array([0.85, 0.62, 0.52])
        m2 = delta_e.measure(skin, skin * 0.98, "srgb")
        self.assertEqual(m2["skin"]["n"], 64)

    def test_align_tolerates_a_pixel_and_refuses_more(self):
        ref = np.zeros((100, 150, 3))
        self.assertEqual(delta_e.align(ref, np.zeros((101, 150, 3))).shape, ref.shape)
        with self.assertRaises(ValueError):
            delta_e.align(ref, np.zeros((130, 150, 3)))

    def test_files_and_heatmap(self):
        import tifffile
        with tempfile.TemporaryDirectory() as d:
            ramp = np.tile(np.linspace(0, 1, 64)[None, :, None], (16, 1, 3))
            a = os.path.join(d, "a.tif"); b = os.path.join(d, "b.tif"); png = os.path.join(d, "h.png")
            tifffile.imwrite(a, (ramp * 65535).astype(np.uint16))
            tifffile.imwrite(b, (np.clip(ramp * 1.1, 0, 1) * 65535).astype(np.uint16))
            r = delta_e.measure_files(a, b, "prophoto")
            self.assertGreater(r["all"]["median"], 0.5)
            self.assertEqual(r["space"], "prophoto")
            delta_e.heatmap(r["map"], png)
            self.assertTrue(os.path.getsize(png) > 0)
            self.assertNotIn("map", delta_e.to_json(r))
            rgb, space = delta_e.read_rgb01(a)
            self.assertEqual(rgb.shape, (16, 64, 3))
            self.assertIsNone(space, "no ICC profile → unknown space")

    def test_space_from_icc(self):
        self.assertEqual(delta_e.space_from_icc(b"....ProPhoto RGB...."), "prophoto")
        self.assertEqual(delta_e.space_from_icc(b"....ROMM RGB...."), "prophoto")
        self.assertEqual(delta_e.space_from_icc(b"....sRGB IEC61966-2.1...."), "srgb")
        self.assertIsNone(delta_e.space_from_icc(b"nothing"))


if __name__ == "__main__":
    unittest.main()
