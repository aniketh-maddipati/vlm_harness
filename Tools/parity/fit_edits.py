#!/usr/bin/env python3
"""Fit one stage's coefficients on *whole edits* (a personal set's `__editNN` refs) instead of a
single-slider sweep: for sliders Lightroom's sweep plug-in never had (Dehaze, 2026-10-29).

    python3 Tools/parity/fit_edits.py --stage dehaze --root ~/LuminaEvidence/parity-dv-edits
                                      [--rules Lumina/Sets/Look/rules-v1.json] [--px 384] [--maxiter 200]
                                      [--out /Volumes/LuminaFactory/tmp/fits/rules-dehaze.json]

Per pair: Lightroom's export of the edit (the reference) and Lumina's *neutral* render of the
same RAW with the edit's crop (rendered here with lumina-render, cached under <root>/render-neutral).
The numpy mirror runs the edit's whole look on the neutral render (every stage, so the fitted
stage sits where it will in the app) with candidate coefficients; the objective is mean ΔE2000
over the pairs whose look uses the stage. Nelder–Mead from the current values, within fit.py's
bounds. The confound is stated, not hidden: on whole edits the stage also absorbs what the other
stages get wrong on these photos, so the candidate is judged on the held-out set
(`parity_personal.py --rules <candidate>`), never adopted from this number alone.
"""
import argparse
import json
import os
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402
import lookmath  # noqa: E402
from fit import BOUNDS, FREE, PENALTY, lab_from_working  # noqa: E402

RENDER = os.path.join(HERE, "lumina-render", ".build", "release", "lumina-render")
STAGE_KEY = {"dehaze": "dhz", "contrast": "con", "colour": "vib", "clarity": "clr", "tone": "hl"}


def shrink(rgb, size):
    """BOX-resample (H, W, 3) float 0…1 to (w, h), 16-bit per channel."""
    from PIL import Image
    w, h = size
    out = np.zeros((h, w, 3))
    for c in range(3):
        im = Image.fromarray((np.clip(rgb[..., c], 0, 1) * 65535).astype(np.uint16))
        out[..., c] = np.asarray(im.resize((w, h), Image.BOX)).astype(np.float64) / 65535.0
    return out


def load_pair(ref_path, render_path, px):
    """The export (full size) and the neutral render (render-px), both brought to px long edge
    in the working space, plus the reference's Lab. Same aspect: the render carries the crop."""
    ref, space = delta_e.read_rgb01(ref_path)
    ren, ren_space = delta_e.read_rgb01(render_path)
    space = space or ren_space or "srgb"
    h, w = ren.shape[:2]
    s = min(1.0, px / max(h, w))
    size = (max(1, round(w * s)), max(1, round(h * s)))
    ref_s, ren_s = shrink(ref, size), shrink(ren, size)
    return {"ref_lin": delta_e.to_working_linear(ref_s, space), "base_lin": delta_e.to_working_linear(ren_s, ren_space or space),
            "ref_lab": delta_e.to_lab(ref_s, space), "space": space}


