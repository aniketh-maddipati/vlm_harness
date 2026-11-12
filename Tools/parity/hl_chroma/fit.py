"""Fit a highlight chroma gain on top of today's tone stage, Lightroom base → Lightroom Highlights.
out' = y + (out − y)·s, s = 2^(κ·(hl/100)·m), m = smoothstep(p0, p1, perceptual(mask luma)), κ per sign,
capped so no channel goes below 0. Luma is kept, grey stays grey.
Variants of the mask luma: 'base' (pixel luma of the stage input; adopted), 'anch' (× the Highlights mask scale nh), 'gain' (anch × the photo's Highlights strength).
Fit: DV dev half at 256 px, mean ΔE76. Score: ΔE2000 at 512 px on dev / unseen / sweep.
Usage: fit.py [variant] → stdout + ~/LuminaEvidence/hl-chroma/fit-<variant>.json"""
import json, sys
import numpy as np
from scipy.optimize import minimize
from common import load, W, lab, score, OUT
from today import apply_today, RULES
import lookmath as lm

VAR = sys.argv[1] if len(sys.argv) > 1 else 'base'
EV = '/Users/' + __import__('getpass').getuser() + '/LuminaEvidence/hl-chroma/'
POS = [-100, -50, 50]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / max(1e-4, e1 - e0), 0, 1); return t * t * (3 - 2 * t)


def chroma(out, mlum, hl, p, gh=1.0):
    """p = (κ, p0, p1). Variant 'gain' scales by the photo's Highlights strength gh too."""
    kap, p0, p1 = p
    m = smooth(p0, p1, np.power(np.maximum(mlum, 0), 1 / 2.2))
    s = 2.0 ** (kap * hl / 100 * m * (gh if VAR == 'gain' else 1.0))
    y = out @ W
    lo = out.min(-1)
    cap = np.where(y - lo > 1e-6, y / np.maximum(y - lo, 1e-6), 1e6)   # s ≤ cap keeps every channel ≥ 0
    s = np.minimum(s, np.maximum(cap, 1.0))
    return y[..., None] + (out - y[..., None]) * s[..., None]


def prep(P):
    D = []
    for ph in P:
        base = ph['base'].astype(np.float64)
        an = lm.tone_anchor(base, RULES); nh = lm.tone_normalisers(an, RULES)[1]
        yb = base @ W
        mlum = yb * (nh if VAR in ('anch', 'gain') else 1.0)
        gh = lm.tone_normalisers(an, RULES)[3]
        d = {'gh': gh, 'set': ph['set'], 'half': ph['half'], 'stem': ph['stem'], 'mlum': mlum, 'out': {}, 'ref': {}}
        for v in POS:
            d['out'][v] = apply_today(base, v, 0); d['ref'][v] = ph['pairs'][('Highlights', v)].astype(np.float64)
        D.append(d)
    return D


def ds(a):
    return a[: a.shape[0] // 2 * 2, : a.shape[1] // 2 * 2].reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2, *a.shape[2:]).mean((1, 3))


if __name__ == '__main__':
    D = prep(load())
    dev = [d for d in D if d['half'] == 'dev']
    small = [{'gh': d['gh'], 'mlum': ds(d['mlum']), 'out': {v: ds(d['out'][v]) for v in POS}, 'ref': {v: lab(ds(d['ref'][v])) for v in POS}} for d in dev]

    def loss(p, vs):
        if not (p[1] < p[2]): return 1e9
        e = []
        for d in small:
            for v in vs:
                o = chroma(d['out'][v], d['mlum'], v, p, d['gh'])
                e.append(np.linalg.norm(lab(np.clip(o, 0, 1)) - d['ref'][v], axis=-1)[::3, ::3].ravel())
        e = np.concatenate(e); return e.mean() + 0.25 * np.percentile(e, 95)
    res = {}
    for sign, vs in [('neg', [-100, -50]), ('pos', [50])]:
        best = None
        for x0 in [(-0.6, 0.6, 1.0), (-1.0, 0.75, 1.0), (-0.4, 0.4, 0.95)]:
            x0 = np.array(x0) * (1 if sign == 'neg' else np.array([-1, 1, 1]))
            r = minimize(loss, x0, args=(vs,), method='Nelder-Mead', options={'xatol': 1e-3, 'fatol': 1e-4, 'maxiter': 300})
            if best is None or r.fun < best.fun: best = r
        res[sign] = best.x.tolist(); print(sign, best.x.round(4), round(best.fun, 4), flush=True)
    out = {'variant': VAR, 'params': res, 'scores': {}}
    for v in POS:
        p = res['neg' if v < 0 else 'pos']
        for half in ['dev', 'unseen', 'sweep']:
            a, b = [], []
            for d in D:
                if d['half'] != half: continue
                a.append(score(d['ref'][v], d['out'][v]).ravel()); b.append(score(d['ref'][v], chroma(d['out'][v], d['mlum'], v, p, d['gh'])).ravel())
            a, b = np.concatenate(a), np.concatenate(b)
            row = [float(np.median(a)), float(np.percentile(a, 95)), float(np.median(b)), float(np.percentile(b, 95))]
            out['scores'][f'{v} {half}'] = row
            print(f'Highlights {v:+d} {half:7s} today {row[0]:.2f} / {row[1]:.2f}  chroma {row[2]:.2f} / {row[3]:.2f}', flush=True)
    json.dump(out, open(EV + f'fit-{VAR}.json', 'w'), indent=1)
