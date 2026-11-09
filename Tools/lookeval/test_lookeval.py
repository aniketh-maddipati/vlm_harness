"""The look eval's own tests, on synthetic data only (no PST50, no photos).

  ~/LuminaEvidence/venv-parity/bin/python -I -m unittest discover -s Tools/lookeval -p 'test_*.py'   (make lookeval-test)
The parity test needs node (it runs the page's own LOOK block); it skips without it.
"""
import os, sys, json, shutil, subprocess, unittest
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lookmath as lm
import fit as F
from colour import de2000, srgb_to_lab, de, split_mask

NODE = shutil.which('node')


def page(rgb, looks, mode, params=()):
    q = json.dumps(dict(rgb=np.asarray(rgb).tolist(), looks=looks, mode=mode, params=list(params)))
    return json.loads(subprocess.run([NODE, os.path.join(HERE, 'look_ref.mjs')], input=q, capture_output=True, text=True, check=True).stdout)


def random_looks(r, n, k=8):
    ps, out = lm.all_params(), [{}]
    for _ in range(n):
        L = {}
        for p in r.choice(ps, k, replace=False):
            a, b = lm.rng(p)
            L[p] = round(float(r.uniform(a, b)), 2 if p == 'ev' else 0)
        out.append(L)
    return out


@unittest.skipUnless(NODE, 'node not found')
class PageParity(unittest.TestCase):
    def test_port_equals_the_page(self):
        r = np.random.default_rng(7)
        rgb = r.random((300, 3))
        rgb[:30] = rgb[:30, :1]  # greys
        rgb[30:40] = [[1, 1, 1], [0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [0, 1, 1], [1, 0, 1], [.5, .5, .5], [1, .5, 0]]
        looks = random_looks(r, 30) + [{p: lm.rng(p)[1]} for p in lm.all_params()] + [{p: lm.rng(p)[0]} for p in lm.all_params()]
        for mode in (0, 1, 2):
            o = page(rgb, looks, mode)
            for ref, L in zip(o['out'], looks):
                np.testing.assert_allclose(lm.preview(rgb, L, mode), np.array(ref), atol=1e-9, err_msg=f'mode {mode} look {L}')

    def test_tables_and_ranges_match_the_page(self):
        o = page([[0, 0, 0]], [{p: 123.456 for p in lm.all_params()}], 0, lm.all_params())
        self.assertEqual([(p, mx) for p, _, mx in o['rows']['light']], lm.ROWS_LIGHT)
        self.assertEqual([(p, mx) for p, _, mx in o['rows']['color']], lm.ROWS_COLOR)
        self.assertEqual([(h, c) for h, _, c in o['hues']], lm.HUES)
        self.assertEqual([z for z, _ in o['zones']], lm.ZONES)
        for p, ab in o['ranges'].items():
            self.assertEqual(tuple(ab), lm.rng(p), p)
        for p, v in o['clean'][0].items():
            self.assertEqual(v, lm.clean(p, 123.456), p)


class Colour(unittest.TestCase):
    def test_de2000_reference_pairs(self):
        # Sharma, Wu & Dalal (2005) test data, pairs 1, 7, 13, 25, 17.
        a = np.array([[50, 2.6772, -79.7751], [50, 0, 0], [50, 2.49, -0.001], [60.2574, -34.0099, 36.2677], [50, 2.5, 0]])
        b = np.array([[50, 0, -82.7485], [50, -1, 2], [50, -2.49, 0.0009], [60.4626, -34.1751, 39.4387], [73, 25, -18]])
        np.testing.assert_allclose(de2000(a, b), [2.0425, 2.3669, 7.1792, 1.2644, 27.1492], atol=1e-4)

    def test_white_is_L100(self):
        np.testing.assert_allclose(srgb_to_lab(np.ones((1, 3))), [[100, 0, 0]], atol=1e-3)


class Space(unittest.TestCase):
    def test_round_trip_and_bounds(self):
        sp = F.Space(F.STAGES['full'])
        L = {'ev': 1.25, 'con': 30, 'mix.blue.s': -40, 'grade.sh.h': 210, 'grade.sh.s': 35, 'grade.blend': 70, 'grade.bal': -20}
        back = lm.clean_look(sp.look(sp.x0(L)))
        for p, v in L.items():
            self.assertEqual(back[p], v, p)
        self.assertEqual(len(sp.lo), len(sp.names))
        self.assertTrue(np.all(sp.lo < sp.hi))
        self.assertEqual((sp.lo[sp.names.index('ev')], sp.hi[sp.names.index('ev')]), (-4, 4))


def synthetic(seed=3, h=96, w=160):
    """A smooth colourful frame: hue across, value down, saturation in rings."""
    yy, xx = np.mgrid[0:h, 0:w]
    hue = 360 * xx / w
    val = 0.08 + 0.9 * yy / h
    sat = 0.15 + 0.8 * (0.5 + 0.5 * np.sin(np.hypot(xx - w / 2, yy - h / 2) / 7))
    img = lm.from_hsv(hue.ravel(), sat.ravel(), val.ravel()).reshape(h, w, 3)
    return np.clip(img + np.random.default_rng(seed).normal(0, 0.002, img.shape), 0, 1)


class Recovery(unittest.TestCase):
    def test_global_look_is_recovered(self):
        src = synthetic()
        truth = {'ev': 0.4, 'con': 25, 'hl': -30, 'sh': 20, 'temp': 15, 'tint': -10, 'sat': -20}
        dst = lm.preview(src.reshape(-1, 3), truth, 0).reshape(src.shape)
        m = split_mask(*src.shape[:2], block=16)
        xs, ys = F.sample(src, dst, m, 4000)
        L = F.fit_stage(xs, ys, 0, 'global')
        med, p95 = F.score(L, src, dst, ~m)
        self.assertLess(med, 0.3, L)
        self.assertLess(p95, 1.0, L)
        self.assertAlmostEqual(L.get('ev', 0), truth['ev'], delta=0.15)
        self.assertAlmostEqual(L.get('temp', 0), truth['temp'], delta=6)

    def test_mix_and_grade_beat_global_on_a_hue_move(self):
        src = synthetic()
        truth = {'ev': 0.2, 'mix.blue.s': -50, 'mix.green.h': 40, 'grade.sh.h': 200, 'grade.sh.s': 60}
        dst = lm.preview(src.reshape(-1, 3), truth, 0).reshape(src.shape)
        m = split_mask(*src.shape[:2], block=16)
        xs, ys = F.sample(src, dst, m, 4000)
        G = F.fit_stage(xs, ys, 0, 'global')
        Fu = F.fit_stage(xs, ys, 0, 'full', G)
        g, f = F.score(G, src, dst, ~m)[0], F.score(Fu, src, dst, ~m)[0]
        self.assertLess(f, 0.5, Fu)
        self.assertLess(f, g / 2, (g, f))

    def test_slog3_mode_fits_a_code_shift(self):
        src = 0.3 + 0.4 * synthetic()  # log-like: lifted, flat
        truth = {'ev': -0.7, 'con': 20}
        dst = lm.preview(src.reshape(-1, 3), truth, 1).reshape(src.shape)
        m = split_mask(*src.shape[:2], block=16)
        xs, ys = F.sample(src, dst, m, 4000)
        L = F.fit_stage(xs, ys, 1, 'global')
        self.assertLess(F.score(L, src, dst, ~m, 1)[0], 0.3, L)
        self.assertAlmostEqual(L.get('ev', 0), truth['ev'], delta=0.1)

    def test_score_is_zero_for_the_same_frame(self):
        src = synthetic()
        self.assertLess(max(F.score({}, src, src)), 1e-9)
        self.assertGreater(float(np.median(de(src, np.clip(src + 0.05, 0, 1)))), 1)


if __name__ == '__main__':
    unittest.main()
