"""Skim's ⇧E as the page computes it: Python's side of page.mjs (Node runs the page's own `sceneSl` / `evAutoMap`).

    from page import run_page, to_codes
    out = run_page({'a': (False, [frame_uint8, ...]), 'b': (True, [...])})   # id → (slog3, frames)
    out['sl'][id] → per-frame values, out['ev'][id] → stops (rounded to 1/100, ±1, as the page sets them)

Frames are 8-bit (H, W, 3|4) arrays, as a canvas gives them, or `Sampled(codes)`: only the pixels sceneSl reads
(every 8th), (N, 3) uint8, rebuilt by page.mjs at their places. `patches`: [(old, new)] applied to the page's text
first (a round's candidate, before it is made in the page). rule.py is the numpy cross-check of the same numbers.
"""
import json
import os
import shutil
import struct
import subprocess
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MJS = os.path.join(HERE, 'page.mjs')
SLOG3_CUT = 171.2102946929


class Sampled:
    """The pixels sceneSl reads of one frame (every 8th), (N, 3|4) uint8."""
    def __init__(self, codes):
        self.codes = np.ascontiguousarray(codes, dtype=np.uint8)


def node():
    n = shutil.which('node')
    if not n:
        raise RuntimeError('node not found: page.py runs the page through Node')
    return n


def run_page(clips, page=None, patches=(), timeout=600):
    head, chunks, off = {'clips': []}, [], 0
    for cid, (slog3, frames) in clips.items():
        fs = []
        for f in frames:
            sampled = isinstance(f, Sampled)
            a = f.codes if sampled else np.ascontiguousarray(f)
            if a.dtype != np.uint8:
                raise ValueError('frames are 8-bit')
            if sampled:
                if a.ndim != 2:
                    raise ValueError('Sampled is (N, ch)')
                w, h, ch = a.shape[0], 1, a.shape[1]
            else:
                if a.ndim != 3 or a.shape[2] not in (3, 4):
                    raise ValueError('frame must be (H, W, 3|4)')
                h, w, ch = a.shape
            b = a.tobytes()
            fs.append({'off': off, 'w': int(w), 'h': int(h), 'ch': int(ch), 'sampled': sampled})
            chunks.append(b)
            off += len(b)
        head['clips'].append({'id': str(cid), 'slog3': bool(slog3), 'frames': fs})
    hb = json.dumps(head).encode()
    with tempfile.TemporaryDirectory(prefix='lumina-page-ev-') as d:
        fin = os.path.join(d, 'in.bin')
        with open(fin, 'wb') as fh:
            fh.write(struct.pack('<I', len(hb)))
            fh.write(hb)
            for b in chunks:
                fh.write(b)
        cmd = [node(), MJS, fin]
        if page:
            cmd += ['--page', page]
        if patches:
            pf = os.path.join(d, 'patch.json')
            json.dump([list(p) for p in patches], open(pf, 'w'))
            cmd += ['--patch', pf]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if r.returncode:
            raise RuntimeError('page.mjs failed: ' + r.stderr.strip()[-2000:])
        return json.loads(r.stdout)


# ---- scene-linear → the 8-bit codes Skim would see (for sets stored as scene-linear: Sparks, Tears of Steel, Uday)

def srgb_codes(lin):
    """Scene-linear (sRGB's curve undone) → 8-bit codes, the inverse of the page's non-S-Log3 table."""
    x = np.clip(np.asarray(lin, np.float64), 0, 1)
    s = np.where(x <= 0.0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - 0.055)
    return np.clip(np.floor(s * 255 + 0.5), 0, 255).astype(np.uint8)


def slog3_codes(lin):
    """Scene-linear reflectance → 8-bit S-Log3 codes (code/1023 · 255, the page's table with no calibration)."""
    x = np.asarray(lin, np.float64)
    c = np.where(x >= 0.01125, 420 + np.log10((np.maximum(x, 0.01125) + 0.01) / 0.19) * 261.5,
                 x * (SLOG3_CUT - 95) / 0.01125 + 95)
    return np.clip(np.floor(c / 1023 * 255 + 0.5), 0, 255).astype(np.uint8)


def to_codes(lin, space):
    """'slog3' → S-Log3 codes; 'display' (anything else) → sRGB codes."""
    return slog3_codes(lin) if space == 'slog3' else srgb_codes(lin)
