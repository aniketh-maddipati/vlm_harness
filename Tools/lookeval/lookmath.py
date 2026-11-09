"""Skim's look maths in numpy: a port of the page's LOOK block (`Lumina Skim v3.dc.html`, lkPx / lkSl3 / lkIn /
lkPreview), vectorised over pixels. The page is the reference; `test_lookeval.py` holds this port to it through
`look_ref.mjs` (the page's block run in Node) on random pixels and looks.

A look is the page's flat dict ({'ev': 0.4, 'mix.blue.s': -20, 'grade.sh.h': 210, …}); missing keys are at rest.
Pixels are (n, 3) display-referred 0…1.
"""
import numpy as np

# The page's tables (LK_ROWS, LK_HUES, LK_ZONES); the parity test checks they still match the page.
ROWS_LIGHT = [('ev', 4), ('con', 100), ('hl', 100), ('sh', 100), ('wh', 100), ('bl', 100)]
ROWS_COLOR = [('temp', 100), ('tint', 100), ('vib', 100), ('sat', 100)]
HUES = [('red', 0), ('orange', 30), ('yellow', 60), ('green', 120), ('aqua', 180), ('blue', 220), ('purple', 270), ('magenta', 320)]
ZONES = ['sh', 'mid', 'hi', 'all']
SL3T = np.array([0.0000, 0.0225, 0.0459, 0.0709, 0.0984, 0.1292, 0.1631, 0.1996, 0.2387, 0.2810, 0.3268, 0.3766, 0.4301,
                 0.4876, 0.5500, 0.6167, 0.6851, 0.7530, 0.8170, 0.8740, 0.9223, 0.9604, 0.9866, 1.0000, 1.0000, 1.0000,
                 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000, 1.0000])
SL3M = np.array([1.9014, -0.8790, -0.0434, 0.0067, -0.1553, 1.3955, -0.2447, 0.0003, 0.0021, -0.3185, 1.3129, -0.0011])
LUMA = np.array([0.2126, 0.7152, 0.0722])


def default(p):
    return 50 if p == 'grade.blend' else 0


def rng(p):
    """lkRange: a slider's real range."""
    if p == 'ev':
        return (-4, 4)
    if p == 'grade.blend' or (p.startswith('grade.') and p.endswith('.s')):
        return (0, 100)
    if p.startswith('grade.') and p.endswith('.h'):
        return (0, 360)
    return (-100, 100)


def js_round(v):
    return np.floor(v + 0.5)


def clean(p, v):
    """lkClean: what the page stores for a slider value (ev to 1/100, the rest whole numbers, hues wrapped)."""
    a, b = rng(p)
    if p.startswith('grade.') and p.endswith('.h'):
        return float(js_round(((v % 360) + 360) % 360))
    v = max(a, min(b, v))
    return float(js_round(v * 100) / 100) if p == 'ev' else float(js_round(v))


def clean_look(L):
    return {p: clean(p, v) for p, v in L.items()}


def all_params():
    ps = [p for p, _ in ROWS_LIGHT + ROWS_COLOR]
    ps += [f'mix.{h}.{k}' for h, _ in HUES for k in 'hsl']
    ps += [f'grade.{z}.{k}' for z in ZONES for k in 'hsl'] + ['grade.blend', 'grade.bal']
    return ps


def uniforms(L):
    """lkU."""
    G = lambda p: float(L.get(p, default(p))) if L else float(default(p))
    return dict(ev=G('ev'), temp=G('temp') / 100, tint=G('tint') / 100, con=G('con') / 100, hl=G('hl') / 100,
                sh=G('sh') / 100, wh=G('wh') / 100, bl=G('bl') / 100, vib=G('vib') / 100, sat=G('sat') / 100,
                mixC=np.array([c for _, c in HUES], float),
                mixH=np.array([G(f'mix.{h}.h') / 100 for h, _ in HUES]),
                mixS=np.array([G(f'mix.{h}.s') / 100 for h, _ in HUES]),
                mixL=np.array([G(f'mix.{h}.l') / 100 for h, _ in HUES]),
                gH=np.array([G(f'grade.{z}.h') for z in ZONES]), gS=np.array([G(f'grade.{z}.s') / 100 for z in ZONES]),
                gL=np.array([G(f'grade.{z}.l') / 100 for z in ZONES]),
                blend=G('grade.blend') / 100, bal=G('grade.bal') / 100)


def hsv(rgb):
    """lkHsv on (n,3)."""
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    mx, mn = rgb.max(1), rgb.min(1)
    d = mx - mn
    ok = d > 1e-6
    dd = np.where(ok, d, 1)
    h = np.where(mx == r, np.fmod((g - b) / dd, 6), np.where(mx == g, (b - r) / dd + 2, (r - g) / dd + 4)) * 60
    h = np.where(h < 0, h + 360, h)
    h = np.where(ok, h, 0)
    s = np.where(mx > 0, d / np.where(mx > 0, mx, 1), 0)
    return h, s, mx


def from_hsv(h, s, v):
    """lkRgb, broadcasting."""
    def f(n):
        k = np.fmod(n + h / 60, 6)
        return v - v * s * np.maximum(0, np.minimum(np.minimum(k, 4 - k), 1))
    return np.stack([f(5), f(3), f(1)], -1)


