"""Mine (linear, 6 numbers) vs the LLF session's Oklab form (03d9d6c9, 2 numbers) on LR base → LR Highlights,
all pixels and only pixels whose base has no channel ≥ 0.97 (is either fitted to clipped pixels?)."""
import numpy as np
from common import load, W, score
from today import apply_today
from measure import oklab, M1, M2
import lookmath as lm, json
RULES = json.load(open('../../../Lumina/Sets/Look/rules-v1.json'))
iM1, iM2 = np.linalg.inv(M1), np.linalg.inv(M2)
def theirs(out, base, hl):
    k = -0.354 if hl < 0 else -0.819
    Lb = oklab(base)[..., 0]; t = np.clip((Lb - 0.75) / 0.25, 0, 1); m = t * t * (3 - 2 * t)
    o = oklab(out); o[..., 1:] *= (2 ** (hl / 100 * k * m))[..., None]
    return (o @ iM2.T) ** 3 @ iM1.T
def mine(out, base, hl):
    return lm.tone_chroma(out, base @ W, hl, RULES)
P = load(); R = {}
for ph in P:
    base = ph['base'].astype(np.float64); clip = base.max(-1) >= 0.97
    for v in [-100, -50, 50]:
        ref = ph['pairs'][('Highlights', v)].astype(np.float64); out = apply_today(base, v, 0)
        for name, o in [('today', out), ('mine', mine(out, base, v)), ('theirs', theirs(out, base, v))]:
            e = score(ref, o)
            R.setdefault((v, ph['half'], name, 'all'), []).append(e.ravel())
            R.setdefault((v, ph['half'], name, 'unclipped'), []).append(e[~clip].ravel())
for k in sorted(R):
    a = np.concatenate(R[k]); print(k, f'{np.median(a):.2f} / {np.percentile(a, 95):.2f}', flush=True)
