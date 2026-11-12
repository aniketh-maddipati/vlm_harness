"""Ceiling: a per-photo chroma LUT over the anchored mask luma, fitted on the answer, on top of today's
tone output (what any chroma-only term on today's curve could reach)."""
import numpy as np
from common import load, W, score
from today import apply_today, RULES
from measure import oklab
import lookmath as lm
from diag import lut1
P = load(); rows = {}
for ph in P:
    base = ph['base'].astype(np.float64); an = lm.tone_anchor(base, RULES); nh = lm.tone_normalisers(an, RULES)[1]
    x = np.power(np.maximum(base @ W * nh, 0), 1 / 2.2)
    for v in [-100, -50, 50]:
        ref = ph['pairs'][('Highlights', v)].astype(np.float64); out = apply_today(base, v, 0)
        yo = out @ W; yr = ref @ W
        cr = np.log2(np.maximum(np.linalg.norm(ref - yr[..., None], axis=-1), 1e-5) / np.maximum(np.linalg.norm(out - yo[..., None], axis=-1), 1e-5))
        cs = 2 ** lut1(x.ravel(), np.clip(cr, -3, 3).ravel()).reshape(x.shape)
        o2 = yo[..., None] + (out - yo[..., None]) * cs[..., None]
        rows.setdefault((v, ph['half']), []).append(score(ref, o2).ravel())
for k in sorted(rows):
    a = np.concatenate(rows[k]); print('oracle', k, f'{np.median(a):.2f} / {np.percentile(a, 95):.2f}', flush=True)