def tone(x, u):
    """lkTone: blacks, shadows, contrast, highlights, whites on one curve."""
    TAU = 2 * np.pi
    x = x + u['bl'] * 0.12 * (1 - x) ** 4
    x = x + u['sh'] * 0.8 * x * (1 - x) ** 3
    x = x - u['con'] * 0.6 * np.sin(TAU * x) / TAU
    x = x + u['hl'] * 0.8 * x ** 3 * (1 - x)
    x = x + u['wh'] * 0.12 * x ** 4
    return np.clip(x, 0, 1)


def px(rgb, u):
    """lkPx on (n,3) with uniforms u (from `uniforms`)."""
    rgb = np.asarray(rgb, float)
    lin = np.maximum(0, rgb) ** 2.2
    e = 2.0 ** u['ev']
    lin = lin * np.array([2.0 ** (0.35 * u['temp'] + 0.125 * u['tint']) * e, 2.0 ** (-0.25 * u['tint']) * e,
                          2.0 ** (-0.35 * u['temp'] + 0.125 * u['tint']) * e])
    kn = 1 - 0.2 * max(0.0, min(1.0, u['ev']))
    v = np.maximum(0, lin) ** (1 / 2.2)
    if kn < 1:
        v = np.where(v < kn, v, kn + (1 - kn) * (1 - np.exp(-(v - kn) / (1 - kn))))
    x = tone(v, u)
    Y = x @ LUMA
    cs = x.max(1) - x.min(1)
    vib = u['vib']
    k = np.maximum(0, (1 + u['sat']) * (1 + vib * ((1 - np.minimum(1, cs * 1.5)) if vib > 0 else 1)))
    x = Y[:, None] + (x - Y[:, None]) * np.broadcast_to(k, Y.shape)[:, None]
    # colour mix
    h, s, v = hsv(np.maximum(0, x))
    C = u['mixC']
    i = np.clip(np.searchsorted(C, h, side='right') - 1, 0, 7)
    a = C[i]
    bN = np.where(i == 7, 360.0, C[(i + 1) % 8])
    f = (h - a) / (bN - a)
    j = (i + 1) % 8
    dh = u['mixH'][i] * (1 - f) + u['mixH'][j] * f
    ds = u['mixS'][i] * (1 - f) + u['mixS'][j] * f
    dl = u['mixL'][i] * (1 - f) + u['mixL'][j] * f
    wc = np.minimum(1, s * 3)
    m = (wc > 0) & ((dh != 0) | (ds != 0) | (dl != 0))
    if m.any():
        h2 = np.fmod(h + dh * 30 * wc + 360, 360)
        s2 = np.clip(s * (1 + ds * wc), 0, 1)
        v2 = np.maximum(0, v * (1 + dl * 0.35 * wc))
        x = np.where(m[:, None], from_hsv(h2, s2, v2), x)
    # grading
    Y = np.clip(x @ LUMA, 0, 1)
    yb = Y ** (2.0 ** -u['bal'])
    p = 2.5 - 2 * u['blend']
    mS, mH = (1 - yb) ** p, yb ** p
    zs = [mS, np.maximum(0, 1 - mS - mH), mH, np.ones_like(Y)]
    for z in range(4):
        if u['gS'][z]:
            t = from_hsv(np.array(u['gH'][z]), 1.0, 1.0)
            ty = t @ LUMA
            x = x + (t - ty)[None, :] * (u['gS'][z] * 0.15 * zs[z])[:, None]
        if u['gL'][z]:
            x = x + (u['gL'][z] * 0.2 * zs[z])[:, None]
    return np.clip(x, 0, 1)


def sl3(rgb, shift=0.0):
    """lkSl3: S-Log3 code values to Rec.709 (33-point table, then the matrix)."""
    n = len(SL3T) - 1
    x = np.clip(np.asarray(rgb, float) + shift, 0, 1) * n
    i = np.minimum(n - 1, np.floor(x).astype(int))
    t = SL3T[i] + (SL3T[i + 1] - SL3T[i]) * (x - i)
    M = SL3M.reshape(3, 4)
    return np.clip(t @ M[:, :3].T + M[:, 3], 0, 1)


def inp(rgb, mode):
    """lkIn: 0 as shot, 1 S-Log3, 2 the other log profiles' filter."""
    rgb = np.asarray(rgb, float)
    if mode == 1:
        return sl3(rgb)
    if mode != 2:
        return rgb
    c = (rgb - 0.5) * 1.35 + 0.5
    y = (c @ LUMA)[:, None]
    return np.clip((y + (c - y) * 1.45) * 0.96, 0, 1)


def preview(rgb, L, mode=0):
    """lkPreview: what the Viewer draws for code values `rgb` of a clip in `mode` with look L."""
    u = uniforms(L)
    if mode != 1:
        return px(inp(rgb, mode), u)
    shift = float(js_round(u['ev'] * 100)) / 100 * 261.5 * np.log10(2) / 1023
    u['ev'] = 0.0
    return px(sl3(rgb, shift), u)


def preview_cont(rgb, L, mode=0):
    """preview without the page's 1/100-stop rounding of the S-Log3 shift (for the optimiser's gradients only)."""
    u = uniforms(L)
    if mode != 1:
        return px(inp(rgb, mode), u)
    shift = u['ev'] * 261.5 * np.log10(2) / 1023
    u['ev'] = 0.0
    return px(sl3(rgb, shift), u)
