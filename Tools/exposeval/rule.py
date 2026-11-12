"""Skim's ⇧E (per-clip auto exposure) in numpy, line for line with the page.

Source: design/handoff/lumina-skim/Lumina Skim v3.dc.html (LOCAL-CHANGES 322), as scored in report/2026-11-08.md.
Since LOCAL-CHANGES 325 the page's `sceneSl` returns the log-mean instead of the upper median (`scene_sl_logmean`
below; Tools/grademodel round G1); `scene_sl` keeps the 322 form so the 2026-11-08 report reproduces.
  - `sceneSl(img, c)`: a frame's light as shot. Each 8-bit RGBA frame (Skim measures 320 × 180) is read
    every 8th pixel (`i += 32` over RGBA bytes); each level goes to scene-linear through a 256-entry table
    (S-Log3 decoded after the engine's calibration, else sRGB's curve undone); luminance is Rec.709's
    0.2126 R + 0.7152 G + 0.0722 B; the frame's value is the upper median, `v[v.length >> 1]`.
  - `evAutoMap()`: a clip's value is the upper median of its frames' values (frames with 0 left out); the
    shoot's middle is the upper median of its clips' values; a clip's Exposure is
    round(clamp(log2(mid / clip), −1, +1) × 100) / 100 stops.

Nothing here reads files. Frames come in as uint8 arrays (H, W, 3 or 4).
"""

import math

import numpy as np

SLOG3_CUT = 171.2102946929


def srgb_to_linear(s):
    s = np.asarray(s, dtype=np.float64)
    return np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)


def slog3_to_linear(code10):
    """S-Log3 10-bit code value → scene-linear reflectance (Sony's formula, as `sceneSl` has it)."""
    x = np.asarray(code10, dtype=np.float64)
    lin = np.where(x >= SLOG3_CUT,
                   10.0 ** ((x - 420.0) / 261.5) * 0.19 - 0.01,
                   (x - 95.0) * 0.01125 / (SLOG3_CUT - 95.0))
    return np.maximum(0.0, lin)


def level_table(profile="rec709", cal=None, gamma=None):
    """The 256-entry 8-bit level → scene-linear table `sceneSl` builds.

    profile 'slog3': S-Log3 (cal: the engine's 256-entry calibration, 0..1, as `this.cal`).
    profile 'rec709' (any clip that is not S-Log3): sRGB's curve undone. `gamma` replaces it with a pure
    power (an option for this eval only; Skim has none)."""
    i = np.arange(256, dtype=np.float64)
    if profile == "slog3":
        x = (np.asarray(cal, dtype=np.float64) if cal is not None else i / 255.0) * 1023.0
        return slog3_to_linear(x)
    if gamma is not None:
        return (i / 255.0) ** gamma
    return srgb_to_linear(i / 255.0)


def upper_median(values):
    """`a[a.length >> 1]` of the sorted list: the upper of the two middles when the count is even."""
    v = np.sort(np.asarray(values, dtype=np.float64).ravel())
    if v.size == 0:
        return 0.0
    return float(v[v.size >> 1])


def scene_sl(frame, table):
    """One frame's median scene-linear luminance, sampled as `sceneSl` samples it."""
    f = np.asarray(frame)
    if f.dtype != np.uint8:
        raise ValueError("frames are 8-bit, as the canvas gives them")
    if f.ndim != 3 or f.shape[2] not in (3, 4):
        raise ValueError("frame must be (H, W, 3|4)")
    px = f.reshape(-1, f.shape[2])[::8]  # i += 32 over RGBA bytes = every 8th pixel
    lin = table[px[:, 0]] * 0.2126 + table[px[:, 1]] * 0.7152 + table[px[:, 2]] * 0.0722
    return upper_median(lin)



def scene_sl_logmean(frame, table):
    """`sceneSl` since LOCAL-CHANGES 325: exp(mean(log(Y + 1e-4))) over the same sampled pixels."""
    f = np.asarray(frame)
    if f.dtype != np.uint8 or f.ndim != 3 or f.shape[2] not in (3, 4):
        raise ValueError("frames are 8-bit (H, W, 3|4), as the canvas gives them")
    px = f.reshape(-1, f.shape[2])[::8]
    lin = table[px[:, 0]] * 0.2126 + table[px[:, 1]] * 0.7152 + table[px[:, 2]] * 0.0722
    return float(np.exp(np.mean(np.log(lin + 1e-4)))) if lin.size else 0.0

def clip_value(frame_values):
    """A clip's light: the upper median of its frames' `sl`, zeros left out (`x > 0`)."""
    v = [x for x in frame_values if x > 0]
    return upper_median(v) if v else None


def ev_auto_map(clip_values, clamp=1.0, round_to=0.01):
    """clip id → Exposure in stops, as `evAutoMap` returns it. clip_values: id → clip value (None: unmeasured).

    clamp / round_to default to the page's ±1 stop and 1/100; the eval also runs them off (None)."""
    per = {k: v for k, v in clip_values.items() if v is not None and v > 0}
    mid = upper_median(list(per.values()))
    out = {}
    if mid <= 0:
        return out
    for k, v in per.items():
        e = math.log2(mid / v)
        if clamp is not None:
            e = max(-clamp, min(clamp, e))
        if round_to:
            e = math.floor(e / round_to + 0.5) * round_to  # JavaScript's Math.round: halves go up
            e = round(e, 10)
        out[k] = e
    return out
