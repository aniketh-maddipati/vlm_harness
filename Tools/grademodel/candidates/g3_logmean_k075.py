"""G3 (on G1, log-mean ⇧E): Exposure = clamp(0.75 · log2(mid / clip), ±1.2) instead of clamp(1.0 · …, ±1).

k and the clamp were fitted 2026-11-09 on the 25 dev shots of Uday, Sparks and ToS only (train-safe; no held shot,
no PST50, no adaCG): each shot's target = its G1 stops + the oracle's extra stops on G1's look; grid k 0.20–1.20,
clamp 0.3–1.5; median |error| 0.297 (k 1, ±1) → 0.167 stops (k 0.75, ±1.2)."""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline as B  # noqa: E402
import r1_logmean as G1  # noqa: E402

fit_look, apply_look = B.fit_look, B.apply_look
K, CLAMP = 0.75, 1.2


def balance(clips, space):
    vals = {}
    for k, frames in clips.items():
        v = [x for x in (G1.log_mean(f) for f in frames) if x > 0]
        if v:
            vals[k] = B.gm.upper_median(v)
    mid = B.gm.upper_median(list(vals.values()))
    out = {}
    for k, v in vals.items():
        e = max(-CLAMP, min(CLAMP, K * math.log2(mid / v)))
        out[k] = np.full(3, math.floor(e * 100 + 0.5) / 100)
    return out
