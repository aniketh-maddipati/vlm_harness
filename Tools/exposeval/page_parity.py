#!/usr/bin/env python3
"""The page's ⇧E (page.mjs, the page's own JavaScript) against rule.py's numpy copy, on the same 8-bit frames.

    ~/LuminaEvidence/venv-parity/bin/python -I Tools/exposeval/page_parity.py \
        [--pkl …/trainDemo8b.pkl.UNTRUSTED-do-not-unpickle] [--cache ~/LuminaEvidence/grademodel/cache] [--tol 1e-6]

Per frame |log2(page / rule)| and per clip |Exposure page − rule| (stops), on the adaCG label stills (each location
a shoot, each video's two stills a clip) and on the Sparks / Tears of Steel frames the grade model balances (each
set a shoot; their scene-linear samples go back to the 8-bit S-Log3 codes Skim reads). Exit 1 if either is over
the tolerance. Prints numbers only.
"""
import argparse
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import page as P  # noqa: E402
import rule  # noqa: E402

PKL = '/Volumes/T7/Lumina/datasets/hdrvs-adacg/trainDemo8b.pkl.UNTRUSTED-do-not-unpickle'
CACHE = os.path.expanduser('~/LuminaEvidence/grademodel/cache')


def as_frame(f):
    """What rule.py reads for a frame page.mjs gets: a Sampled frame is rebuilt with each pixel at every 8th place."""
    if isinstance(f, P.Sampled):
        a = np.zeros((f.codes.shape[0] * 8, 1, f.codes.shape[1]), np.uint8)
        a[::8, 0] = f.codes
        return a
    return f


def compare(clips, patches=(), stat=rule.scene_sl_logmean):
    """clips {id: (slog3, [frames])} (one shoot) → (max frame Δ stops, max clip Δ stops, page output)."""
    out = P.run_page(clips, patches=patches)
    vals, dframe = {}, 0.0
    for cid, (slog3, frames) in clips.items():
        t = rule.level_table('slog3' if slog3 else 'rec709')
        py = [stat(as_frame(f), t) for f in frames]
        js = out['sl'][str(cid)]
        for a, b in zip(js, py):
            if a > 0 and b > 0:
                dframe = max(dframe, abs(math.log2(a / b)))
            elif a != b:
                dframe = math.inf
        vals[str(cid)] = rule.clip_value(py)
    ev = rule.ev_auto_map(vals)
    if set(ev) != set(out['ev']):
        return dframe, math.inf, out
    dclip = max((abs(ev[k] - out['ev'][k]) for k in ev), default=0.0)
    return dframe, dclip, out


def adacg_shoots(pkl):
    import adacg as A
    from run import decode_thumb, location_of
    E = A.entries(A.load(pkl))
    shoots = {}
    for name, e in sorted(E.items()):
        loc = location_of(list(e['labels']))
        shoots.setdefault(loc, {}).setdefault(str(A.shot_of(name)), (False, []))[1].append(decode_thumb(e['thumb']))
    return shoots


def cache_shoot(path):
    z = np.load(path, allow_pickle=False)
    clips = {}
    for k in sorted((k for k in z.files if k.startswith('bal|')), key=lambda k: (k.split('|')[1], int(k.split('|')[2]))):
        s = k.split('|')[1]
        clips.setdefault(s, (True, []))[1].append(P.Sampled(P.slog3_codes(z[k].astype(np.float64))))
    return clips


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--pkl', default=PKL)
    ap.add_argument('--cache', default=CACHE)
    ap.add_argument('--tol', type=float, default=1e-6)
    a = ap.parse_args(argv)
    rows = []
    if os.path.exists(a.pkl):
        for loc, clips in sorted(adacg_shoots(a.pkl).items()):
            rows.append((f'adacg {loc}', len(clips), sum(len(f) for _, f in clips.values())) + compare(clips)[:2])
    else:
        print('adacg: no', a.pkl)
    for name in ('sparks', 'tos'):
        p = os.path.join(a.cache, name + '.npz')
        if os.path.exists(p):
            clips = cache_shoot(p)
            rows.append((name, len(clips), sum(len(f) for _, f in clips.values())) + compare(clips)[:2])
        else:
            print(name + ': no', p)
    print('| shoot | clips | frames | max frame Δ (stops) | max clip Δ (stops) |\n|---|---|---|---|---|')
    for r in rows:
        print(f'| {r[0]} | {r[1]} | {r[2]} | {r[3]:.2e} | {r[4]:.2e} |')
    bad = [r for r in rows if not (r[3] <= a.tol and r[4] <= a.tol)]
    print(('FAIL ' + ', '.join(r[0] for r in bad)) if bad else f'PASS {len(rows)} shoots within {a.tol:g} stops' if rows else 'NO DATA')
    return 1 if bad or not rows else 0


if __name__ == '__main__':
    sys.exit(main())
