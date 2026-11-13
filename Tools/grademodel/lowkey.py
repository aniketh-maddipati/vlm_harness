#!/usr/bin/env python3
"""Low-key shots, reported apart (info, not gated): ⇧E's known risk is lifting a dark shot too far.

    ~/LuminaEvidence/venv-parity/bin/python -I Tools/grademodel/lowkey.py <incumbent.json> <candidate.json>

Which shots count is fixed, not up to a candidate:
  adaCG   every shot whose labels include `night` (the annotator's relative middle as target; dev and held apart);
  look    Sparks, Tears of Steel and Uday's shots whose log-mean scene light (the page as of LOCAL-CHANGES 325, run
          through page.mjs on the evaluator's cached frames) sits at least LOWKEY stops below its shoot's median.
Per shot: ⇧E's stops, |stops − target| or ΔE median, and the oracle (the extra gain that would fit best).
"""
import json
import math
import os
import statistics
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'exposeval'))
import page as P  # noqa: E402
import page_parity as PP  # noqa: E402

ROOT = os.environ.get('LUMINA_GRADEMODEL', os.path.expanduser('~/LuminaEvidence/grademodel'))
CRIT = json.load(open(os.path.join(HERE, 'criteria.json')))
LOWKEY = 0.5  # stops below the shoot's median
SETS = ('sparks', 'tos', 'uday')
PAGE_325 = ()  # the page as of 325 is the repo's page; if a later change moves sceneSl, patch it back here so the set stays fixed


def keys(name):
    """shot → its log-mean scene light in stops against the shoot's median (the page as of 325, no patch)."""
    out = P.run_page(PP.cache_shoot(os.path.join(ROOT, 'cache', name + '.npz')), patches=PAGE_325)
    v = {k: sorted(x)[len(x) >> 1] for k, x in out['sl'].items()}
    mid = sorted(v.values())[len(v) >> 1]
    return {k: math.log2(x / mid) for k, x in v.items()}


def night_shots(pkl=PP.PKL):
    import adacg as A
    E = A.entries(A.load(pkl))
    return sorted({str(A.shot_of(n)) for n, e in E.items() if 'night' in e['labels']}, key=int)


def main(a, b):
    inc, cand = json.load(open(a)), json.load(open(b))
    held = {n: set(CRIT['splits'][n]['held']) for n in ('adacg',) + SETS}
    lines = [f"## Low-key shots: {inc['candidate']} → {cand['candidate']}", '']
    ni = night_shots()
    lines += ['adaCG `night` (|stops − annotator| median; signed bias median)', '',
              '| half | n | |err| | bias (stops − target) |', '|---|---|---|---|']
    for half in ('dev', 'held'):
        ks = [k for k in ni if k in inc['per_shot']['adacg'] and (k in held['adacg']) == (half == 'held')]
        e0 = [inc['per_shot']['adacg'][k]['err'] for k in ks]
        e1 = [cand['per_shot']['adacg'][k]['err'] for k in ks]
        b0 = [inc['per_shot']['adacg'][k]['stops'] - inc['per_shot']['adacg'][k]['target'] for k in ks]
        b1 = [cand['per_shot']['adacg'][k]['stops'] - cand['per_shot']['adacg'][k]['target'] for k in ks]
        lines.append(f'| {half} | {len(ks)} | {np.median(e0):.3f} → {np.median(e1):.3f} | {np.median(b0):+.3f} → {np.median(b1):+.3f} |')
    lines += ['', f'Look shots ≥ {LOWKEY} stop under their shoot (ΔE median; ⇧E stops; oracle extra stops)', '',
              '| set | shot | half | key | ⇧E stops | ΔE median | oracle |', '|---|---|---|---|---|---|---|']
    deltas = {'dev': [], 'held': []}
    for n in SETS:
        if n not in inc['per_shot']:
            continue
        K = keys(n)
        for s in sorted((s for s in K if K[s] <= -LOWKEY), key=lambda s: K[s]):
            r0, r1 = inc['per_shot'][n][s], cand['per_shot'][n][s]
            half = 'held' if s in held[n] else 'dev'
            deltas[half].append(r1['de'][0] - r0['de'][0])
            name = s if n != 'uday' else f'shot {s}'
            lines.append(f"| {n} | {name} | {half} | {K[s]:+.2f} | {r0['stops']:+.2f} → {r1['stops']:+.2f} | "
                         f"{r0['de'][0]:.2f} → {r1['de'][0]:.2f} | {r0['oracle']:+.1f} → {r1['oracle']:+.1f} |")
    for half, d in deltas.items():
        if d:
            lines.append(f'\n{half}: median per-shot ΔE change {statistics.median(d):+.3f} over {len(d)} low-key shots '
                         f'({sum(x < 0 for x in d)} better, {sum(x > 0 for x in d)} worse)')
    print('\n'.join(lines))


if __name__ == '__main__':
    main(*sys.argv[1:3])
