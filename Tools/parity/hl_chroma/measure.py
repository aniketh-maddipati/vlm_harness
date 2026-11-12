"""How Lightroom's chroma moves with Highlights, against today's tone stage on Lightroom's own base.
Per pixel, Oklab chroma ratio C_ref / C_today, binned by the tone stage's log2 gain and by base luma;
per photo, the C-weighted mean of log2 ratio. Numbers only (stdout)."""
import sys
import numpy as np
from scipy.ndimage import gaussian_filter
from common import load, W
from today import apply_today, RULES
import lookmath as lm

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
               [0.0259040371, 0.7827717662, -0.8086757660]])


def oklab(lin):
    lms = np.cbrt(np.maximum(lin, 0) @ M1.T)
    return lms @ M2.T


def gain(base, hl):
    c = base.astype(np.float64); anchor = lm.tone_anchor(c, RULES); y = lm.luma(c, RULES)
    b = gaussian_filter(y, lm.k(RULES, 'tone', 'radiusFraction', 0.03) * max(c.shape[:2]), mode='nearest')
    return np.log2(lm.tone_gain(b, anchor, hl, 0, RULES)), anchor


if __name__ == '__main__':
    P = load()
    for v in [-100, -50, 50]:
        print(f'=== Highlights {v}')
        rows = []
        bins_g = {}; bins_l = {}
        for ph in P:
            base = ph['base'].astype(np.float64); ref = ph['pairs'][('Highlights', v)].astype(np.float64)
            out = apply_today(base, v, 0)
            lg, an = gain(base, v)
            Lr, Lo = oklab(ref), oklab(out)
            Cr, Co = np.hypot(Lr[..., 1], Lr[..., 2]), np.hypot(Lo[..., 1], Lo[..., 2])
            Cb = np.hypot(*oklab(base)[..., 1:].transpose(2, 0, 1))
            ok = (Co > 0.02) & (Cr > 0.005) & (ref.max(-1) < 0.98)
            lr = np.log2(Cr[ok] / Co[ok]); wts = Co[ok]
            lb = Lo[..., 0][ok]
            rows.append((ph['set'], ph['half'], ph['stem'], np.average(lr, weights=wts), an['mean'], an['high'], an['spread'], an['bright'],
                         np.average(np.log2(Co[ok] / np.maximum(Cb[ok], 1e-4)), weights=wts)))
            for x, store, edges in [(lg[ok], bins_g, np.linspace(-2.5, 1.5, 17)), (lb, bins_l, np.linspace(0, 1.05, 22))]:
                i = np.digitize(x, edges)
                for j in np.unique(i):
                    m = i == j; store.setdefault((ph['set'], j), []).append((lr[m] * wts[m]).sum()); store.setdefault((ph['set'], j, 'w'), []).append(wts[m].sum())
        for name, store, edges in [('log2 gain', bins_g, np.linspace(-2.5, 1.5, 17)), ('Oklab L(today)', bins_l, np.linspace(0, 1.05, 22))]:
            print(f'  log2 Cref/Ctoday by {name}:')
            for s in ['dv', 'sweep']:
                line = []
                for j in range(len(edges) + 1):
                    if (s, j) in store:
                        w = sum(store[(s, j, 'w')])
                        if w > 1: line.append(f'{(edges[j-1] if j else -9):+.2f}:{sum(store[(s, j)]) / w:+.3f}')
                print('   ', s, ' '.join(line))
        a = np.array([r[3:] for r in rows])
        print('  per photo log2 ratio: mean %.3f sd %.3f' % (a[:, 0].mean(), a[:, 0].std()))
        names = ['log2 mean', 'log2 high', 'spread', 'bright', 'today vs base log2 C']
        for j, nme in enumerate(names):
            x = a[:, j + 1]; x = np.log2(x) if j < 2 else x
            print(f'   corr with {nme}: {np.corrcoef(x, a[:, 0])[0, 1]:+.2f}')
        for r in rows:
            if r[0] == 'sweep': print('   sweep', r[2], f'{r[3]:+.3f}')
