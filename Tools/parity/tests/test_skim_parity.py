import os
import shutil
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import skim_parity  # noqa: E402


class MappingTests(unittest.TestCase):
    def test_white_balance_moves(self):
        self.assertGreater(skim_parity.wb_delta("Temperature", 10000, {"Temperature": 5500}), 0, "a higher Kelvin is warmer")
        self.assertLess(skim_parity.wb_delta("Temperature", 3200, {"Temperature": 5500}), 0)
        self.assertEqual(skim_parity.wb_delta("Tint", 20, {"Tint": -5}), 25)


@unittest.skipUnless(shutil.which("node"), "needs node")
class SkimRenderTests(unittest.TestCase):
    def test_flat_look_is_identity_and_moves_move(self):
        img = np.random.default_rng(0).uniform(0.05, 0.95, (8, 12, 3))
        flat, ev, warm = skim_parity.skim_render(img, [{}, {"ev": 1}, {"temp": 60}])
        np.testing.assert_allclose(flat, img, atol=1e-5)
        self.assertGreater(ev.mean(), img.mean() + 0.05)
        self.assertGreater((warm[..., 0] - warm[..., 2]).mean(), (img[..., 0] - img[..., 2]).mean())


if __name__ == "__main__":
    unittest.main()
