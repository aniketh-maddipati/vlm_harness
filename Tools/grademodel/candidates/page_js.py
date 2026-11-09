"""Skim's ⇧E as the page ships it, run through the page's own JavaScript (Tools/exposeval/page.mjs): the balance
this evaluator scores from 2026-11-09 on. Look as baseline.

Each frame's samples (scene-linear, every 8th pixel) go back to the 8-bit codes Skim reads on its canvas: S-Log3
codes (code/1023 · 255, no calibration) on 'slog3' sets, sRGB codes on 'display' (adaCG's thumbnails, which come
back exactly). The page's `sceneSl` and `evAutoMap` then set each clip's Exposure (1/100, ±1): gains on all three
channels. A round's candidate imports this and sets PATCHES ([(old, new)] on the page's text) before the change is
made in the page. Tools/exposeval/rule.py is the cross-check (Tools/exposeval/tests/test_page.py)."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'exposeval'))
import baseline as B  # noqa: E402
import page as P  # noqa: E402

fit_look, apply_look = B.fit_look, B.apply_look
PATCHES = ()
PAGE = None


def page_ev(clips, space, patches=None, page=None):
    """clips {id: [frame (N, 3) scene-linear]} → {id: stops} from the page."""
    slog3 = space == 'slog3'
    data = {k: (slog3, [P.Sampled(P.to_codes(f, space)) for f in fr]) for k, fr in clips.items()}
    out = P.run_page(data, page=page if page is not None else PAGE, patches=PATCHES if patches is None else patches)
    return {k: float(v) for k, v in out['ev'].items()}


def make_balance(patches=(), page=None):
    def balance(clips, space):
        return {k: np.full(3, e) for k, e in page_ev(clips, space, patches, page).items()}
    return balance


balance = make_balance()
