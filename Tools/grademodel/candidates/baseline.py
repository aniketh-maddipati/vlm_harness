"""Baseline: Skim as it ships. Balance = ⇧E (LOCAL-CHANGES 322): each frame's upper-median scene-linear luminance
(every 8th pixel), a clip's upper median of its frames, the shoot's upper median of its clips, Exposure =
round(clamp(log2(mid / clip), ±1), 1/100) on every channel. No white balance. Look = one smoothed 17³ LUT on the
balanced S-Log3 input, fitted on every training shot together (what "learn the look once" means here).

A candidate file defines:
  balance(clips, space)         clips {id: [frame (N, 3) scene-linear]} → {id: (3,) log2 RGB gains}
  fit_look(shots, space)        shots [(X (N, 3) look input 0..1, Y (N, 3) graded display code)] → look
  apply_look(look, X, space)    → display code (N, 3)
space: 'slog3' (scene-linear through S-Log3) or 'rec709' (PST50's display-referred input); balance sees
'slog3' or 'display' (adaCG thumbnails, sRGB's curve undone)."""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import gm  # noqa: E402


def frame_value(f):
    y = np.maximum(f, 0) @ gm.LUMA
    return gm.upper_median(y)


def exposure(clips, stat=frame_value, clamp=1.0):
    vals = {}
    for k, frames in clips.items():
        v = [x for x in (stat(f) for f in frames) if x > 0]
        vals[k] = gm.upper_median(v) if v else None
    per = {k: v for k, v in vals.items() if v}
    mid = gm.upper_median(list(per.values()))
    out = {}
    for k, v in per.items():
        e = max(-clamp, min(clamp, math.log2(mid / v)))
        out[k] = math.floor(e * 100 + 0.5) / 100
    return out


def balance(clips, space):
    return {k: np.full(3, e) for k, e in exposure(clips).items()}


def fit_look(shots, space):
    X = np.concatenate([x for x, _ in shots])
    Y = np.concatenate([y for _, y in shots])
    return gm.fit_lut(X, Y)


def apply_look(look, X, space):
    return np.clip(gm.apply_lut(look, X), 0, 1)
