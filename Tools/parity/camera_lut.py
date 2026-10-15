#!/usr/bin/env python3
"""The camera profile as a learned 3D colour table per Creative Style, against today's form.

    python3 Tools/parity/camera_lut.py [--sizes 9 17] [--smooth 0.3] [--out ~/LuminaEvidence/camera-profile]

Same data and split as camera_fit.py (its index, renders and camera JPEGs; train shoots / held-out
shoots). Per style, a table of n³ nodes maps Lumina's base (sRGB-encoded) to the camera's JPEG,
read with trilinear interpolation (what Core Image's CIColorCube does). It is linear in its nodes, so
it is solved exactly: data term + a smoothness term between neighbouring nodes + a pull toward the
identity where no data falls. The grey axis is pinned: diagonal nodes get one value for all three
channels, so a grey stays grey. Reported on the held-out photos next to the base match form with the
numbers in rules-v1.json, ΔE2000 per photo (median of medians / median of p95s). Measures only.
"""
import argparse
import json
import os
import sys

import numpy as np
from scipy.sparse import coo_matrix, diags, vstack
from scipy.sparse.linalg import spsolve

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import camera_fit as cf  # noqa: E402
import delta_e  # noqa: E402
import lookmath  # noqa: E402


def weights(x, n):
    """Trilinear weights of points x (N, 3) in 0..1 on an n³ grid: a sparse (N, n³) matrix."""
    g = np.clip(x, 0, 1) * (n - 1)
    i0 = np.minimum(np.floor(g).astype(int), n - 2)
    f = g - i0
    rows, cols, vals = [], [], []
    for dr in (0, 1):
        for dg in (0, 1):
            for db in (0, 1):
                w = (f[:, 0] if dr else 1 - f[:, 0]) * (f[:, 1] if dg else 1 - f[:, 1]) * (f[:, 2] if db else 1 - f[:, 2])
                idx = ((i0[:, 0] + dr) * n + (i0[:, 1] + dg)) * n + (i0[:, 2] + db)
                rows.append(np.arange(len(x))); cols.append(idx); vals.append(w)
    return coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(len(x), n ** 3)).tocsr()


def smoothness(n):
    """Differences between each node and its neighbour along r, g and b."""
    rows, cols, vals, r = [], [], [], 0
    for a in range(n):
        for b in range(n):
            for c in range(n):
                i = (a * n + b) * n + c
                for da, db, dc in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
                    if a + da < n and b + db < n and c + dc < n:
                        j = ((a + da) * n + (b + db)) * n + (c + dc)
                        rows += [r, r]; cols += [i, j]; vals += [1.0, -1.0]; r += 1
    return coo_matrix((vals, (rows, cols)), shape=(r, n ** 3)).tocsr()


def fit_lut(x, y, n, smooth, prior=1e-3):
    """Per channel: min |W L - y|² + smooth·N/n³ |D L|² + prior |L - identity|²; then the grey axis pinned."""
    W, D = weights(x, n), smoothness(n)
    grid = np.stack(np.meshgrid(*[np.linspace(0, 1, n)] * 3, indexing="ij"), -1).reshape(-1, 3)
    lam = smooth * len(x) / n ** 3
    A = (W.T @ W + lam * (D.T @ D) + prior * diags(np.ones(n ** 3))).tocsc()
    L = np.stack([spsolve(A, W.T @ y[:, ch] + prior * grid[:, ch]) for ch in range(3)], -1)
    diag = [(k * n + k) * n + k for k in range(n)]
    L[diag] = L[diag].mean(1, keepdims=True)            # a grey in stays a grey out
    return L


def apply_lut(L, x, n):
    return weights(x, n) @ L


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--sizes", type=int, nargs="+", default=[9, 17])
    p.add_argument("--smooth", type=float, default=0.3)
    p.add_argument("--px", type=int, default=384)
    p.add_argument("--per-style", type=int, default=160)
    p.add_argument("--out", default=cf.OUT)
    p.add_argument("--on-today", action="store_true", help="fit the table on top of today's form (a correction), not on the base")
    a = p.parse_args()
    rules = json.load(open(cf.RULES))
    coeff = rules["stages"].get("camera", {}).get("coefficients", {})
    styles = cf.sample(cf.read_index(a.out), a.per_style)
    enc, dec = delta_e.encode_srgb, delta_e.decode_srgb
    head = f"{'style':<10} {'train':>5} {'test':>4}   {'base (Adobe)':>13}   {'today (10 numbers)':>18}" + "".join(f"   {'table ' + str(n) + '³':>13}" for n in a.sizes)
    lines = ["camera profile as learned colour tables vs today's form, held-out photos, ΔE2000 median / p95 (median over photos)", head]
    tables = {}
    for style, rs in sorted(styles.items(), key=lambda kv: -len(kv[1])):
        tr_r, te_r, how = cf.split(rs)
        train = [t for t in (cf.blocks(r, a.px, a.out) for r in tr_r) if t]
        test = [t for t in (cf.blocks(r, a.px, a.out) for r in te_r) if t]
        if len(train) < 12 or not test:
            continue
        m = {k: coeff.get(style.lower() + v, lookmath.BASE_RESET[k]) for k, v in cf.RULE_NAME.items()}
        first = (lambda b: lookmath.base_match(b, m, rules)) if a.on_today else (lambda b: b)
        x = enc(np.clip(np.concatenate([first(t[0]) for t in train]), 0, 1)); y = enc(np.clip(np.concatenate([t[1] for t in train]), 0, 1))

        def score(fn):
            out = []
            for base, cam in test:
                d = delta_e.delta_e2000(cf.lab(fn(base)), cf.lab(cam))
                out.append((np.median(d), np.percentile(d, 95)))
            return "%5.2f / %5.2f" % tuple(np.median(np.array(out), 0))
        row = f"{style:<10} {len(train):>5} {len(test):>4}   {score(lambda b: b):>13}   {score(lambda b: lookmath.base_match(b, m, rules)):>18}"
        for n in a.sizes:
            L = fit_lut(x, y, n, a.smooth)
            tables[f"{style.lower()}-{n}"] = L.tolist()
            row += f"   {score(lambda b, L=L, n=n: dec(np.clip(apply_lut(L, enc(np.clip(first(b), 0, 1)), n), 0, 1))):>13}"
        lines.append(row + ("" if how == "by shoot" else "   (split by file: one shoot)"))
        print(lines[-1], flush=True)
    os.makedirs(os.path.join(HERE, "report"), exist_ok=True)
    with open(os.path.join(HERE, "report", "camera-lut.txt"), "w") as f:
        f.write("\n".join(lines) + f"\nsmooth {a.smooth}; tables in {a.out}/luts.json\n")
    json.dump(tables, open(os.path.join(a.out, "luts.json"), "w"))
    print("\n".join(lines[:2]))


if __name__ == "__main__":
    main()
