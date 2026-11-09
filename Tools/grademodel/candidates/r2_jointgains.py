"""Round 2: learn the look with each training shot's own balance taken out. fit_look alternates: one 17³ LUT over all
training shots, then 3 log2 RGB gains per training shot (scene-linear, mean over shots held at 0) fitted to that
shot's grade, then the LUT again on the re-balanced pixels (3 passes). The grader's per-shot trims then stop
blurring the shared look. At apply time nothing changes: the held-out shot gets only the balance rule's gains.
Fitted on training shots only (Uday / Sparks / ToS). With one shot (PST50) it is the baseline LUT."""
import os
import sys

import numpy as np
from scipy.optimize import least_squares

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline as B  # noqa: E402

gm = B.gm
balance, apply_look = B.balance, B.apply_look
PASSES = 3


def _shot_gain(lut, lin, y, g0):
    i = np.random.default_rng(0).choice(len(lin), min(3000, len(lin)), replace=False)
    lin, y = lin[i], y[i]

    def r(g):
        return (np.clip(gm.apply_lut(lut, gm.enc(gm.apply_gains(lin, g))), 0, 1) - y).ravel()
    return least_squares(r, g0, bounds=(-3, 3), max_nfev=40, diff_step=1e-3).x


def fit_look(shots, space):
    if space != 'slog3' or len(shots) < 2:
        return B.fit_look(shots, space)
    lins = [gm.s3_lin(x) for x, _ in shots]
    ys = [y for _, y in shots]
    g = [np.zeros(3) for _ in shots]
    for p in range(PASSES):
        X = np.concatenate([gm.enc(gm.apply_gains(l, gi)) for l, gi in zip(lins, g)])
        lut = gm.fit_lut(X, np.concatenate(ys))
        if p == PASSES - 1:
            return lut
        g = [_shot_gain(lut, l, y, gi) for l, y, gi in zip(lins, ys, g)]
        m = np.mean(g, axis=0)
        g = [gi - m for gi in g]
