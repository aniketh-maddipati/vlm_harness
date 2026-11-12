"""Fit Skim's look sliders to a graded frame: bounded least squares on CIELAB residuals (ΔE76 per pixel), each slider
held to its real range (lkRange). The result is rounded the way the page stores it (lkClean) and scored with the page's
own maths (lookmath.preview, ΔE2000), so a score is what Skim would draw with that look.

Slider groups (what "which sliders carry the gain" is measured over):
  ev      Exposure
  tone    Contrast, Highlights, Shadows, Whites, Blacks
  wb      Temp, Tint
  sat     Vibrance, Saturation
  mix     8 hues × hue / saturation / luminance
  grade   4 zones × tint (a wheel: hue + strength) and luminance, blending, balance
"""
import numpy as np
from scipy.optimize import least_squares

import lookmath as lm
from colour import srgb_to_lab, de, stats

GROUPS = {
    'ev': ['ev'],
    'tone': ['con', 'hl', 'sh', 'wh', 'bl'],
    'wb': ['temp', 'tint'],
    'sat': ['vib', 'sat'],
    'mix': [f'mix.{h}.{k}' for h, _ in lm.HUES for k in 'hsl'],
    'grade': [f'grade.{z}.{k}' for z in lm.ZONES for k in 'hsl'] + ['grade.blend', 'grade.bal'],
}
GLOBAL = ['ev', 'tone', 'wb', 'sat']
STAGES = {'global': GLOBAL, 'mix': GLOBAL + ['mix'], 'grade': GLOBAL + ['grade'], 'full': GLOBAL + ['mix', 'grade']}


class Space:
    """The optimiser's vector for a set of slider groups. Sliders in units of their range (ev in stops, the rest /100);
    a grade wheel (hue, strength) as a point (x, y) in the unit square, strength = min(1, |(x, y)|), so the hue has no
    seam at 0°/360° and a wheel at rest has no hue to pick."""

    def __init__(self, groups):
        self.groups = list(groups)
        self.names = []  # vector entries: a slider name, or ('wheel', zone, 'x'|'y')
        for g in self.groups:
            for p in GROUPS[g]:
                if p.startswith('grade.') and p[-2:] in ('.h', '.s'):
                    z = p.split('.')[1]
                    if p.endswith('.h'):
                        self.names += [('wheel', z, 'x'), ('wheel', z, 'y')]
                else:
                    self.names.append(p)
        lo, hi = [], []
        for n in self.names:
            if isinstance(n, tuple):
                lo.append(-1.0); hi.append(1.0)
            else:
                a, b = lm.rng(n)
                s = 1 if n == 'ev' else 100
                lo.append(a / s); hi.append(b / s)
        self.lo, self.hi = np.array(lo), np.array(hi)

    def x0(self, look=None):
        look = look or {}
        x = []
        for n in self.names:
            if isinstance(n, tuple):
                _, z, c = n
                s = look.get(f'grade.{z}.s', 0) / 100
                h = np.radians(look.get(f'grade.{z}.h', 0))
                x.append(s * (np.cos(h) if c == 'x' else np.sin(h)))
            else:
                x.append(look.get(n, lm.default(n)) / (1 if n == 'ev' else 100))
        return np.clip(np.array(x, float), self.lo, self.hi)

    def look(self, x, base=None):
        L = dict(base or {})
        wheels = {}
        for n, v in zip(self.names, x):
            if isinstance(n, tuple):
                wheels.setdefault(n[1], {})[n[2]] = v
            else:
                L[n] = float(v) * (1 if n == 'ev' else 100)
        for z, w in wheels.items():
            L[f'grade.{z}.s'] = float(min(1.0, np.hypot(w['x'], w['y'])) * 100)
            L[f'grade.{z}.h'] = float(np.degrees(np.arctan2(w['y'], w['x'])) % 360)
        return L


def sample(src, dst, mask, n, seed=0):
    r = np.random.default_rng(seed)
    xs, ys = src[mask], dst[mask]
    sel = r.choice(len(xs), min(n, len(xs)), replace=False)
    return xs[sel], ys[sel]


def fit(xs, ys, mode, groups, start=None, max_nfev=200):
    """Fit the sliders in `groups` (others held at `start`) so preview(xs) ≈ ys. Returns the page-clean look."""
    sp = Space(groups)
    base = {k: v for k, v in (start or {}).items()}
    tgt = srgb_to_lab(ys)
    k = 1 / np.sqrt(len(xs))

    def res(x):
        return ((srgb_to_lab(lm.preview_cont(xs, sp.look(x, base), mode)) - tgt) * k).ravel()

    r = least_squares(res, sp.x0(base), bounds=(sp.lo, sp.hi), method='trf', diff_step=1e-3, x_scale='jac',
                      max_nfev=max_nfev)
    L = sp.look(r.x, base)
    return {p: v for p, v in lm.clean_look(L).items() if v != lm.default(p)}


def score(L, src, dst, mask=None, mode=0):
    """ΔE2000 median / p95 of the page's own preview of `src` with look L against `dst` (on `mask` if given)."""
    h, w, _ = src.shape
    out = lm.preview(src.reshape(-1, 3), L, mode).reshape(h, w, 3)
    d = de(out, dst)
    return stats(d[mask] if mask is not None else d)


def fit_stage(xs, ys, mode, stage, start=None):
    """Global: three exposure starts, best kept. Other stages start from `start` (normally the global fit)."""
    groups = STAGES[stage] if isinstance(stage, str) else stage
    if start is None and 'ev' in groups:
        tgt = srgb_to_lab(ys)
        best = None
        for ev in (-1.0, 0.0, 1.0):
            L = fit(xs, ys, mode, groups, {'ev': ev})
            c = float(np.mean(np.sum((srgb_to_lab(lm.preview(xs, L, mode)) - tgt) ** 2, 1)))
            if best is None or c < best[0]:
                best = (c, L)
        return best[1]
    return fit(xs, ys, mode, groups, start)
