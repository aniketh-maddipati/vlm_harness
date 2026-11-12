"""Oracle diagnostic: how much of Lightroom's Highlights / Shadows is a per-photo global curve on luma,
and how much more a local (2-D: pixel luma × blurred luma at scale s) table explains. Fitted per photo
on the answer itself, so these are ceilings, not models."""
import sys
import numpy as np
from scipy.ndimage import gaussian_filter
from common import load, POS, W, score
from today import apply_today

NB = 32
def lut1(x, t, nb=NB):
    e = np.linspace(x.min(), x.max() + 1e-6, nb + 1); i = np.clip(np.digitize(x, e) - 1, 0, nb - 1)
    s = np.bincount(i, t, nb); n = np.bincount(i, None, nb); m = s / np.maximum(n, 1)
    c = (e[:-1] + e[1:]) / 2; ok = n > 0
    return np.interp(x, c[ok], m[ok])
def lut2(x, z, t, nb=24):
    ex = np.linspace(x.min(), x.max() + 1e-6, nb + 1); ez = np.linspace(z.min(), z.max() + 1e-6, nb + 1)
    i = np.clip(np.digitize(x, ex) - 1, 0, nb - 1); j = np.clip(np.digitize(z, ez) - 1, 0, nb - 1); k = i * nb + j
    s = np.bincount(k, t, nb * nb); n = np.bincount(k, None, nb * nb)
    m1 = lut1(x, t)  # fallback for sparse cells
    return np.where(n[k] >= 4, s[k] / np.maximum(n[k], 1), m1)
if __name__ == '__main__':
    P = load()
    SC = [0.005, 0.02, 0.06]
    rows = {}
    for ph in P:
        base = ph['base'].astype(np.float64); yb = np.maximum(base @ W, 1e-5); lb = np.log2(yb)
        long = max(base.shape[:2])
        blur = {s: np.log2(np.maximum(gaussian_filter(yb, s * long), 1e-5)) for s in SC}
        for (sl, v), ref in ph['pairs'].items():
            ref = ref.astype(np.float64); t = np.log2(np.maximum(ref @ W, 1e-5)) - lb
            r = {}
            r['none'] = score(ref, base)
            r['today'] = score(ref, apply_today(base, v if sl == 'Highlights' else 0, v if sl == 'Shadows' else 0))
            r['global'] = score(ref, base * 2 ** lut1(lb.ravel(), t.ravel()).reshape(lb.shape)[..., None])
            for s in SC:
                r[f'local{s}'] = score(ref, base * 2 ** lut2(lb.ravel(), blur[s].ravel(), t.ravel()).reshape(lb.shape)[..., None])
            for k, de in r.items():
                rows.setdefault((ph['set'], sl, v, k), []).append(de.ravel()[::7])
    keys = ['none', 'today', 'global'] + [f'local{s}' for s in SC]
    print('median / p95 ΔE2000, pooled pixels, all photos of the set (oracles fitted per photo on the answer)')
    print('%-26s' % '' + ''.join('%14s' % k for k in keys))
    for setname in ['dv', 'sweep']:
        for sl, v in POS:
            line = '%-26s' % f'{setname} {sl} {v:+d}'
            for k in keys:
                a = np.concatenate(rows[(setname, sl, v, k)]); line += '%14s' % f'{np.median(a):.2f}/{np.percentile(a, 95):.2f}'
            print(line)