def neutral_look(look_text):
    """The edit's look with every slider at reset: crop, rotation and noise reduction stay."""
    look = lookmath.parse_look(look_text)
    for k in ("ev", "con", "hl", "sh", "wh", "bl", "vib", "sat", "clr", "dhz", "shp", "vig"):
        look[k] = 0.0
    look["wb"] = None
    for k in ("tc", "crv", "crvr", "crvg", "crvb", "mixh", "mixs", "mixl"):
        look[k] = None if k.startswith("crv") else ((0.0,) * 8 if k.startswith("mix") else (0.0, 0.0, 0.0))
    look["bw"] = False
    return lookmath.format_look(look)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", required=True, choices=list(FREE))
    ap.add_argument("--root", default="~/LuminaEvidence/parity-dv-edits")
    ap.add_argument("--rules", default=os.path.join(HERE, "..", "..", "Lumina", "Sets", "Look", "rules-v1.json"))
    ap.add_argument("--px", type=int, default=384)
    ap.add_argument("--render-px", type=int, default=1024)
    ap.add_argument("--maxiter", type=int, default=200)
    ap.add_argument("--free", help="comma-separated coefficient names (default: fit.py's FREE for the stage)")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    root = os.path.expanduser(a.root)
    rules = json.load(open(os.path.expanduser(a.rules)))
    key = STAGE_KEY[a.stage]
    d = json.load(open(os.path.join(root, "refs.json")))
    refs = [r for r in (d["refs"] if isinstance(d, dict) else d) if r.get("kind") == "edit" and f" {key}:" in " " + r["look"]]
    print(f"{len(refs)} edits use {key}")
    out_dir = os.path.join(root, "render-neutral")
    os.makedirs(out_dir, exist_ok=True)
    jobs = []
    for r in refs:
        r["neutral"] = os.path.join(out_dir, r["id"] + ".tif")
        if not os.path.exists(r["neutral"]):
            jobs.append({"image": r["raw"], "look": neutral_look(r["look"]), "px": a.render_px, "space": "srgb", "out": r["neutral"]})
    if jobs:
        jp = os.path.join(out_dir, "jobs.json")
        json.dump(jobs, open(jp, "w"))
        t = time.time()
        subprocess.run([RENDER, "batch", jp, "--rules", os.path.expanduser(a.rules), "--cache", os.path.join(root, "cache")], stdout=subprocess.DEVNULL, check=False)
        print(f"{len(jobs)} neutral renders in {time.time() - t:.0f} s")
    pairs = []
    for r in refs:
        if not os.path.exists(r["neutral"]):
            print("no neutral render for", r["id"]); continue
        p = load_pair(r["path"], r["neutral"], a.px)
        p["look"] = lookmath.parse_look(r["look"])
        p["as_shot"] = tuple(r["appleAsShot"])
        p["id"] = r["id"]
        pairs.append(p)
    names = a.free.split(",") if a.free else FREE[a.stage]
    x0 = np.array([rules["stages"][a.stage]["coefficients"][n] for n in names], dtype=np.float64)

    def score(values):
        rr = json.loads(json.dumps(rules))
        for n, v in zip(names, values):
            lo, hi = BOUNDS.get(n, (-np.inf, np.inf))
            if not (lo <= v <= hi):
                return PENALTY + abs(v) * 1e3, None
            rr["stages"][a.stage]["coefficients"][n] = float(v)
        per = []
        for p in pairs:
            pred = lookmath.apply_image(p["base_lin"], p["look"], p["as_shot"], rr)
            per.append(float(np.mean(delta_e.delta_e2000(p["ref_lab"], lab_from_working(pred)))))
        return float(np.mean(per)), per

    s0, per0 = score(x0)
    print("start", dict(zip(names, np.round(x0, 5))), "mean ΔE %.3f  median-of-frames %.3f" % (s0, np.median(per0)))
    from scipy.optimize import minimize
    hist = []

    def f(x):
        s, _ = score(x)
        hist.append(s)
        if len(hist) % 20 == 0:
            print(f"  eval {len(hist)}: best {min(hist):.3f}")
        return s
    res = minimize(f, x0, method="Nelder-Mead", options={"maxiter": a.maxiter, "xatol": 1e-4, "fatol": 1e-4, "initial_simplex": None})
    s1, per1 = score(res.x)
    print("fitted", dict(zip(names, np.round(res.x, 5))), "mean ΔE %.3f  median-of-frames %.3f  (%d evals)" % (s1, np.median(per1), len(hist)))
    better = sum(b < a_ for a_, b in zip(per0, per1))
    print(f"frames improved {better}/{len(pairs)}")
    cand = json.loads(json.dumps(rules))
    for n, v in zip(names, res.x):
        cand["stages"][a.stage]["coefficients"][n] = float(round(v, 6))
    out = os.path.expanduser(a.out or f"/Volumes/LuminaFactory/tmp/fits/rules-{a.stage}.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(cand, open(out, "w"), indent=1)
    json.dump({"stage": a.stage, "names": names, "start": list(map(float, x0)), "fitted": list(map(float, res.x)), "meanStart": s0, "meanFitted": s1,
               "frames": [{"id": p["id"], "start": a_, "fitted": b} for p, a_, b in zip(pairs, per0, per1)]},
              open(out.replace(".json", "-fit.json"), "w"), indent=1)
    print("candidate →", out)


if __name__ == "__main__":
    main()
