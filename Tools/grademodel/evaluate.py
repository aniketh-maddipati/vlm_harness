#!/usr/bin/env python3
"""The grade model's one evaluator (frozen 2026-11-09; splits and rules in criteria.json, changed only by the owner).

    ~/LuminaEvidence/venv-parity/bin/python -I Tools/grademodel/evaluate.py Tools/grademodel/candidates/<name>.py [--jobs 10]

Scores one candidate (a Python file with `balance`, `fit_look`, `apply_look`; see candidates/baseline.py) and prints
one table. Every number also goes to $LUMINA_GRADEMODEL/<date>/<name>.json (default ~/LuminaEvidence/grademodel).
Needs the cache from prepare.py.

What is scored (dev / held halves from criteria.json):
  exposure  adaCG (measure only): |stops − the annotator's relative middle| per shot, the shoot = location label.
            The candidate's balance runs on every shot of a location (as ⇧E runs on a whole shoot).
  uday      Uday's Saratoga, leave one shot out: balance (whole shoot, no grade seen) → the look fitted on the other
            shots' balanced pixels → ΔE2000 to his grade on the held-out shot's unseen frames.
  sparks    the same on Netflix Sparks SDR (8 ranges, leave one out); tos: Tears of Steel (33 shots, 6 folds).
  pst50     (measure only) a look fitted on half the 32 px blocks of one graded frame, scored on the other half;
            transfer: a pair's look on the other pair of its look cluster.
  ΔE rows: median over shots of each shot's median, and of each shot's p95.
  info rows (not gated): oracle exposure, the one extra gain (stops) that would best fit the held-out shot on top of
            the candidate's balance, its |median|, and ΔE with it (the "touch-up" pass).
"""
import argparse
import datetime
import functools
import importlib.util
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gm  # noqa: E402

ROOT = os.environ.get('LUMINA_GRADEMODEL', os.path.expanduser('~/LuminaEvidence/grademodel'))
CRIT = json.load(open(os.path.join(HERE, 'criteria.json')))
FITTED = ('uday', 'sparks', 'tos')


