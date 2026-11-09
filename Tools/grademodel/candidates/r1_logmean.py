"""Round 1: ⇧E matches each frame's log-mean luminance (the geometric mean, Reinhard's key) instead of its median.
Everything else as baseline. No parameter: nothing fitted."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline as B  # noqa: E402

fit_look, apply_look = B.fit_look, B.apply_look


def log_mean(f):
    y = np.maximum(f, 0) @ B.gm.LUMA
    return float(np.exp(np.mean(np.log(y + 1e-4))))


def balance(clips, space):
    return {k: np.full(3, e) for k, e in B.exposure(clips, stat=log_mean).items()}
