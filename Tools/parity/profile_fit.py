#!/usr/bin/env python3
"""Fit the `profile` stage (Tools/parity/profile_math.py): Lumina's own camera profile, from the
decoder's linear output to Lightroom's Adobe Color base exports.

    python3 Tools/parity/profile_fit.py --index ~/LuminaEvidence/profile/index.json [--px 384]
        [--per-image 400] [--hue 30 --sat 8 --val 1 --nodes 33] [--holdout-every 5] [--rounds 3]
        [--smooth 0.02] [--out ~/LuminaEvidence/profile/candidate.json]

index.json: [{"set", "stem", "raw", "ref" (Lightroom base JPEG), "linear" (lumina-render of the
RAW with boostAmount 0 and no base match, 16-bit ProPhoto TIFF)}]. Every --holdout-every'th photo
(sorted by stem) is held out of the fit and reported on its own; the owner's own edits (the
mehendi set) are never in the index: they are measured with parity_personal.py afterwards.

The fit alternates two blocks, each scipy least_squares on Lab residuals (≈ ΔE76) plus smoothness:
  (a) exposure, the 3×3 mix and the curve (dense, ~40 numbers);
  (b) the hue/sat table, whose Jacobian is sparse: with (a) fixed, each pixel reads one cell of the
      table and its neighbours, so the pattern is exact and the finite differences cheap.
The result is the stage's coefficients and tables, written into a copy of rules-v1.json
(rawDevelop's boostAmount 0 and base match reset), plus numbers.json and report.md next to it.
"""
import argparse
import json
import os
import sys
import time

import numpy as np
from scipy.optimize import least_squares
from scipy.sparse import lil_matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402
import fit as fitmod  # noqa: E402
import profile_math as pm  # noqa: E402

np.seterr(all="ignore")


def load_pair(ref_path, linear_path, px):
    """The reference (a Lightroom JPEG, any size) and the linear render, both reduced to px on the
    long edge with a box filter: working-linear base (h, w, 3) and the reference's Lab."""
    from PIL import Image
    ref, space = delta_e.read_rgb01(ref_path)
    ren, ren_space = delta_e.read_rgb01(linear_path)
    space = space or "srgb"

    def small(rgb, size):
        out = np.zeros((size[1], size[0], 3))
        for c in range(3):
            im = Image.fromarray((np.clip(rgb[..., c], 0, 1) * 65535).astype(np.uint16))
            out[..., c] = np.asarray(im.resize(size, Image.BOX)).astype(np.float64) / 65535.0
        return out
    h, w = ren.shape[:2]
    s = min(1.0, px / max(h, w))
    size = (max(1, round(w * s)), max(1, round(h * s)))
    rh, rw = ref.shape[:2]
    if abs((rw / rh) / (w / h) - 1) > 0.02:
        raise ValueError(f"aspect mismatch: reference {rw}×{rh}, render {w}×{h}")
    ref_s, ren_s = small(ref, size), small(ren, size)
    return delta_e.to_working_linear(ren_s, ren_space or "prophoto"), delta_e.to_lab(ref_s, space)


def load_pairs(index, px, per_image, seed, cache_dir, weights=None):
    """Sampled pixels per photo: base_lin (n, 3) working-linear, ref_lab (n, 3)."""
    os.makedirs(cache_dir, exist_ok=True)
    rng = np.random.default_rng(seed)
    out = []
    for e in index:
        key = os.path.join(cache_dir, f"{e['stem']}-{px}.npz")
        if os.path.exists(key):
            z = np.load(key)
            base, lab = z["base"], z["lab"]
        else:
            base, lab = load_pair(e["ref"], e["linear"], px)
            np.savez(key, base=base.astype(np.float32), lab=lab.astype(np.float32))
        h, w = lab.shape[:2]
        n = min(int(per_image * (weights or {}).get(e["set"], 1.0)), h * w)
        idx = rng.choice(h * w, size=n, replace=False)
        out.append({"set": e["set"], "stem": e["stem"], "base": base.reshape(-1, 3)[idx].astype(np.float64),
                    "lab": lab.reshape(-1, 3)[idx].astype(np.float64)})
    return out


