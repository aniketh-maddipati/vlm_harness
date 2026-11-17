"""The page's own ⇧E (page.mjs runs `sceneSl` / `evAutoMap` read out of the Skim page) against rule.py, on
synthetic 8-bit frames (Linux too; needs node). On real frames: page_parity.py, and the last test here when the
adaCG labels and the grade model's cache are on this machine."""
import math
import os
import shutil
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import page as P  # noqa: E402
import page_parity  # noqa: E402
import rule  # noqa: E402

TOL = 1e-6  # stops
MEDIAN_322 = [('if (!v.length) return 0; let s = 0; for (const y of v) s += Math.log(y + 1e-4); return Math.exp(s / v.length); // log-mean (325)',
               'v.sort((a, b) => a - b); return v.length ? v[v.length >> 1] : 0;')]


def shoot(seed, n_clips=7, slog3=False):
    """Clips of 1–4 frames: noise, gradients, a dark low-key frame, a clipped one, a black one, odd sizes."""
    rng = np.random.default_rng(seed)
    clips = {}
    for c in range(n_clips):
        frames = []
        for j in range(1 + (c + seed) % 4):
            h, w = int(rng.integers(9, 40)), int(rng.integers(16, 70))
            kind = (c + j) % 5
            if kind == 0:
                f = rng.integers(0, 256, (h, w, 3))
            elif kind == 1:
                f = np.broadcast_to(np.linspace(0, 255, w)[None, :, None], (h, w, 3)) * rng.uniform(0.3, 1.0)
            elif kind == 2:
                f = rng.integers(0, 40, (h, w, 3)); f[: h // 5] = 230  # low key with a bright window
            elif kind == 3:
                f = np.clip(rng.normal(200, 60, (h, w, 3)), 0, 255)
            else:
                f = rng.integers(0, 256, (h, w, 4))
            frames.append(np.asarray(f, dtype=np.uint8))
        clips[f'c{c}'] = (slog3, frames)
    return clips


@unittest.skipUnless(shutil.which('node'), 'node not found')
class PageMatchesRule(unittest.TestCase):
    def check(self, clips, **kw):
        df, dc, out = page_parity.compare(clips, **kw)
        self.assertLessEqual(df, TOL, 'frame values differ')
        self.assertLessEqual(dc, TOL, 'clip Exposure differs')
        return out

    def test_display_shoots(self):
        for seed in range(4):
            self.check(shoot(seed))

    def test_slog3_shoots(self):
        for seed in range(4):
            self.check(shoot(10 + seed, slog3=True))

    def test_sampled_frames_are_the_pixels_scenesl_reads(self):
        rng = np.random.default_rng(3)
        full = rng.integers(0, 256, (18, 40, 3)).astype(np.uint8)
        a = P.run_page({'x': (True, [full])})['sl']['x'][0]
        b = P.run_page({'x': (True, [P.Sampled(full.reshape(-1, 3)[::8])])})['sl']['x'][0]
        self.assertEqual(a, b)

    def test_exposure_is_clamped_and_rounded_as_the_page(self):
        clips = {'dark': (False, [np.full((9, 16, 3), 8, np.uint8)]), 'mid': (False, [np.full((9, 16, 3), 118, np.uint8)]),
                 'bright': (False, [np.full((9, 16, 3), 250, np.uint8)])}
        ev = self.check(clips)['ev']
        self.assertEqual(ev['mid'], 0)
        self.assertEqual(ev['dark'], 1)
        self.assertLess(ev['bright'], 0)
        self.assertEqual(round(ev['bright'] * 100), ev['bright'] * 100)

    def test_patch_brings_back_322s_median(self):
        # the patch mechanism a round's candidate uses: the page as it was before 325 matches rule.scene_sl
        for seed in range(2):
            self.check(shoot(20 + seed), patches=MEDIAN_322, stat=rule.scene_sl)

    def test_measure_sites_call_scenesl_as_the_harness_does(self):
        # page.mjs calls `pp.sl = sceneSl(img, c, pp)`; the page's own sites must pass the same (pp only if it takes it)
        import re
        src = open(os.path.join(os.path.dirname(P.MJS), '..', '..', 'design/handoff/lumina-skim/Lumina Skim v3.dc.html'), encoding='utf-8').read()
        params = re.search(r'\n  sceneSl\(([^)]*)\) \{', src).group(1).split(',')
        calls = re.findall(r'(\w+)\.sl = this\.sceneSl\(([^)]*)\)', src)
        self.assertEqual(len(re.findall(r'this\.sceneSl\(', src)), len(calls), 'every call stores into pp.sl')
        self.assertGreaterEqual(len(calls), 1)
        for pp, args in calls:
            a = [x.strip() for x in args.split(',')]
            self.assertEqual(len(a), len(params))
            if len(a) == 3:
                self.assertEqual(a[2], pp)

    def test_patch_must_match_once(self):
        with self.assertRaises(RuntimeError):
            P.run_page({'x': (False, [np.zeros((4, 8, 3), np.uint8)])}, patches=[('no such text in the page', '')])

    def test_codes_round_trip(self):
        i = np.arange(256)
        self.assertTrue(np.array_equal(P.srgb_codes(rule.level_table('rec709')[i].astype(np.float32)), i))
        s = rule.level_table('slog3')
        ok = s > 0  # codes below black (S-Log3's 95 of 1023) all decode to 0
        self.assertTrue(np.array_equal(P.slog3_codes(s[i[ok]]), i[ok]))

    @unittest.skipUnless(os.path.exists(page_parity.PKL) and os.path.isdir(page_parity.CACHE), 'adaCG labels / grade model cache not here')
    def test_real_frames(self):
        self.assertEqual(page_parity.main([]), 0)


if __name__ == '__main__':
    unittest.main()
