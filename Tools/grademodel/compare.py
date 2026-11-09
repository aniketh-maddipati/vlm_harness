#!/usr/bin/env python3
"""Check a candidate against the incumbent under criteria.json's adopt rule. Prints every delta and a verdict.

    python3 Tools/grademodel/compare.py <incumbent.json> <candidate.json>

The judge (a subagent that did not write the candidate) reads this with both tables and decides; this script is
the rule written out, so the decision can be checked."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def check(inc, cand, crit):
    A = crit['adopt']
    tol = A['held_tolerance']
    I, C = inc['summary'], cand['summary']
    lines, ok = [], True
    d_exp = C['exposure_adacg.dev']['median'] - I['exposure_adacg.dev']['median']
    d_look = C['look_composite.dev']['median'] - I['look_composite.dev']['median']
    lines.append(f'dev exposure  {I["exposure_adacg.dev"]["median"]:.3f} → {C["exposure_adacg.dev"]["median"]:.3f} ({d_exp:+.3f} stops)')
    lines.append(f'dev look      {I["look_composite.dev"]["median"]:.3f} → {C["look_composite.dev"]["median"]:.3f} ({d_look:+.3f} ΔE)')
    better_exp = d_exp <= -A['min_gain']['stops']
    better_look = d_look <= -A['min_gain']['de']
    improves = (better_exp and d_look <= tol['de_median']) or (better_look and d_exp <= tol['stops_median'])
    lines.append(f'dev improves: {"yes" if improves else "no"}')
    ok &= improves
    for row in A['held_rows']:
        r = f'{row}.held'
        if row == 'exposure_adacg':
            d = C[r]['median'] - I[r]['median']
            good = d <= tol['stops_median']
            lines.append(f'{r:24s} median {I[r]["median"]:.3f} → {C[r]["median"]:.3f} ({d:+.3f}) {"ok" if good else "FAIL"}')
            ok &= good
        else:
            for k, t in (('median', tol['de_median']), ('p95', tol['de_p95'])):
                d = C[r][k] - I[r][k]
                good = d <= t
                lines.append(f'{r:24s} {k:6s} {I[r][k]:.3f} → {C[r][k]:.3f} ({d:+.3f}) {"ok" if good else "FAIL"}')
                ok &= good
    lines.append('VERDICT (rule): ' + ('ADOPT' if ok else 'REJECT'))
    return ok, '\n'.join(lines)


if __name__ == '__main__':
    crit = json.load(open(os.path.join(HERE, 'criteria.json')))
    ok, text = check(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), crit)
    print(text)