class Params:
    """θ ↔ the stage. Curve nodes come from positive increments (monotone, 0 → 1); the table's
    scales are logs (positive); valScale on the sat-0 row stays 1."""

    def __init__(self, hue, sat, val, nodes):
        self.h, self.s, self.v, self.n = hue, sat, val, nodes
        self.n_dense = 1 + 6 + (nodes - 1)
        self.n_hsm = val * hue * sat * 3

    def stage(self, dense, hsm_flat):
        c = {"exposure": float(dense[0]), "rg": float(dense[1]), "rb": float(dense[2]), "gr": float(dense[3]),
             "gb": float(dense[4]), "br": float(dense[5]), "bg": float(dense[6]),
             "hueDivisions": self.h, "satDivisions": self.s, "valDivisions": self.v, "curveNodes": self.n}
        inc = np.exp(dense[7:])
        curve = np.concatenate([[0.0], np.cumsum(inc) / inc.sum()])
        t = hsm_flat.reshape(self.v, self.h, self.s, 3).copy()
        t[..., 1] = np.exp(t[..., 1])
        t[..., 2] = np.exp(t[..., 2])
        t[:, :, 0, 2] = 1.0
        return {"coefficients": c, "tables": {"hsm": t.ravel().tolist(), "curve": curve.tolist()}}

    def identity(self):
        dense = np.zeros(self.n_dense)
        hsm = np.zeros((self.v, self.h, self.s, 3))
        return dense, hsm.ravel()


def predict_lab(base, stage, rules):
    return fitmod.lab_from_working(pm.profile(base, stage, rules))


def residuals(pairs, stage, rules):
    base = np.concatenate([p["base"] for p in pairs])
    lab = np.concatenate([p["lab"] for p in pairs])
    return (predict_lab(base, stage, rules) - lab).ravel()


def ridge_hsm(hsm_flat, P, lam):
    """Pull every entry toward the identity (no shift, scales 1), so a cell few pixels reach
    stays sane: the same weights as the smoothness term."""
    t = hsm_flat.reshape(P.v, P.h, P.s, 3)
    return lam * np.concatenate([(t[..., 0] / 15.0).ravel(), t[..., 1].ravel(), t[..., 2].ravel()]) * np.sqrt(P.h * P.s * P.v)


def smooth_hsm(hsm_flat, P, lam):
    t = hsm_flat.reshape(P.v, P.h, P.s, 3)
    d = [np.roll(t, -1, axis=1) - t]                       # along hue, wrapping
    if P.s > 1:
        d.append((t[:, :, 1:] - t[:, :, :-1]).ravel())
    if P.v > 1:
        d.append((t[1:] - t[:-1]).ravel())
    w = np.array([1 / 15.0, 1.0, 1.0])                    # degrees vs log scales
    parts = [(d[0] * w).ravel()] + [x for x in d[1:]]
    return lam * np.concatenate(parts) * np.sqrt(P.h * P.s * P.v)


def de2000(pairs, stage, rules):
    base = np.concatenate([p["base"] for p in pairs])
    lab = np.concatenate([p["lab"] for p in pairs])
    de = delta_e.delta_e2000(lab, predict_lab(base, stage, rules))
    per = []
    o = 0
    for p in pairs:
        n = p["base"].shape[0]
        per.append(float(np.median(de[o:o + n])))
        o += n
    return {"median": float(np.median(de)), "p95": float(np.percentile(de, 95)), "mean": float(np.mean(de)),
            "frameMedian": float(np.median(per)), "worstFrame": float(np.max(per))}


