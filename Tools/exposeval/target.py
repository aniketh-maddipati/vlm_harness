"""The annotator's exposure target, as far as the adaCG labels carry one.

The labels hold no exposure, gain or brightness choice: `set` is CIELAB a*/b* offsets (colour only) and
`reg` is four region thresholds ("pivots"), where the annotator decided the darkest / dark / light /
lightest regions of each still begin. A pivot is a level of mean(R, G, B) in the still's own encoding
(Display P3, gamma 2.4; adaCG.py `colorEngine`: `yLut = mean(idLut)`, masks by `np.piecewise` on it).
The falloffs are the tool's defaults on every still (−10, −5, 5, 10), so the pivots are the only choice.

Proxy: the annotator's middle is halfway between where "dark" ends and "light" begins,
    mid = (pivot_dark + pivot_light) / 2  (encoded),
and the exposure that would put that middle at a reference is log2(ref / mid_linear), mid_linear =
mid ** 2.4. Two references:
  - absolute: 18 % grey. The tool's default pivots (0.4, 0.5) put mid at 0.45 encoded, 0.147 linear,
    close to 18 % (0.49 encoded), so the tool's neutral is near this reference;
  - relative: the shoot's own centre (the median over the shoot's shots), the frame ⇧E works in.
`which` picks another pivot to stand for the middle ('dark', 'light', or a region name) for sensitivity.
"""

import math

import numpy as np

from adacg import REGIONS

DISPLAY_GAMMA = 2.4
GREY18 = 0.18


def to_linear(code, gamma=DISPLAY_GAMMA):
    return float(max(code, 1e-4)) ** gamma


def mid_code(pivots, which="mid"):
    p = dict(zip(REGIONS, pivots))
    if which == "mid":
        return 0.5 * (p["dark"] + p["light"])
    return p[which]


def absolute_ev(pivots, which="mid", ref=GREY18):
    """Stops that put the annotator's middle at `ref` (scene-linear)."""
    return math.log2(ref / to_linear(mid_code(pivots, which)))


def shot_log_mid(pivot_lists, which="mid"):
    """A shot's middle in log2 linear: the mean over its stills (two per video in the subset)."""
    return float(np.mean([math.log2(to_linear(mid_code(p, which))) for p in pivot_lists]))


def relative_ev(shot_logs):
    """shot → stops that bring its middle to the shoot's median middle (plain median: no ⇧E quirks)."""
    c = float(np.median(list(shot_logs.values())))
    return {k: c - v for k, v in shot_logs.items()}
