#!/usr/bin/env python3
"""Build the grade model eval's fixed pixel samples (once), so every round scores the same pixels.

    ~/LuminaEvidence/venv-parity/bin/python -I Tools/grademodel/prepare.py [adacg uday sparks tos pst50]
    ~/LuminaEvidence/venv-parity/bin/python -I Tools/grademodel/prepare.py splits   # prints the seeded splits (criteria.json)

Reads only; writes $LUMINA_GRADEMODEL/cache/<set>.npz (default ~/LuminaEvidence/grademodel). Nothing here is
committed: Uday's footage is private, PST50 and adaCG are measure-only, Sparks / Tears of Steel stay on the T7.

Per dataset and shot:
  train  scene-linear source pixels + the graded display code (what a look may be fitted on)
  eval   other frames' / blocks' pixels, scored only
  bal    each frame as the balance rule sees it: scene-linear, every 8th pixel (Skim's `sceneSl` sampling)
"""
import csv
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gm  # noqa: E402

OUT = os.path.join(os.environ.get('LUMINA_GRADEMODEL', os.path.expanduser('~/LuminaEvidence/grademodel')), 'cache')
T7 = '/Volumes/T7/Lumina'
SEED = 20261109


def save(name, d):
    os.makedirs(OUT, exist_ok=True)
    tmp = os.path.join(OUT, name + '.tmp.npz')
    np.savez(tmp, **d)
    os.replace(tmp, os.path.join(OUT, name + '.npz'))
    print(name, 'saved', len(d), 'arrays', flush=True)


def put(d, shot, kind, j, x, y=None):
    d[f'{kind}|{shot}|{j}|x'] = np.asarray(x, np.float32)
    if y is not None:
        d[f'{kind}|{shot}|{j}|y'] = np.asarray(y, np.float32)


# ---- Uday, Saratoga: his FCP edit without (OG, S-Log3) and with his grade, frame-aligned. 9 shots, shot 2 left out
# (the two exports are not aligned there). Same frames, cuts and masks as work/fit/fit_balance3.py.
def uday():
    root = f'{T7}/uday/saratoga'
    z = np.load(f'{root}/work/fit/frames.npz', mmap_mode='r')
    og, gr = z['og'], z['gr']
    n = min(len(og), len(gr))
    H, W, STEP = 216, 384, 3
    cuts = [float(x) for x in open(f'{root}/work/cuts.txt').read().split()]
    t = np.arange(n) * STEP / 24
    shot = np.searchsorted(cuts, t, side='right')
    valid = np.array([min(abs(x - c) for c in cuts) >= 3 / 24 for x in t])
    disp = lambda c: np.clip((c * 1023 - 64) / 876, 0, 1)  # noqa: E731  (legal range → full, as his export is viewed)
    rng = np.random.default_rng(SEED)
    d = {}
    for s in sorted(set(shot)):
        if s == 2:
            continue
        fr = np.where((shot == s) & valid)[0]
        for j, i in enumerate(fr):
            m = np.ones((H, W), bool)
            if s == 0:
                m[int(.30 * H):int(.80 * H), :] = False  # his title card
            bh, bw = int(.12 * H), int(.12 * W)
            m[:bh] = m[-bh:] = False
            m[:, :bw] = m[:, -bw:] = False
            o = np.asarray(og[i], np.float64).reshape(-1, 3)
            g = np.asarray(gr[i], np.float64).reshape(-1, 3)
            put(d, s, 'bal', j, gm.s3_lin(o[::8]))
            idx = np.where(m.ravel())[0]
            kind = 'train' if j % 2 == 0 else 'eval'
            sel = rng.choice(idx, 1500 if kind == 'train' else 4000, replace=False)
            put(d, s, kind, j, gm.s3_lin(o[sel]), disp(g[sel]))
    d['meta'] = np.array(json.dumps({'space': 'slog3', 'eotf': 'srgb'}))
    save('uday', d)


# ---- Netflix Sparks SDR: ungraded ACES2065-1 linear → the graded SDR Rec.709 (BT.1886). 108 frames, 8 ranges.
SPARKS_R = [(30, 511), (2024, 2455), (5363, 5763), (5764, 6024), (6026, 6502), (8396, 8941), (9774, 10071), (11198, 11570)]


def sparks():
    dd = f'{T7}/datasets/netflix-sparks-sdr/work512'
    rng = np.random.default_rng(SEED)
    d = {}
    cnt = {}
    for f in sorted(x for x in os.listdir(dd) if x.endswith('.npz') and not x.startswith('._')):
        fr = int(f[:-4])
        z = np.load(f'{dd}/{f}', allow_pickle=False)
        u, g = z['ungraded'].astype(np.float64), z['graded'].astype(np.float64)
        if 5100 <= fr <= 5763:
            u = u[::-1, ::-1]  # camera rigged upside down; the masters are turned
        grp = next(f'{a}-{b}' for a, b in SPARKS_R if a <= fr <= b)
        j = cnt.get(grp, 0)
        cnt[grp] = j + 1
        U, G = u.reshape(-1, 3), g.reshape(-1, 3)
        put(d, grp, 'bal', j, U[::8])
        sel = rng.choice(len(U), 9000, replace=False)
        put(d, grp, 'train', j, U[sel[:3000]], G[sel[:3000]])
        put(d, grp, 'eval', j, U[sel[3000:]], G[sel[3000:]])  # other pixels of the same frames (a shot-level split is
        # what scores the look: the held-out shot is never in the fit; within a fitted shot these pixels are unused)
    d['meta'] = np.array(json.dumps({'space': 'slog3', 'eotf': 'g24'}))
    save('sparks', d)


