"""G2 (on G1, log-mean ⇧E): white balance toward the shoot. Each frame's colour is the median log2(R/G) and log2(B/G)
over its mid-tone pixels (luma between its p25 and p90, so black and clipped pixels don't vote); a clip's is the
median over its frames, the shoot's the median over its clips. Each clip moves half way to the shoot (strength 0.5,
fixed), at most ±0.3 stop per channel; all three gains are then shifted together so the luminance-weighted gain
is still ⇧E's exposure (adaCG's exposure row is unchanged by construction). Nothing fitted."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline as B  # noqa: E402
import r1_logmean as G1  # noqa: E402

fit_look, apply_look = B.fit_look, B.apply_look
STRENGTH, CAP = 0.5, 0.3


def frame_chroma(f):
    f = np.maximum(f, 1e-5)
    y = f @ B.gm.LUMA
    lo, hi = np.percentile(y, [25, 90])
    m = (y >= lo) & (y <= hi)
    if m.sum() < 20:
        return None
    return np.array([np.median(np.log2(f[m, 0] / f[m, 1])), np.median(np.log2(f[m, 2] / f[m, 1]))])


def white(clips):
    ch = {}
    for k, frames in clips.items():
        v = [c for c in (frame_chroma(f) for f in frames) if c is not None]
        if v:
            ch[k] = np.median(np.array(v), axis=0)
    if not ch:
        return {}
    mid = np.median(np.array(list(ch.values())), axis=0)
    return {k: np.clip(STRENGTH * (mid - c), -CAP, CAP) for k, c in ch.items()}


def balance(clips, space):
    exp = G1.balance(clips, space)
    wb = white(clips)
    out = {}
    for k, g in exp.items():
        g = g.copy()
        if k in wb:
            g[0] += wb[k][0]
            g[2] += wb[k][1]
            g -= np.dot(B.gm.LUMA, g) - np.dot(B.gm.LUMA, exp[k])  # all three shift together: luma-weighted gain = exposure
        out[k] = g
    return out
