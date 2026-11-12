"""Shared loading for the LLF prototype: Lightroom's own base export and its Highlights / Shadows
exports, cached at a small size in linear working RGB (sRGB primaries, the space fit.py uses).
Photos stay in ~/LuminaEvidence/llf-proto; nothing image-like is written to the repo."""
import json, os, pickle, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import delta_e  # noqa: E402
from PIL import Image  # noqa: E402

H = os.path.expanduser('~/LuminaEvidence/')
OUT = H + 'llf-proto/'
W = np.array([0.2126, 0.7152, 0.0722])
POS = [('Highlights', -100), ('Highlights', -50), ('Highlights', 50), ('Shadows', -50), ('Shadows', 50), ('Shadows', 100)]
EXCLUDE = {'DSC06742', 'DSC06841', 'DSC06842'}   # refs carry masks / crop (LR CC presets don't reset them)
PX = int(os.environ.get('LLF_PX', '512'))


def small(path, px=PX):
    a, s = delta_e.read_rgb01(path); h, w = a.shape[:2]
    shape = (round(px * h / w), px) if w >= h else (px, round(px * w / h))
    out = np.zeros(shape + (3,))
    for c in range(3):
        im = Image.fromarray((np.clip(a[..., c], 0, 1) * 65535).astype(np.uint16))
        out[..., c] = np.asarray(im.resize((shape[1], shape[0]), Image.BOX)).astype(np.float64) / 65535
    return delta_e.to_working_linear(out, s or 'srgb')


def lab(lin):
    return delta_e.xyz_to_lab(np.clip(lin, 0, 1) @ delta_e.SRGB_TO_XYZ.T, delta_e.D65)


def _sources():
    split = json.load(open(H + 'parity/death-valley/tone-split.json'))
    test = set(split['test'])
    dv = os.path.realpath(H + 'local/parity/dv-tone/base-refs')
    out = []
    for f in sorted(os.listdir(dv)):
        stem = f.split('__')[0]
        if stem in EXCLUDE: continue
        refdir = H + ('local/parity/dv-tone/unseen-refs' if stem in test else 'parity/dv-tone/refs')
        alt = H + 'parity/dv-tone/refs'
        pos = {}
        for sl, v in POS:
            p = f'{refdir}/{stem}__{sl}__{v}.jpg'
            if not os.path.exists(p): p = f'{alt}/{stem}__{sl}__{v}.jpg'
            pos[(sl, v)] = p
        out.append(('dv', stem, 'unseen' if stem in test else 'dev', f'{dv}/{f}', pos))
    sw = H + 'local/parity/sweep/refs'
    for stem in ['DSC05860', 'DSC05917', 'DSC06215', 'DSC06490', 'DSC06707']:
        out.append(('sweep', stem, 'sweep', f'{sw}/{stem}__base.jpg', {(sl, v): f'{sw}/{stem}__{sl}__{v}.jpg' for sl, v in POS}))
    return out


def load():
    pk = OUT + f'cache{PX}.pkl'
    if os.path.exists(pk): return pickle.load(open(pk, 'rb'))
    P = []
    for setname, stem, half, base, pos in _sources():
        if not all(os.path.exists(p) for p in [base, *pos.values()]):
            print('missing', stem, file=sys.stderr); continue
        b = small(base).astype(np.float32)
        ph = {'set': setname, 'stem': stem, 'half': half, 'base': b, 'pairs': {}}
        ok = True
        for k, p in pos.items():
            r = small(p).astype(np.float32)
            if r.shape != b.shape: ok = False; break
            ph['pairs'][k] = r
        if ok: P.append(ph)
    pickle.dump(P, open(pk, 'wb'))
    return P


def score(ref_lin, out_lin):
    """ΔE2000 per pixel, the delta_e.py way (3 × 3 median on both, CIELAB D65)."""
    return delta_e.delta_e2000(lab(delta_e.median3(ref_lin)), lab(delta_e.median3(np.clip(out_lin, 0, 1))))
