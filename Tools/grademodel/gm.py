"""Shared maths for the grade model eval: S-Log3, CIELAB / ΔE2000, a smoothed 17³ LUT. Frozen with the evaluator.

Scene-linear values are what a balance gain multiplies; a look sees them through S-Log3 (`enc`), the curve Skim
reads Uday's clips in, so one look model works on every dataset (Sparks' ACES linear and Tears of Steel's plates
are put through the same curve)."""
import numpy as np
from scipy.sparse import coo_matrix, vstack as svstack
from scipy.sparse.linalg import lsqr

SLOG3_CUT = 171.2102946929
LUMA = np.array([0.2126, 0.7152, 0.0722])


def s3_lin(v):
    """S-Log3 code (0..1 of 10-bit) → scene-linear reflectance (Sony's formula)."""
    c = np.asarray(v, np.float64) * 1023
    return np.where(c >= SLOG3_CUT, 10 ** ((c - 420) / 261.5) * 0.19 - 0.01, (c - 95) * 0.01125 / (SLOG3_CUT - 95))


def lin_s3(x):
    x = np.asarray(x, np.float64)
    return np.where(x >= 0.01125, (420 + np.log10((np.maximum(x, 0.01125) + 0.01) / 0.19) * 261.5) / 1023,
                    (x * (SLOG3_CUT - 95) / 0.01125 + 95) / 1023)


def enc(lin):
    """Scene-linear → the look's input: S-Log3 code, clipped to the cube."""
    return np.clip(lin_s3(np.maximum(lin, -0.01)), 0, 1)


def apply_gains(lin, g):
    """log2 RGB gains on scene-linear pixels."""
    return lin * np.exp2(np.asarray(g, np.float64))[None, :]


# ---- CIELAB, ΔE2000
M709 = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
WD65 = M709.sum(1)


def to_lab(code, eotf='srgb'):
    """Display code (Rec.709 primaries, D65) → CIELAB. eotf 'srgb' (Uday, ToS, PST50) or 'g24' (Sparks, BT.1886)."""
    c = np.clip(code, 0, 1)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4) if eotf == 'srgb' else c ** 2.4
    xyz = lin @ M709.T / WD65
    f = np.where(xyz > (6 / 29) ** 3, np.cbrt(xyz), xyz / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def de2000(lab1, lab2):
    L1, a1, b1 = lab1[..., 0], lab1[..., 1], lab1[..., 2]
    L2, a2, b2 = lab2[..., 0], lab2[..., 1], lab2[..., 2]
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    dh = h2p - h1p
    dh = np.where(dh > 180, dh - 360, np.where(dh < -180, dh + 360, dh))
    dh = np.where(C1p * C2p == 0, 0, dh)
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh / 2))
    Lbp, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
    hs = h1p + h2p
    hbp = np.where(C1p * C2p == 0, hs, np.where(np.abs(h1p - h2p) <= 180, hs / 2,
                   np.where(hs < 360, (hs + 360) / 2, (hs - 360) / 2)))
    T = (1 - 0.17 * np.cos(np.radians(hbp - 30)) + 0.24 * np.cos(np.radians(2 * hbp))
         + 0.32 * np.cos(np.radians(3 * hbp + 6)) - 0.20 * np.cos(np.radians(4 * hbp - 63)))
    dth = 30 * np.exp(-(((hbp - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lbp - 50) ** 2 / np.sqrt(20 + (Lbp - 50) ** 2)
    Sc, Sh = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
    Rt = -np.sin(np.radians(2 * dth)) * Rc
    return np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


def de(code_a, code_b, eotf='srgb'):
    return de2000(to_lab(code_a, eotf), to_lab(code_b, eotf))


# ---- smoothed 17³ LUT (least squares, second-difference penalty; empty cells follow the smooth extension)
N = 17


def lut_weights(x, n=N):
    g = np.clip(x, 0, 1) * (n - 1)
    i0 = np.minimum(g.astype(int), n - 2)
    f = g - i0
    r, c, v = [], [], []
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                r.append(np.arange(len(x)))
                c.append(((i0[:, 0] + dx) * n + (i0[:, 1] + dy)) * n + (i0[:, 2] + dz))
                v.append(w)
    return coo_matrix((np.concatenate(v), (np.concatenate(r), np.concatenate(c))), shape=(len(x), n ** 3)).tocsr()


_LAP = {}


def lut_lap(n=N):
    if n in _LAP:
        return _LAP[n]
    r, c, v = [], [], []
    k = 0
    for a in range(n):
        for b in range(n):
            for d in range(n):
                for ax in range(3):
                    p = [a, b, d]
                    if 0 < p[ax] < n - 1:
                        lo = p.copy(); lo[ax] -= 1
                        hi = p.copy(); hi[ax] += 1
                        for q, w in ((lo, 1), (p, -2), (hi, 1)):
                            r.append(k); c.append((q[0] * n + q[1]) * n + q[2]); v.append(w)
                        k += 1
    _LAP[n] = coo_matrix((v, (r, c)), shape=(k, n ** 3)).tocsr()
    return _LAP[n]


def ident(n=N):
    return np.stack(np.meshgrid(*[np.linspace(0, 1, n)] * 3, indexing='ij'), -1).reshape(-1, 3)


def fit_lut(X, Y, lam=0.5, n=N, x0=None, w=None):
    """X, Y (k, 3) in 0..1. Optional prior table x0 (n³, 3): the penalty then pulls the residual from x0 smooth.
    Optional per-sample weights w."""
    A = lut_weights(X, n)
    Lp = lut_lap(n)
    base = ident(n) if x0 is None else x0
    if w is not None:
        sw = np.sqrt(np.asarray(w, np.float64))
        A = A.multiply(sw[:, None]).tocsr()
    else:
        sw = np.ones(len(X))
    M = svstack([A, lam * np.sqrt(len(X) / n ** 3) * Lp])
    lut = np.zeros((n ** 3, 3))
    for ch in range(3):
        rhs = np.concatenate([Y[:, ch] * sw, (lam * np.sqrt(len(X) / n ** 3) * (Lp @ base[:, ch])) if x0 is not None else np.zeros(Lp.shape[0])])
        lut[:, ch] = lsqr(M, rhs, x0=base[:, ch], atol=1e-7, btol=1e-7, iter_lim=400)[0]
    return lut


def apply_lut(lut, X, n=N):
    return lut_weights(X, n) @ lut


def upper_median(v):
    v = np.sort(np.asarray(v, np.float64).ravel())
    return float(v[v.size >> 1]) if v.size else 0.0
