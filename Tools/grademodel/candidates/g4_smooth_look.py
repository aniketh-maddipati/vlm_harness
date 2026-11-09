"""G4 (on G1, log-mean ⇧E): a smoother shared look when it is learnt across several shots. The 17³ LUT's
smoothness weight goes 0.5 → 2.0 (the value the Tears of Steel dataset script used for its residual LUT; chosen
before this run, not fitted). A one-frame fit (PST50) keeps 0.5, so the PST50 rows can't move."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline as B  # noqa: E402
import r1_logmean as G1  # noqa: E402

balance, apply_look = G1.balance, B.apply_look
LAM_SHOOT = 2.0


def fit_look(shots, space):
    if len(shots) < 2:
        return B.fit_look(shots, space)
    X = np.concatenate([x for x, _ in shots])
    Y = np.concatenate([y for _, y in shots])
    return B.gm.fit_lut(X, Y, lam=LAM_SHOOT)
