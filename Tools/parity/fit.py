#!/usr/bin/env python3
"""Fit one stage's coefficients to Lightroom's sweep (Prompt 2 §5 step 3, "fit numerically").

    python3 Tools/parity/fit.py --stage contrast [--refs ~/LuminaEvidence/parity/refs.json]
                                [--renders ~/LuminaEvidence/parity/render] [--rules Lumina/Sets/Look/rules-v1.json]
                                [--pairs 40] [--px 384] [--maxiter 300] [--out candidate.json | --apply]

Input per pair: Lightroom's TIFF for one slider position and Lumina's *base* render of the same
image (neutral look, from the last parity run), both brought to the working space (linear, sRGB
primaries, D65) at --px long edge. The numpy mirror (lookmath.apply_image) runs the stage on the
base render with candidate coefficients; the objective is mean ΔE2000 plus a penalty on p95 above
the criterion. Nelder–Mead over the stage's coefficients (scipy.optimize), from the current
values. The verification is always the real render: run `make parity STAGE=<id>` afterwards.

Blur-based stages fit at --px with radii scaled the way the graph scales them (fractions of the
long edge), so the fit transfers; sharpen's pixel radius is scaled by px/refPx as in the graph.
"""
import argparse
import json
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402
import lookmath  # noqa: E402
from parity import expand, lr_to_look  # noqa: E402

# Coefficients the fit may move, per stage (the rest are structural or booleans).
FREE = {
    "exposure": ["stopsPerUnit"],
    "whiteBalance": ["redPerMired", "bluePerMired", "greenPerTint"],
    "whitesBlacks": ["blacksPerUnit", "blacksPower", "whitesPerUnit", "whitesPower"],
    "tone": ["shadowsStopsPerUnit", "shadowsHi", "highlightsStopsPerUnit", "highlightsLo", "detailGain", "radiusFraction"],
    "contrast": ["midpoint", "slopePerUnit", "lumaMix"],
    "colour": ["saturationPerUnit", "vibrancePerUnit", "vibranceChromaMax", "skinHue", "skinWidth", "skinProtect"],
    "clarity": ["amountPerUnit", "midtonePower", "radiusFraction"],
    "sharpen": ["amountPerUnit", "threshold", "radiusPx"],
    "vignette": ["stopsPerUnit", "midpoint", "feather"],
}
BOUNDS = {"midpoint": (0.05, 0.95), "lumaMix": (0.0, 1.0), "skinProtect": (0.0, 1.0), "feather": (0.05, 1.5), "radiusFraction": (0.002, 0.2),
          "shadowsHi": (0.2, 1.0), "highlightsLo": (0.0, 0.8), "detailGain": (0.5, 2.0), "threshold": (0.0005, 0.1), "radiusPx": (0.3, 4.0),
          "blacksPower": (0.5, 6.0), "whitesPower": (0.5, 6.0), "midtonePower": (0.5, 6.0), "skinWidth": (5.0, 90.0)}


def load_pair(ref_path, render_path, px):
    """Both images in the working space at px long edge, plus the reference's Lab."""
    from PIL import Image
    ref, space = delta_e.read_rgb01(ref_path)
    ren, ren_space = delta_e.read_rgb01(render_path)
    space = space or ren_space or "prophoto"
    ren = delta_e.align(ref, ren)

    def small(rgb):
        h, w = rgb.shape[:2]
        s = px / max(h, w)
        if s >= 1:
            return rgb
        out = np.zeros((max(1, round(h * s)), max(1, round(w * s)), 3))
        for c in range(3):
            im = Image.fromarray((np.clip(rgb[..., c], 0, 1) * 65535).astype(np.uint16))
            out[..., c] = np.asarray(im.resize((out.shape[1], out.shape[0]), Image.BOX)).astype(np.float64) / 65535.0
        return out
    ref_s, ren_s = small(ref), small(ren)
    return {"ref_lin": delta_e.to_working_linear(ref_s, space), "base_lin": delta_e.to_working_linear(ren_s, space),
            "ref_lab": delta_e.to_lab(ref_s, space), "space": space}


def lab_from_working(lin):
    """Linear sRGB-primaried values → Lab (D65), clipped like the output transform."""
    return delta_e.xyz_to_lab(np.clip(lin, 0, 1) @ delta_e.SRGB_TO_XYZ.T, delta_e.D65)


