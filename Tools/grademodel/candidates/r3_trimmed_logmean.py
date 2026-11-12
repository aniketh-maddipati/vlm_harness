"""Round 3: ⇧E matches each frame's trimmed log-mean luminance: the geometric mean of the pixels between the frame's
10th and 90th luminance percentiles (deep shadows and highlights left out, so neither drags the key). Fixed
percentiles, nothing fitted. Everything else as baseline."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline as B  # noqa: E402

fit_look, apply_look = B.fit_look, B.apply_look


def trimmed_log_mean(f):
    y = np.maximum(f, 0) @ B.gm.LUMA
    lo, hi = np.percentile(y, [10, 90])
    m = (y >= lo) & (y <= hi)
    return float(np.exp(np.mean(np.log(y[m] + 1e-4)))) if m.any() else 0.0


def balance(clips, space):
    return {k: np.full(3, e) for k, e in B.exposure(clips, stat=trimmed_log_mean).items()}