# ---- Tears of Steel: linear plate → the regraded edit (sRGB), 33 shots, frames registered by the dataset session.
def tos():
    D = f'{T7}/datasets/tears-of-steel'
    rows = [r for r in csv.DictReader(open(f'{D}/pairs.csv')) if float(r['png_corr']) >= 0.7 and float(r['reg_corr']) >= 0.5]
    rng = np.random.default_rng(SEED)
    d = {}
    cnt = {}
    for r in rows:
        z = np.load(f"{D}/{r['npz']}", allow_pickle=False)
        v = z['valid']
        x, y = z['plate'][v].astype(np.float64), z['graded'][v].astype(np.float64)
        if len(x) < 2000:
            continue
        s = r['shot']
        j = cnt.get(s, 0)
        cnt[s] = j + 1
        put(d, s, 'bal', j, x[::8])
        sel = rng.permutation(len(x))
        put(d, s, 'train', j, x[sel[:3000]], y[sel[:3000]])
        put(d, s, 'eval', j, x[sel[3000:9000]], y[sel[3000:9000]])
    d['meta'] = np.array(json.dumps({'space': 'slog3', 'eotf': 'srgb', 'category': {r['shot']: r['category'] for r in rows}}))
    save('tos', d)


# ---- PST50 (measure only): content_709 → the professional grade, one frame per pair. The look is fitted on half the
# 32 px blocks and scored on the other half (as Tools/lookeval), and carried between pairs of one look cluster.
def pst50():
    sys.path.insert(0, os.path.join(HERE, '..', 'lookeval'))
    from colour import pair, split_mask, IDS  # noqa: E402
    mask = split_mask(540, 960).ravel()
    fit_idx, held_idx = np.where(mask)[0], np.where(~mask)[0]
    d = {}
    for i in IDS:
        rng = np.random.default_rng(SEED + i)
        p = pair(i)
        X, Y = p['r709'].reshape(-1, 3), p['gt'].reshape(-1, 3)
        a = rng.choice(fit_idx, 20000, replace=False)
        b = rng.choice(held_idx, 20000, replace=False)
        put(d, i, 'train', 0, X[a], Y[a])
        put(d, i, 'eval', 0, X[b], Y[b])
        print('pst50', i, flush=True)
    d['meta'] = np.array(json.dumps({'space': 'rec709', 'eotf': 'srgb'}))
    save('pst50', d)


# ---- adaCG (measure only): the annotator's per-shot middle (Tools/exposeval/target.py) and the label thumbnails.
def adacg():
    sys.path.insert(0, os.path.join(HERE, '..', 'exposeval'))
    import adacg as A  # noqa: E402
    import target  # noqa: E402
    from run import decode_thumb, location_of  # noqa: E402
    db = A.load('/Volumes/T7/Lumina/datasets/hdrvs-adacg/trainDemo8b.pkl.UNTRUSTED-do-not-unpickle')
    E = A.entries(db)
    shots = {}
    for name, e in E.items():
        shots.setdefault(A.shot_of(name), []).append(e)
    d = {}
    mids, locs = {}, {}
    for k, es in sorted(shots.items()):
        locs[k] = location_of(list(es[0]['labels']))
        mids[k] = target.shot_log_mid([A.pivots(e) for e in es], 'mid')
        for j, e in enumerate(es):
            fr = decode_thumb(e['thumb']).reshape(-1, 3)
            put(d, k, 'bal', j, gm.np.where(fr / 255.0 <= 0.04045, fr / 255.0 / 12.92, ((fr / 255.0 + 0.055) / 1.055) ** 2.4)[::8])
    tgt = {}
    for loc in sorted(set(locs.values())):
        ks = [k for k in mids if locs[k] == loc]
        tgt.update(target.relative_ev({k: mids[k] for k in ks}))
    d['meta'] = np.array(json.dumps({'loc': {str(k): v for k, v in locs.items()}, 'target': {str(k): v for k, v in tgt.items()}}))
    save('adacg', d)


def splits():
    """Seeded halves (dev / held). Printed once into criteria.json; the evaluator reads them from there."""
    rng = np.random.default_rng(SEED)
    out = {}
    for name in ('adacg', 'uday', 'sparks', 'tos', 'pst50'):
        z = np.load(os.path.join(OUT, name + '.npz'), allow_pickle=False)
        meta = json.loads(str(z['meta']))
        shots = sorted({k.split('|')[1] for k in z.files if '|' in k}, key=lambda s: (len(s), s))
        if name == 'adacg':  # stratified by location
            groups = {}
            for s in shots:
                groups.setdefault(meta['loc'][s], []).append(s)
        elif name == 'tos':  # stratified by category
            groups = {}
            for s in shots:
                groups.setdefault(meta['category'][s], []).append(s)
        else:
            groups = {'all': shots}
        held = []
        for g in sorted(groups):
            ss = sorted(groups[g], key=lambda s: (len(s), s))
            p = rng.permutation(len(ss))
            held += [ss[i] for i in p[: len(ss) // 2]]
        out[name] = {'held': sorted(held, key=lambda s: (len(s), s))}
    out['pst50_clusters'] = {'dev': [[2, 21], [44, 46]], 'held': [[4, 39], [30, 36]]}
    print(json.dumps(out))


if __name__ == '__main__':
    todo = sys.argv[1:] or ['adacg', 'uday', 'sparks', 'tos', 'pst50']
    for t in todo:
        globals()[t]()