def objective(values, names, stage, rules, pairs, crit_p95):
    r = json.loads(json.dumps(rules))
    for n, v in zip(names, values):
        lo, hi = BOUNDS.get(n, (-np.inf, np.inf))
        if not (lo <= v <= hi):
            return 1e6 + abs(v) * 1e3
        r["stages"][stage]["coefficients"][n] = float(v)
    r["order"] = ["rawDevelop", stage, "outputTransform"]
    des = []
    for p in pairs:
        pred = lookmath.apply_image(p["base_lin"], p["look"], p["as_shot"], r)
        de = delta_e.delta_e2000(p["ref_lab"], lab_from_working(pred))
        des.append(de.ravel())
    v = np.concatenate(des)
    p95 = float(np.percentile(v, 95))
    return float(np.mean(v)) + 0.5 * max(0.0, p95 - crit_p95), float(np.median(v)), p95


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", required=True, choices=list(FREE))
    ap.add_argument("--refs", default="~/LuminaEvidence/parity/refs.json")
    ap.add_argument("--renders", default="~/LuminaEvidence/parity/render")
    ap.add_argument("--label", default="all", help="the parity run whose base renders to use (render-dir/<label>)")
    ap.add_argument("--rules", default=os.path.join(HERE, "..", "..", "Lumina", "Sets", "Look", "rules-v1.json"))
    ap.add_argument("--criteria", default=os.path.join(HERE, "criteria.json"))
    ap.add_argument("--pairs", type=int, default=40)
    ap.add_argument("--px", type=int, default=384)
    ap.add_argument("--maxiter", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", help="write the candidate rules here (default <rules>.candidate.json)")
    ap.add_argument("--apply", action="store_true", help="write the fitted coefficients into --rules")
    a = ap.parse_args(argv)
    from scipy.optimize import minimize

    rules = json.load(open(expand(a.rules)))
    criteria = json.load(open(expand(a.criteria)))
    refs = json.load(open(expand(a.refs)))["refs"]
    if rules["stages"][a.stage].get("locked"):
        print(f"{a.stage} is locked; unlock it by hand before fitting", file=sys.stderr)
        return 2
    render_dir = os.path.join(expand(a.renders), a.label)
    cache = json.load(open(os.path.join(expand(a.renders), "asshot.json"))) if os.path.exists(os.path.join(expand(a.renders), "asshot.json")) else {}
    sliders = [s for s, st in lookmath.SLIDER_STAGE.items() if st == a.stage]
    if a.stage == "vignette":
        print("vignette has no Lightroom basic slider in the sweep; fit it against a PostCropVignetteAmount sweep if you add one", file=sys.stderr)
    candidates = [r for r in refs if r["kind"] == "single" and r.get("slider") in sliders]
    random.Random(a.seed).shuffle(candidates)
    pairs = []
    for r in candidates:
        base = os.path.join(render_dir, f"{r['stem']}__base.lumina.tif")
        if not os.path.exists(base):
            continue
        apple = next((tuple(v) for k, v in cache.items() if os.path.splitext(os.path.basename(k))[0] == r["stem"]), None)
        if apple is None:
            continue
        p = load_pair(r["path"], base, a.px)
        p["look"] = lr_to_look(r["settings"], r.get("asShot", {}), apple)
        p["as_shot"] = apple
        p["id"] = r["id"]
        pairs.append(p)
        if len(pairs) >= a.pairs:
            break
    if not pairs:
        print(f"no pairs: need {sliders} references in {a.refs} and base renders in {render_dir} (run make parity first)", file=sys.stderr)
        return 2
    names = [n for n in FREE[a.stage] if n in rules["stages"][a.stage]["coefficients"]]
    x0 = np.array([rules["stages"][a.stage]["coefficients"][n] for n in names], dtype=float)
    crit = criteria["singles"]["p95"]
    f0, med0, p950 = objective(x0, names, a.stage, rules, pairs, crit)
    print(f"{a.stage}: {len(pairs)} pairs at {a.px} px · start objective {f0:.3f} (median {med0:.2f}, p95 {p950:.2f}) · fitting {names}")
    simplex = [x0.copy()]
    for j in range(len(x0)):
        v = x0.copy()
        v[j] = v[j] * 1.15 if v[j] != 0 else 0.02
        simplex.append(v)
    res = minimize(lambda x: objective(x, names, a.stage, rules, pairs, crit)[0], x0, method="Nelder-Mead",
                   options={"maxiter": a.maxiter, "xatol": 1e-4, "fatol": 1e-4, "initial_simplex": np.vstack(simplex)})
    f1, med1, p951 = objective(res.x, names, a.stage, rules, pairs, crit)
    print(f"fitted objective {f1:.3f} (median {med1:.2f}, p95 {p951:.2f}) after {res.nfev} evaluations")
    for n, v0, v1 in zip(names, x0, res.x):
        print(f"  {n}: {v0:.5g} → {v1:.5g}")
    out = json.loads(json.dumps(rules))
    for n, v in zip(names, res.x):
        out["stages"][a.stage]["coefficients"][n] = float(round(float(v), 6))
    note = {"stage": a.stage, "pairs": len(pairs), "px": a.px, "before": {"objective": f0, "median": med0, "p95": p950},
            "after": {"objective": f1, "median": med1, "p95": p951}, "changed": {n: [float(v0), float(v1)] for n, v0, v1 in zip(names, x0, res.x)}}
    if f1 >= f0:
        print("no improvement on the fit set; nothing written")
        return 1
    if a.apply:
        with open(expand(a.rules), "w") as f:
            json.dump(out, f, indent=2)
            f.write("\n")
        print(f"applied to {a.rules}")
    else:
        dest = a.out or expand(a.rules) + ".candidate.json"
        with open(dest, "w") as f:
            json.dump(out, f, indent=2)
            f.write("\n")
        print(f"candidate → {dest} (verify with: make parity STAGE={a.stage} RULES={dest})")
    with open(os.path.join(expand(a.renders), f"fit-{a.stage}.json"), "w") as f:
        json.dump(note, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
