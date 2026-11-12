import numpy as np
from common import load
from today import apply_today
from measure import oklab
P = load()
for v in [-100, 50]:
    for clipcut in [1.01, 0.97, 0.9]:
        num = {}; den = {}
        for ph in P:
            if ph['set'] != 'dv': continue
            base = ph['base'].astype(np.float64); ref = ph['pairs'][('Highlights', v)].astype(np.float64)
            out = apply_today(base, v, 0); Lr, Lo = oklab(ref), oklab(out); Lb = oklab(base)
            Cr, Co = np.hypot(Lr[..., 1], Lr[..., 2]), np.hypot(Lo[..., 1], Lo[..., 2])
            ok = (Co > 0.02) & (Cr > 0.005) & (ref.max(-1) < 0.98) & (base.max(-1) < clipcut)
            lr = np.log2(Cr[ok] / Co[ok]); w = Co[ok]; i = np.digitize(Lb[..., 0][ok], np.linspace(0, 1, 21))
            for j in np.unique(i):
                m = i == j; num[j] = num.get(j, 0) + (lr[m] * w[m]).sum(); den[j] = den.get(j, 0) + w[m].sum()
        print(v, clipcut, 'by base L:', ' '.join(f'{(j-1)*0.05:.2f}:{num[j]/den[j]:+.2f}' for j in sorted(num) if den[j] > 1))
