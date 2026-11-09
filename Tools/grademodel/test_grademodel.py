"""Synthetic tests for the grade model eval (Linux too): S-Log3 round trip, ΔE2000 on Sharma's pairs, the LUT
recovering a known look, ⇧E as the page computes it, and the adopt rule."""
import json
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gm  # noqa: E402
import compare  # noqa: E402

import importlib.util  # noqa: E402
_spec = importlib.util.spec_from_file_location('baseline', os.path.join(HERE, 'candidates', 'baseline.py'))
baseline = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(baseline)


class Maths(unittest.TestCase):
    def test_slog3_round_trip(self):
        x = np.array([-0.005, 0.0, 0.005, 0.01125, 0.18, 1.0, 10.0])
        self.assertTrue(np.allclose(gm.s3_lin(gm.lin_s3(x)), x, atol=1e-9))
        self.assertAlmostEqual(float(gm.lin_s3(0.18)) * 1023, 420.0, places=6)  # 18 % grey at code 420

    def test_de2000_sharma(self):
        # Sharma, Wu & Dalal (2005), pairs 1, 7, 13, 25, 17 (as Tools/lookeval)
        a = np.array([[50, 2.6772, -79.7751], [50, 0, 0], [50, 2.49, -0.001], [60.2574, -34.0099, 36.2677], [50, 2.5, 0]])
        b = np.array([[50, 0, -82.7485], [50, -1, 2], [50, -2.49, 0.0009], [60.4626, -34.1751, 39.4387], [73, 25, -18]])
        self.assertTrue(np.allclose(gm.de2000(a, b), [2.0425, 2.3669, 7.1792, 1.2644, 27.1492], atol=1e-4))

    def test_lut_recovers_a_smooth_look(self):
        r = np.random.default_rng(0)
        X = r.random((20000, 3))
        Y = np.clip(X ** 0.8 @ np.array([[0.9, 0.1, 0], [0.05, 0.9, 0.05], [0, 0.1, 0.9]]).T, 0, 1)
        lut = gm.fit_lut(X, Y)
        Xt = r.random((2000, 3))
        Yt = np.clip(Xt ** 0.8 @ np.array([[0.9, 0.1, 0], [0.05, 0.9, 0.05], [0, 0.1, 0.9]]).T, 0, 1)
        self.assertLess(float(np.median(gm.de(gm.apply_lut(lut, Xt), Yt))), 0.5)


class ShiftE(unittest.TestCase):
    def test_matches_the_shoot_median_with_the_clamp(self):
        f = lambda v: [np.full((100, 3), v)]  # noqa: E731
        g = baseline.balance({'a': f(0.18), 'b': f(0.09), 'c': f(0.36), 'd': f(0.01)}, 'slog3')
        # upper median of (0.01, 0.09, 0.18, 0.36) is 0.18
        self.assertEqual(g['a'][0], 0.0)
        self.assertEqual(g['b'][0], 1.0)
        self.assertEqual(g['c'][0], -1.0)
        self.assertEqual(g['d'][0], 1.0)  # clamped


class Rule(unittest.TestCase):
    def summary(self, exp, look, held_de=5.0, held_exp=0.6):
        s = {'exposure_adacg.dev': {'median': exp}, 'look_composite.dev': {'median': look},
             'exposure_adacg.held': {'median': held_exp}}
        for n in ('uday', 'sparks', 'tos', 'pst50', 'pst50_transfer'):
            s[n + '.held'] = {'median': held_de, 'p95': held_de * 2}
        return {'summary': s}

    def crit(self):
        return json.load(open(os.path.join(HERE, 'criteria.json')))

    def test_adopts_a_dev_gain_with_held_inside_tolerance(self):
        ok, _ = compare.check(self.summary(0.6, 5.0), self.summary(0.6, 4.9, held_de=5.04), self.crit())
        self.assertTrue(ok)

    def test_rejects_a_held_regression(self):
        ok, _ = compare.check(self.summary(0.6, 5.0), self.summary(0.6, 4.9, held_de=5.06), self.crit())
        self.assertFalse(ok)

    def test_rejects_no_dev_gain(self):
        ok, _ = compare.check(self.summary(0.6, 5.0), self.summary(0.598, 4.995), self.crit())
        self.assertFalse(ok)

    def test_exposure_gain_must_not_cost_the_look(self):
        ok, _ = compare.check(self.summary(0.6, 5.0), self.summary(0.5, 5.2), self.crit())
        self.assertFalse(ok)


if __name__ == '__main__':
    unittest.main()
