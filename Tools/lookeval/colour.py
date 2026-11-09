"""Colour and fitting helpers shared by the look eval: sRGB → CIELAB, ΔE2000, the 32 px checkerboard split, and a
smoothed 3D LUT (used only to put a log clip frame through the same Rec.709 conversion as its PST50 pair). Adapted from the
PST50 measurement scripts (2026-10-30) so the numbers line up with theirs."""
import os
import numpy as np
from PIL import Image
import scipy.sparse as sp
from scipy.sparse.linalg import lsqr

D = os.environ.get('LUMINA_PST50', '/Volumes/T7/Lumina/datasets/pst50').rstrip('/') + '/'
IDS = list(range(1, 51))
SCALE = (960, 540)  # half res: 518k px per frame


def load(path, size=SCALE):
    im = Image.open(path).convert('RGB')
    if size:
        im = im.resize(size, Image.BILINEAR)
    return np.asarray(im).astype(np.float64) / 255.0


def pair(i, size=SCALE):
    return dict(log=load(f'{D}content_log/in{i}.png', size), r709=load(f'{D}content_709/in{i}.png', size),
                style=load(f'{D}paired_style/tar{i}.png', size), gt=load(f'{D}paired_gt/gt{i}.png', size))


# ---- colour: treat display-referred frames as sRGB-encoded Rec.709 primaries, D65
M_RGB2XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                      [0.2126729, 0.7151522, 0.0721750],
                      [0.0193339, 0.1191920, 0.9503041]])
WHITE = M_RGB2XYZ.sum(1)


def srgb_to_lab(rgb):
    c = np.clip(rgb, 0, 1)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = lin @ M_RGB2XYZ.T / WHITE
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
    dth = 30 * np.exp(-((hbp - 275) / 25) ** 2)
    RC = 2 * np.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    SL = 1 + 0.015 * (Lbp - 50) ** 2 / np.sqrt(20 + (Lbp - 50) ** 2)
    SC, SH = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
    RT = -np.sin(np.radians(2 * dth)) * RC
    return np.sqrt((dLp / SL) ** 2 + (dCp / SC) ** 2 + (dHp / SH) ** 2 + RT * (dCp / SC) * (dHp / SH))


def de(rgb1, rgb2):
    return de2000(srgb_to_lab(rgb1), srgb_to_lab(rgb2))


def stats(d):
    d = np.asarray(d).ravel()
    return float(np.median(d)), float(np.percentile(d, 95))


# ---- spatial split: 32 px checkerboard blocks; fit on A, score on B
def split_mask(h, w, block=32):
    yy, xx = np.mgrid[0:h, 0:w]
    return ((yy // block + xx // block) % 2 == 0)


class LUT3D:
    """N^3 trilinear LUT fitted by least squares with a second-difference smoothness penalty
    (empty cells follow the smooth extension)."""
    name = 'smoothed LUT'

    def __init__(self, N=33, lam=0.05):
        self.N, self.lam = N, lam

    def weights(self, x):
        N = self.N
        t = np.clip(x, 0, 1) * (N - 1)
        i0 = np.minimum(np.floor(t).astype(int), N - 2)
        f = t - i0
        rows, cols, vals = [], [], []
        n = len(x)
        for dr in (0, 1):
            for dg in (0, 1):
                for db in (0, 1):
                    w = ((f[:, 0] if dr else 1 - f[:, 0]) * (f[:, 1] if dg else 1 - f[:, 1])
                         * (f[:, 2] if db else 1 - f[:, 2]))
                    idx = ((i0[:, 0] + dr) * N + (i0[:, 1] + dg)) * N + (i0[:, 2] + db)
                    rows.append(np.arange(n)); cols.append(idx); vals.append(w)
        return sp.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, N ** 3))

    def smooth_op(self):
        N = self.N
        I = sp.identity(N, format='csr')
        d2 = sp.diags([1, -2, 1], [0, 1, 2], shape=(N - 2, N), format='csr')
        ops = [sp.kron(sp.kron(d2, I), I), sp.kron(sp.kron(I, d2), I), sp.kron(sp.kron(I, I), d2)]
        return sp.vstack(ops).tocsr()

    def fit(self, x, y):
        A = self.weights(x)
        S = self.smooth_op()
        # scale smoothness against data count so lam means the same at any sample size
        s = np.sqrt(self.lam * len(x) / S.shape[0])
        M = sp.vstack([A, s * S]).tocsr()
        z = np.zeros(S.shape[0])
        self.T = np.stack([lsqr(M, np.r_[y[:, c], z], atol=1e-6, btol=1e-6, iter_lim=3000)[0] for c in range(3)], 1)
        return self

    def __call__(self, x):
        return self.weights(x) @ self.T