def candidate(path):
    spec = importlib.util.spec_from_file_location('candidate', path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


@functools.lru_cache(maxsize=None)
def data(name):
    z = np.load(os.path.join(ROOT, 'cache', name + '.npz'), allow_pickle=False)
    d = {'meta': json.loads(str(z['meta'])), 'train': {}, 'eval': {}, 'bal': {}}
    keys = sorted((k for k in z.files if k.endswith('|x')), key=lambda k: (k.split('|')[1], int(k.split('|')[2])))
    for k in keys:
        kind, s, j, _ = k.split('|')
        x = z[k].astype(np.float64)
        y = z[k[:-1] + 'y'].astype(np.float64) if kind != 'bal' else None
        d[kind].setdefault(s, []).append((x, y) if y is not None else x)
    for kind in ('train', 'eval'):
        d[kind] = {s: (np.concatenate([a for a, _ in v]), np.concatenate([b for _, b in v])) for s, v in d[kind].items()}
    d['shots'] = sorted(d['bal'] or d['train'], key=lambda s: (len(s), s))
    return d


def stats(v):
    return [float(np.median(v)), float(np.percentile(v, 95))]


def folds(name, shots):
    if name == 'tos':
        return [[s for i, s in enumerate(shots) if i % 6 == f] for f in range(6)]
    return [[s] for s in shots]


@functools.lru_cache(maxsize=None)
def gains_for(cpath, name):
    C = candidate(cpath)
    d = data(name)
    space = d['meta'].get('space', 'display')
    g = C.balance({s: d['bal'][s] for s in d['shots']}, space)
    return {s: np.asarray(g.get(s, np.zeros(3)), np.float64) for s in d['shots']}


def job_fold(cpath, name, test):
    C = candidate(cpath)
    d = data(name)
    space, eotf = d['meta']['space'], d['meta']['eotf']
    G = gains_for(cpath, name)
    train = [(gm.enc(gm.apply_gains(d['train'][s][0], G[s])), d['train'][s][1]) for s in d['shots'] if s not in test]
    look = C.fit_look(train, space)
    out = {}
    for s in test:
        X, Y = d['eval'][s]
        pred = C.apply_look(look, gm.enc(gm.apply_gains(X, G[s])), space)
        r = {'de': stats(gm.de(pred, Y, eotf)), 'stops': float(np.dot(gm.LUMA, G[s]))}
        sub = slice(0, None, max(1, len(X) // 3000))
        best = None
        for e in np.arange(-2.0, 2.0001, 0.1):
            p = C.apply_look(look, gm.enc(gm.apply_gains(X[sub], G[s] + e)), space)
            m = float(np.mean(gm.de(p, Y[sub], eotf)))
            if best is None or m < best[0]:
                best = (m, e)
        e = round(float(best[1]), 2)
        r['oracle'] = e
        r['de_touch'] = stats(gm.de(C.apply_look(look, gm.enc(gm.apply_gains(X, G[s] + e)), space), Y, eotf))
        out[s] = r
    return name, out


def job_pst50(cpath, ids):
    C = candidate(cpath)
    d = data('pst50')
    out = {}
    for i in ids:
        look = C.fit_look([d['train'][i]], 'rec709')
        X, Y = d['eval'][i]
        out[i] = {'de': stats(gm.de(C.apply_look(look, X, 'rec709'), Y, 'srgb'))}
        for pair in CRIT['splits']['pst50_clusters']['dev'] + CRIT['splits']['pst50_clusters']['held']:
            ps = [str(p) for p in pair]
            if i in ps:
                t = ps[1 - ps.index(i)]
                Xt, Yt = d['eval'][t]
                out[i]['to_' + t] = stats(gm.de(C.apply_look(look, Xt, 'rec709'), Yt, 'srgb'))
    return 'pst50', out


def job_adacg(cpath):
    C = candidate(cpath)
    d = data('adacg')
    loc, tgt = d['meta']['loc'], d['meta']['target']
    out = {}
    for L in sorted(set(loc.values())):
        ks = [k for k in d['shots'] if loc[k] == L]
        g = C.balance({k: d['bal'][k] for k in ks}, 'display')
        for k in ks:
            e = float(np.dot(gm.LUMA, np.asarray(g.get(k, np.zeros(3)), np.float64)))
            out[k] = {'stops': e, 'target': tgt[k], 'err': abs(e - tgt[k])}
    return 'adacg', out


def summarise(R):
    S = CRIT['splits']
    T = {}
    for half in ('dev', 'held'):
        def pick(name, keys):
            held = set(S[name]['held'])
            return [k for k in keys if (k in held) == (half == 'held')]
        a = R['adacg']
        ks = pick('adacg', a)
        err = np.array([a[k]['err'] for k in ks])
        none = np.array([abs(a[k]['target']) for k in ks])
        T[f'exposure_adacg.{half}'] = {'median': float(np.median(err)), 'p90': float(np.percentile(err, 90)), 'n': len(ks),
                                       'no_change_median': float(np.median(none))}
        for name in FITTED + ('pst50',):
            r = R[name]
            ks = pick(name, r)
            row = {'median': float(np.median([r[k]['de'][0] for k in ks])), 'p95': float(np.median([r[k]['de'][1] for k in ks])), 'n': len(ks)}
            if name != 'pst50':
                row['oracle_abs_stops'] = float(np.median([abs(r[k]['oracle']) for k in ks]))
                row['touch_median'] = float(np.median([r[k]['de_touch'][0] for k in ks]))
            T[f'{name}.{half}'] = row
        tr = []
        for pair in S['pst50_clusters'][half]:
            a_, b_ = str(pair[0]), str(pair[1])
            tr += [R['pst50'][a_]['to_' + b_], R['pst50'][b_]['to_' + a_]]
        T[f'pst50_transfer.{half}'] = {'median': float(np.median([t[0] for t in tr])), 'p95': float(np.median([t[1] for t in tr])), 'n': len(tr)}
        T[f'look_composite.{half}'] = {'median': float(np.mean([T[f'{n}.{half}']['median'] for n in CRIT['look_composite']]))}
    return T


def table(name, T):
    lines = [f'## {name}', '', '| metric | dev median | dev p95/p90 | held median | held p95/p90 | n dev/held |', '|---|---|---|---|---|---|']
    for m in ['exposure_adacg'] + list(FITTED) + ['pst50', 'pst50_transfer', 'look_composite']:
        dv, hd = T[f'{m}.dev'], T[f'{m}.held']
        q = 'p90' if m.startswith('exposure') else 'p95'
        f = lambda r, k: f"{r[k]:.3f}" if k in r else '–'  # noqa: E731
        lines.append(f"| {m} | {f(dv, 'median')} | {f(dv, q)} | {f(hd, 'median')} | {f(hd, q)} | {dv.get('n', '–')}/{hd.get('n', '–')} |")
    lines += ['', 'info (not gated): exposure no change dev/held '
              f"{T['exposure_adacg.dev']['no_change_median']:.3f} / {T['exposure_adacg.held']['no_change_median']:.3f} stops; "
              + '; '.join(f"{n} oracle |stops| {T[n + '.dev']['oracle_abs_stops']:.2f}/{T[n + '.held']['oracle_abs_stops']:.2f}, "
                          f"touch-up ΔE {T[n + '.dev']['touch_median']:.2f}/{T[n + '.held']['touch_median']:.2f}" for n in FITTED)]
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('candidate')
    ap.add_argument('--jobs', type=int, default=10)
    a = ap.parse_args()
    cpath = os.path.abspath(a.candidate)
    name = os.path.splitext(os.path.basename(cpath))[0]
    t0 = time.time()
    tasks = [('adacg',)]
    for n in FITTED:
        for f in folds(n, _shots(n)):
            tasks.append(('fold', n, tuple(f)))
    ids = [str(i) for i in range(1, 51)]
    for k in range(10):
        tasks.append(('pst50', tuple(ids[k::10])))
    R = {n: {} for n in ('adacg',) + FITTED + ('pst50',)}
    with ProcessPoolExecutor(a.jobs) as ex:
        futs = []
        for t in tasks:
            if t[0] == 'adacg':
                futs.append(ex.submit(job_adacg, cpath))
            elif t[0] == 'fold':
                futs.append(ex.submit(job_fold, cpath, t[1], list(t[2])))
            else:
                futs.append(ex.submit(job_pst50, cpath, list(t[1])))
        for f in futs:
            n, out = f.result()
            R[n].update(out)
    T = summarise(R)
    day = datetime.date.today().isoformat()
    od = os.path.join(ROOT, day)
    os.makedirs(od, exist_ok=True)
    json.dump({'candidate': name, 'seconds': round(time.time() - t0), 'summary': T, 'per_shot': R}, open(os.path.join(od, name + '.json'), 'w'), indent=1)
    print(table(name, T))
    print(f'\n{round(time.time() - t0)} s; evidence {os.path.join(od, name + ".json")}')


def _shots(name):
    z = np.load(os.path.join(ROOT, 'cache', name + '.npz'), allow_pickle=False)
    return sorted({k.split('|')[1] for k in z.files if '|' in k}, key=lambda s: (len(s), s))


if __name__ == '__main__':
    main()
