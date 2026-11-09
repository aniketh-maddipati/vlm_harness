"""PST50: how much of a professional grade Skim's own look sliders reproduce, and whether a look fitted on one graded
frame carries to another shot. Measures only: reads the PST50 PNGs and clips, writes JSON to the evidence folder.

  python -I -W ignore Tools/lookeval/pst50.py pairs [k n]   # every pair (worker k of n); resumable, one JSON per pair
  python -I -W ignore Tools/lookeval/pst50.py transfer      # look clusters + the style-source clips
  python -I -W ignore Tools/lookeval/pst50.py cross [k n]   # each pair's look applied to every other pair
Evidence: $LUMINA_LOOKEVAL (default ~/LuminaEvidence/lookeval).

Inputs, as the page would see them:
  A  content_709, mode 0 ("as shot"): the clip reaches Skim already in Rec.709 (PST50's own technical conversion).
  B  content_log, mode 1 (S-Log3 → Rec.709 table): what Skim does with a clip it reads as S-Log3. PST50 does not name
     its log curve, so B assumes S-Log3; Exposure is then the page's code shift, not a gain.
Scores: ΔE2000 on the 32 px checkerboard blocks the fit never saw (960×540), the page's own maths with the stored
(rounded) slider values.
"""
import os, sys, json, glob, time, subprocess, shutil
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lookmath as lm
import fit as F
from colour import D, IDS, load, pair, split_mask, de, stats, LUT3D

OUT = os.environ.get('LUMINA_LOOKEVAL', os.path.expanduser('~/LuminaEvidence/lookeval'))
NFIT = 6000
MASK = split_mask(540, 960)
HELD = ~MASK
FF = shutil.which('ffmpeg') or '/usr/local/bin/ffmpeg'


def r2(t):
    return [round(float(v), 3) for v in t]


