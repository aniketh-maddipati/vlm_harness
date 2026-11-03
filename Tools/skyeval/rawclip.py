"""Sensor clipping straight from the RAW (ground truth for LookSky's F1 and F6).

Per Bayer site: clipped when (raw − black) ≥ 0.98 × (white − black), with the white level from the
file's own WhiteLevel tag (Sony compressed ARW: 15360; LibRaw reports 16383, which misses the top
band). Returned as planes on a given grid, upright like the develop: the share of each channel's
sites that clipped in each cell, and each channel's level (raw fraction of white) for the
headroom estimate. Research tool: rawpy is not part of the app.
"""
import json
import subprocess

import numpy as np
import rawpy

CLIP = 0.98
_tags = {}


def levels(path):
    if path not in _tags:
        out = subprocess.run(["exiftool", "-j", "-n", "-WhiteLevel", "-BlackLevel", path], capture_output=True, text=True).stdout
        d = json.loads(out)[0]
        w = d.get("WhiteLevel"); b = d.get("BlackLevel")
        w = float(str(w).split()[0]) if w is not None else None
        b = float(str(b).split()[0]) if b is not None else None
        _tags[path] = (w, b)
    return _tags[path]


def _box(a, h, w):
    """Mean of `a` over an h × w grid of cells (area average)."""
    H, W = a.shape
    ys = (np.arange(h + 1) * H / h).astype(int)
    xs = (np.arange(w + 1) * W / w).astype(int)
    c = np.cumsum(np.cumsum(np.pad(a.astype(np.float64), ((1, 0), (1, 0))), 0), 1)
    s = c[ys[1:, None], xs[None, 1:]] - c[ys[:-1, None], xs[None, 1:]] - c[ys[1:, None], xs[None, :-1]] + c[ys[:-1, None], xs[None, :-1]]
    n = (ys[1:, None] - ys[:-1, None]) * (xs[None, 1:] - xs[None, :-1])
    return s / np.maximum(n, 1)


def _upright(a, flip):
    # LibRaw flip: 3 = 180°, 5 = 90° counter-clockwise, 6 = 90° clockwise
    return {3: np.rot90(a, 2), 5: np.rot90(a, 1), 6: np.rot90(a, -1)}.get(flip, a)


def planes(path, h, w):
    """{'r','g','b'}: share of clipped sites per cell; {'lr','lg','lb'}: mean level (0…1 of white) per cell."""
    wl, bl = levels(path)
    with rawpy.imread(path) as r:
        raw = r.raw_image_visible.astype(np.float32)
        pat = r.raw_pattern
        desc = r.color_desc.decode()
        black = bl if bl is not None else float(np.mean(r.black_level_per_channel))
        white = wl if wl is not None else float(r.white_level)
        flip = r.sizes.flip
    frac = (raw - black) / (white - black)
    H2, W2 = raw.shape[0] // 2 * 2, raw.shape[1] // 2 * 2
    frac = frac[:H2, :W2]
    chans = {"r": [], "g": [], "b": []}
    for dy in range(2):
        for dx in range(2):
            name = desc[pat[dy, dx]].lower()
            chans[name].append(frac[dy::2, dx::2])
    out = {}
    for k, subs in chans.items():
        lvl = np.mean(subs, axis=0)
        clip = np.max([s >= CLIP for s in subs], axis=0).astype(np.float32)
        lvl, clip = _upright(lvl, flip), _upright(clip, flip)
        out[k] = _box(clip, h, w)
        out["l" + k] = _box(lvl, h, w)
    return out