def hsm_sparsity(pairs, stage, rules, P):
    """Which table entries each pixel's residuals can touch: its cell's eight corners (and the
    value neighbours), found from the hue / sat the pixel has after exposure and the mix."""
    c = pm.coefficients(stage)
    base = np.concatenate([p["base"] for p in pairs])
    x = base * (2.0 ** c["exposure"]) @ pm.mix_rows(c).T
    pp = np.maximum(x @ pm.SRGB_TO_PROPHOTO.T, 0.0)
    h, s, v = pm.rgb_to_hsv6(pp)
    gamma = float(rules.get("perceptualGamma", 2.2))
    v_enc = np.power(np.clip(v, 0, 1), 1 / gamma)
    hf = np.mod(h, 6.0) * (P.h / 6.0)
    h0 = np.mod(np.floor(hf).astype(int), P.h)
    sf = np.clip(s, 0, 1) * (P.s - 1)
    s0 = np.minimum(np.floor(sf).astype(int), max(P.s - 2, 0))
    if P.v > 1:
        vf = np.clip(v_enc, 0, 1) * (P.v - 1)
        v0 = np.minimum(np.floor(vf).astype(int), P.v - 2)
        vs = [v0, v0 + 1]
    else:
        vs = [np.zeros_like(h0)]
    n = base.shape[0]
    S = lil_matrix((n * 3, P.n_hsm), dtype=np.int8)
    rows = np.repeat(np.arange(n), 3) * 3 + np.tile(np.arange(3), n)
    cols = []
    for vi in vs:
        for hi in (h0, np.mod(h0 + 1, P.h)):
            for si in (s0, np.minimum(s0 + 1, P.s - 1)):
                cell = (vi * P.h * P.s + hi * P.s + si) * 3
                for k in range(3):
                    cols.append(np.repeat(cell + k, 3))
    for col in cols:
        S[rows, col] = 1
    return S.tocsr()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default=os.path.expanduser("~/LuminaEvidence/profile/index.json"))
    ap.add_argument("--rules", default=os.path.join(HERE, "..", "..", "Lumina", "Sets", "Look", "rules-v1.json"))
    ap.add_argument("--px", type=int, default=384)
    ap.add_argument("--per-image", type=int, default=400)
    ap.add_argument("--hue", type=int, default=30)
    ap.add_argument("--sat", type=int, default=8)
    ap.add_argument("--val", type=int, default=1)
    ap.add_argument("--nodes", type=int, default=33)
    ap.add_argument("--holdout-every", type=int, default=5)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--smooth", type=float, default=0.02)
    ap.add_argument("--ridge", type=float, default=0.02, help="pull toward the identity table (0 = none)")
    ap.add_argument("--exclude", help="JSON list of stems to leave out (a label audit's rejects)")
    ap.add_argument("--weights", help="pixels per image by set, as multipliers of --per-image: dv=1,portraits=4")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--sets", help="comma-separated subset of index sets to fit on (default all)")
    ap.add_argument("--out", default=os.path.expanduser("~/LuminaEvidence/profile/candidate.json"))
    a = ap.parse_args(argv)

    rules = json.load(open(a.rules))
    index = sorted(json.load(open(a.index)), key=lambda e: e["stem"])
    if a.sets:
        keep = set(a.sets.split(","))
        index = [e for e in index if e["set"] in keep]
    if a.exclude:
        drop = set(json.load(open(a.exclude)))
        before = len(index)
        index = [e for e in index if e["stem"] not in drop]
        print(f"excluded {before - len(index)} of {before} (bad labels)", flush=True)
    t0 = time.time()
    weights = {k: float(v) for k, v in (w.split("=") for w in a.weights.split(","))} if a.weights else None
    pairs = load_pairs(index, a.px, a.per_image, a.seed, os.path.join(os.path.dirname(a.out), "pairs"), weights)
    train = [p for i, p in enumerate(pairs) if a.holdout_every <= 0 or i % a.holdout_every != 0]
    held = [p for i, p in enumerate(pairs) if a.holdout_every > 0 and i % a.holdout_every == 0]
    print(f"pairs {len(pairs)} (train {len(train)}, held-out {len(held)}) · {sum(p['base'].shape[0] for p in pairs)} pixels · {time.time() - t0:.1f} s", flush=True)

    P = Params(a.hue, a.sat, a.val, a.nodes)
    dense, hsm = P.identity()
    # the current base match's numbers as the start for the mix; the curve starts straight
    cur = rules["stages"]["rawDevelop"]["coefficients"]
    for i, k in enumerate(("baseRG", "baseRB", "baseGR", "baseGB", "baseBR", "baseBG")):
        dense[1 + i] = float(cur.get(k, 0.0))

    def report(tag, stage):
        tr, ho = de2000(train, stage, rules), (de2000(held, stage, rules) if held else None)
        print(f"  {tag}: train {tr['median']:.2f} / {tr['p95']:.2f} (frame {tr['frameMedian']:.2f}, worst {tr['worstFrame']:.2f})"
              + (f" · held-out {ho['median']:.2f} / {ho['p95']:.2f} (frame {ho['frameMedian']:.2f})" if ho else ""), flush=True)
        return {"train": tr, "heldOut": ho}

    stage = P.stage(dense, hsm)
    numbers = {"start": report("linear decode, straight curve", stage)}
    for r in range(a.rounds):
        # (a) dense
        def f_dense(th):
            return residuals(train, P.stage(th, hsm), rules)
        t1 = time.time()
        res = least_squares(f_dense, dense, method="trf", jac="2-point", max_nfev=60, x_scale="jac", verbose=0)
        dense = res.x
        stage = P.stage(dense, hsm)
        print(f"round {r + 1} (a) dense: cost {res.cost:.0f}, {time.time() - t1:.0f} s", flush=True)
        report("after (a)", stage)
        # (b) sparse table
        S = hsm_sparsity(train, stage, rules, P)
        n_res = sum(p["base"].shape[0] for p in train) * 3
        n_smooth = smooth_hsm(hsm, P, a.smooth).shape[0] + ridge_hsm(hsm, P, a.ridge).shape[0]
        # the smoothness rows touch every entry: a dense block at the bottom (cheap, few rows)
        S2 = lil_matrix((n_res + n_smooth, P.n_hsm), dtype=np.int8)
        S2[:n_res] = S
        S2[n_res:] = 1
        S2 = S2.tocsr()

        def f_hsm(th):
            return np.concatenate([residuals(train, P.stage(dense, th), rules), smooth_hsm(th, P, a.smooth), ridge_hsm(th, P, a.ridge)])
        t1 = time.time()
        res = least_squares(f_hsm, hsm, method="trf", jac="2-point", jac_sparsity=S2, max_nfev=40, x_scale="jac", verbose=0)
        hsm = res.x
        stage = P.stage(dense, hsm)
        print(f"round {r + 1} (b) table: cost {res.cost:.0f}, {time.time() - t1:.0f} s", flush=True)
        numbers[f"round{r + 1}"] = report("after (b)", stage)

    pm.validate(stage)
    out = json.loads(json.dumps(rules))
    out["stages"]["profile"] = {"locked": False, "form": "camera profile (Tools/parity/profile_math.py): exposure, a 3×3 mix (rows sum to 1), a hue/sat table in linear ProPhoto HSV (DNG SDK HueSatMap form), then a monotone tone curve through RGBTone (max and min channels through the curve, the middle keeps its place)", **stage}
    rd = out["stages"]["rawDevelop"]["coefficients"]
    rd["boostAmount"] = 0.0
    for k in list(rd):
        if k.startswith("base"):
            rd[k] = 0.0
    rd["baseHiFrom"], rd["baseLoBelow"] = 0.9, 0.2
    # the profile is rawDevelop's last step (LookPipeline.matched), not a stage in `order`
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(out, open(a.out, "w"), indent=1)
    per_set = {}
    for name in sorted({p["set"] for p in pairs}):
        per_set[name] = {"train": de2000([p for p in train if p["set"] == name], stage, rules) if any(p["set"] == name for p in train) else None,
                         "heldOut": de2000([p for p in held if p["set"] == name], stage, rules) if any(p["set"] == name for p in held) else None}
    numbers["perSet"] = per_set
    numbers["args"] = vars(a)
    json.dump(numbers, open(os.path.splitext(a.out)[0] + "-numbers.json", "w"), indent=1)
    print("per set:", json.dumps({k: {kk: (round(vv["median"], 2), round(vv["p95"], 2)) if vv else None for kk, vv in v.items()} for k, v in per_set.items()}))
    print("wrote", a.out, f"· total {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main()