def save(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(obj, f, indent=1)
    os.replace(tmp, path)


def one_pair(i):
    p = pair(i)
    res = {'id': i, 'tech709': r2(stats(de(p['r709'], p['gt'])[HELD]))}
    t0 = time.time()
    for key, src, mode in (('A', p['r709'], 0), ('B', p['log'], 1)):
        xs, ys = F.sample(src, p['gt'], MASK, NFIT, seed=i)
        R = {'rest': r2(F.score({}, src, p['gt'], HELD, mode))}
        G = F.fit_stage(xs, ys, mode, 'global')
        R['global'] = {'look': G, 'held': r2(F.score(G, src, p['gt'], HELD, mode)), 'fit': r2(F.score(G, src, p['gt'], MASK, mode))}
        stages = ('mix', 'grade', 'full') if key == 'A' else ('full',)
        for st in stages:
            L = F.fit_stage(xs, ys, mode, st, G)
            R[st] = {'look': L, 'held': r2(F.score(L, src, p['gt'], HELD, mode)), 'fit': r2(F.score(L, src, p['gt'], MASK, mode))}
        if key == 'A':
            full = R['full']['look']
            R['zero'], R['drop'], R['only'] = {}, {}, {}
            for g in F.GROUPS:
                # zero: the full look with this group back at rest (no refit)
                Z = {k: v for k, v in full.items() if k not in F.GROUPS[g]}
                R['zero'][g] = r2(F.score(Z, src, p['gt'], HELD, mode))
                # drop: refit everything else without it
                rest = [x for x in F.STAGES['full'] if x != g]
                Ld = F.fit(xs, ys, mode, rest, Z)
                R['drop'][g] = r2(F.score(Ld, src, p['gt'], HELD, mode))
                # only: this group alone, from rest (Exposure gets the three starts)
                Lo = F.fit_stage(xs, ys, mode, [g]) if g == 'ev' else F.fit(xs, ys, mode, [g], {})
                R['only'][g] = r2(F.score(Lo, src, p['gt'], HELD, mode))
        res[key] = R
    res['seconds'] = round(time.time() - t0, 1)
    return res


def run_pairs(k, n):
    for i in IDS:
        if i % n != k:
            continue
        path = f'{OUT}/pairs/pair_{i}.json'
        if os.path.exists(path):
            continue
        r = one_pair(i)
        save(path, r)
        print(f"pair {i}: tech709 {r['tech709'][0]} · A global {r['A']['global']['held'][0]} full {r['A']['full']['held'][0]}"
              f" · B global {r['B']['global']['held'][0]} full {r['B']['full']['held'][0]} ({r['seconds']} s)", flush=True)


def pair_looks():
    out = {}
    for f in glob.glob(f'{OUT}/pairs/pair_*.json'):
        r = json.load(open(f))
        out[r['id']] = r
    return out


# ---- transfer
CLUSTERS = [(2, 21), (44, 46), (4, 39), (30, 36)]  # the PST50 look clusters (summary.json, LUT cross ΔE < 2 / < 3)
CLIPS = [29, 37, 46]  # clips whose matching frame is the style shot tarN (pst50 clips/clip_N.json, grad-corr 0.79–0.97)


def clip_frame(i):
    """The clip frame that matches tarN (searched ±0.3 s around the PST50 match time), 960×540 full range, cached."""
    path = f'{OUT}/frames/clip{i}.png'
    if os.path.exists(path):
        return load(path, None)
    info = json.load(open(f'{D}clips/clip_{i}.json'))
    vid = glob.glob(f'{D}video/in{i}.*')[0]
    tmp = f'{OUT}/frames/tmp{i}'
    shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
    subprocess.run([FF, '-v', 'error', '-y', '-ss', f"{max(0, info['match_t'] - 0.3):.3f}", '-i', vid, '-t', '0.6',
                    '-vf', 'scale=960:540:in_range=tv:out_range=pc,format=rgb24', f'{tmp}/f%04d.png'], check=True)
    T = gnorm(load(f'{D}paired_style/tar{i}.png'))
    best = max(sorted(glob.glob(f'{tmp}/f*.png')), key=lambda f: float(np.mean(gnorm(load(f, None)) * T)))
    shutil.copy(best, path)
    shutil.rmtree(tmp)
    return load(path, None)


def gnorm(a):
    g = np.hypot(*np.gradient(a.mean(2)))
    return (g - g.mean()) / (g.std() + 1e-9)


def fit_full(src, dst, mode, seed=0):
    xs, ys = F.sample(src, dst, MASK, NFIT, seed=seed)
    G = F.fit_stage(xs, ys, mode, 'global')
    return G, F.fit_stage(xs, ys, mode, 'full', G)


def lut_fit(src, dst, seed=0):
    xs, ys = F.sample(src, dst, MASK, 150000, seed=seed)
    return LUT3D(33, 0.1).fit(xs, ys)


def apply_lut(lut, img):
    return np.clip(lut(img.reshape(-1, 3)), 0, 1).reshape(img.shape)


def run_transfer():
    P = pair_looks()
    res = {'clusters': [], 'clips': []}
    # (1) look clusters: fit on pair a, apply to pair b (both directions). Mode A, plus a LUT for scale.
    for a, b in CLUSTERS:
        for s, t in ((a, b), (b, a)):
            ps, pt = pair(s), pair(t)
            row = {'from': s, 'to': t, 'tech709': r2(stats(de(pt['r709'], pt['gt'])[HELD]))}
            for st in ('global', 'full'):
                L = P[s]['A'][st]['look']
                row[st] = r2(F.score(L, pt['r709'], pt['gt'], HELD, 0))
                row[st + '_own'] = P[t]['A'][st]['held']
            row['lut709'] = r2(stats(de(apply_lut(lut_fit(ps['r709'], ps['gt']), pt['r709']), pt['gt'])[HELD]))
            res['clusters'].append(row)
            print('cluster', row, flush=True)
    # (2) clips: content N graded = gtN; the clip's frame graded = tarN, the style shot of the same look.
    for i in CLIPS:
        p = pair(i)
        V = clip_frame(i)
        tar = load(f'{D}paired_style/tar{i}.png')
        to709 = lut_fit(p['log'], p['r709'])  # PST50's own log → 709 conversion, as fitted on the content frame
        V709 = apply_lut(to709, V)
        row = {'id': i, 'clip_tech709_vs_tar': r2(stats(de(V709, tar)[HELD]))}
        for key, src_c, src_v, mode in (('A', p['r709'], V709, 0), ('B', p['log'], V, 1)):
            Gc, Lc = (P[i][key]['global']['look'], P[i][key]['full']['look'])
            Gv, Lv = fit_full(src_v, tar, mode, seed=i)
            row[key] = {
                'content_own': {'global': P[i][key]['global']['held'], 'full': P[i][key]['full']['held']},
                'clip_own': {'global': r2(F.score(Gv, src_v, tar, HELD, mode)), 'full': r2(F.score(Lv, src_v, tar, HELD, mode))},
                'content_to_clip': {'global': r2(F.score(Gc, src_v, tar, HELD, mode)), 'full': r2(F.score(Lc, src_v, tar, HELD, mode))},
                'clip_to_content': {'global': r2(F.score(Gv, src_c, p['gt'], HELD, mode)), 'full': r2(F.score(Lv, src_c, p['gt'], HELD, mode))},
                'clip_look': Lv,
            }
        lc, lv = lut_fit(p['r709'], p['gt']), lut_fit(V709, tar)
        row['lut709'] = {'content_to_clip': r2(stats(de(apply_lut(lc, V709), tar)[HELD])),
                         'clip_to_content': r2(stats(de(apply_lut(lv, p['r709']), p['gt'])[HELD]))}
        res['clips'].append(row)
        print('clip', i, json.dumps({k: row[k] for k in row if k in ('clip_tech709_vs_tar', 'lut709')}),
              json.dumps({k: {kk: vv for kk, vv in row[k].items() if kk != 'clip_look'} for k in ('A', 'B')}), flush=True)
    save(f'{OUT}/transfer.json', res)


def run_cross(k, n):
    """Every pair's fitted look applied to every other pair (mode A) on a fixed 20k sample of held-out pixels."""
    P = pair_looks()
    r = np.random.default_rng(0)
    idx = np.flatnonzero(HELD.ravel())
    sel = r.choice(idx, 20000, replace=False)
    srcs, gts = {}, {}
    for i in IDS:
        p = pair(i)
        srcs[i], gts[i] = p['r709'].reshape(-1, 3)[sel], p['gt'].reshape(-1, 3)[sel]
    for s in IDS:
        if s % n != k:
            continue
        path = f'{OUT}/cross/from_{s}.json'
        if os.path.exists(path):
            continue
        row = {}
        for st in ('global', 'full'):
            L = P[s]['A'][st]['look']
            row[st] = {t: round(float(np.median(de(lm.preview(srcs[t], L, 0), gts[t]))), 3) for t in IDS}
        save(path, row)
        print('cross from', s, flush=True)


if __name__ == '__main__':
    cmd = sys.argv[1]
    k, n = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (0, 1)
    {'pairs': lambda: run_pairs(k, n), 'transfer': run_transfer, 'cross': lambda: run_cross(k, n)}[cmd]()
