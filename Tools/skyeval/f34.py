"""F3 (sky exposure through mask:sky) and F4 (sky blue, `blu`) scored on photos with sky.

Renders through lumina-render (the app's LookPipeline, the sky mask attached with "sky": true,
LUMINA_SKY=1 so `blu` parses), 16-bit sRGB TIFFs at 1024 px, then per photo:
  collateral  share of non-sky pixels (mask < 0.5, outside a 16 px band) with ΔE2000 > 2 vs the base
  halo        p95 ΔE2000 in the 16 px band just outside the mask's edge
  sky         mean CIELAB hue and chroma in the sky, share of sky in the cyan band (h 180°–235°)
  banding     sky columns at 10 bits: distinct L* codes per column (after / before) and the p99 step
              between neighbouring rows in L*

  python f34.py --rows ~/LuminaEvidence/skyeval/f1/rows.jsonl --out ~/LuminaEvidence/skyeval/f34 [--rules r.json --label sigmoid]
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import delta_e  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")
LOOKS = {
    "base": "",
    "f3": "mask:sky/ev=-1.00",
    "f4": "mask:sky/blu=60",
    "all": "mask:sky/ev=-1.00,blu=60",
}
BAND = 16


def render_all(rows, out, rules):
    jobs = []
    for r in rows:
        for k, look in LOOKS.items():
            o = os.path.join(out, "render", f"{r['stem']}__{k}.tif")
            if not os.path.exists(o):
                jobs.append({"image": r["image"], "look": look, "px": 1024, "space": "srgb", "out": o, "sky": k != "base"})
    if not jobs:
        return
    plan = os.path.join(out, "jobs.json")
    json.dump(jobs, open(plan, "w"))
    cmd = [RENDER, "batch", plan] + (["--rules", rules] if rules else [])
    subprocess.run(cmd, env={**os.environ, "LUMINA_SKY": "1"}, check=False, stdout=subprocess.DEVNULL)


def read(p):
    return delta_e.read_rgb01(p)[0]


def lab(rgb):
    return delta_e.to_lab(rgb, "srgb")


def measure(base, img, sky):
    lb, li = lab(base), lab(img)
    de = delta_e.delta_e2000(lb, li)
    hard = sky >= 0.5
    dist_out = ndimage.distance_transform_edt(~hard)
    band = (~hard) & (dist_out <= BAND)
    far = (~hard) & (dist_out > BAND)
    m = {"collateral": float((de[far] > 2).mean()) if far.any() else None,
         "collateralAllNonSky": float((de[~hard] > 2).mean()) if (~hard).any() else None,
         "haloP95": float(np.percentile(de[band], 95)) if band.any() else None,
         "skyDE": float(np.median(de[hard])) if hard.any() else None}
    return m


def sky_colour(img, sky):
    L = lab(img)[sky >= 0.5]
    a, b = L[:, 1], L[:, 2]
    h = np.degrees(np.arctan2(b, a)) % 360
    C = np.hypot(a, b)
    hm = float(np.degrees(np.arctan2(np.mean(np.sin(np.radians(h)) * C), np.mean(np.cos(np.radians(h)) * C))) % 360)
    return {"hue": hm, "chroma": float(C.mean()), "cyan": float(((h >= 180) & (h < 235) & (C > 3)).mean()), "L": float(L[:, 0].mean())}


def banding(img, sky):
    """Columns of sky: distinct 10-bit L* codes and the p99 row-to-row L* step."""
    Lstar = lab(img)[..., 0]
    q = np.round(Lstar / 100 * 1023)
    hard = sky >= 0.5
    distinct, steps = [], []
    for x in range(0, sky.shape[1], 8):
        col = hard[:, x]
        if col.sum() < 40:
            continue
        v = q[col, x]
        distinct.append(len(np.unique(v)))
        steps.extend(np.abs(np.diff(Lstar[col, x])).tolist())
    if not distinct:
        return None
    return {"distinct": float(np.median(distinct)), "stepP99": float(np.percentile(steps, 99))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--rules")
    ap.add_argument("--label", default="clamp")
    ap.add_argument("--min-sky", type=float, default=0.05)
    ap.add_argument("--limit", type=int, default=80)
    a = ap.parse_args()
    out = os.path.join(os.path.expanduser(a.out), a.label)
    os.makedirs(out, exist_ok=True)
    rows = [json.loads(l) for l in open(os.path.expanduser(a.rows))]
    rows = [r for r in rows if r.get("sky", 0) >= a.min_sky and r.get("verdict") not in (None, "no-sky")]
    rows = rows[: a.limit]
    print(len(rows), "photos with sky", flush=True)
    render_all(rows, out, a.rules)
    f1dir = os.path.dirname(os.path.expanduser(a.rows))
    res = []
    for r in rows:
        p = {k: os.path.join(out, "render", f"{r['stem']}__{k}.tif") for k in LOOKS}
        if not all(os.path.exists(v) for v in p.values()):
            continue
        imgs = {k: read(v) for k, v in p.items()}
        H, W = imgs["base"].shape[:2]
        sky = np.asarray(Image.open(os.path.join(f1dir, r["stem"], "sky.png")).convert("L").resize((W, H), Image.BILINEAR), np.float32) / 255
        row = {"stem": r["stem"], "verdict": r.get("truth") or r.get("verdict"), "sky": r["sky"]}
        for k in ("f3", "f4", "all"):
            row[k] = measure(imgs["base"], imgs[k], sky)
        for k in LOOKS:
            row["colour_" + k] = sky_colour(imgs[k], sky)
            row["band_" + k] = banding(imgs[k], sky)
        res.append(row)
    json.dump(res, open(os.path.join(out, "f34.json"), "w"), indent=1)

    def agg(key, sub, fn=np.median):
        v = [x[key][sub] for x in res if x.get(key) and x[key].get(sub) is not None]
        return float(fn(v)) if v else None
    summary = {"n": len(res)}
    for k in ("f3", "f4", "all"):
        summary[k] = {"collateralMedian": agg(k, "collateral"), "collateralP95": agg(k, "collateral", lambda v: np.percentile(v, 95)),
                      "collateralMax": agg(k, "collateral", np.max), "share≤1%": float(np.mean([x[k]["collateral"] <= 0.01 for x in res if x[k]["collateral"] is not None])),
                      "haloP95Median": agg(k, "haloP95"), "skyDEMedian": agg(k, "skyDE")}
    for k in LOOKS:
        summary["colour_" + k] = {s: agg("colour_" + k, s) for s in ("hue", "chroma", "cyan", "L")}
        summary["band_" + k] = {s: agg("band_" + k, s) for s in ("distinct", "stepP99")}
    by = {}
    for v in ("fine", "recoverable", "clipped-at-capture"):
        sub = [x for x in res if x["verdict"] == v]
        if sub:
            by[v] = {"n": len(sub),
                     "hueShift": float(np.median([((x["colour_f4"]["hue"] - x["colour_base"]["hue"] + 180) % 360) - 180 for x in sub])),
                     "cyanBefore": float(np.median([x["colour_base"]["cyan"] for x in sub])), "cyanAfter": float(np.median([x["colour_f4"]["cyan"] for x in sub])),
                     "chromaBefore": float(np.median([x["colour_base"]["chroma"] for x in sub])), "chromaAfter": float(np.median([x["colour_f4"]["chroma"] for x in sub])),
                     "chromaAllOn": float(np.median([x["colour_all"]["chroma"] for x in sub])),
                     "distinctRatioF4": float(np.median([x["band_f4"]["distinct"] / max(1, x["band_base"]["distinct"]) for x in sub if x["band_f4"] and x["band_base"]])),
                     "distinctRatioAll": float(np.median([x["band_all"]["distinct"] / max(1, x["band_base"]["distinct"]) for x in sub if x["band_all"] and x["band_base"]])),
                     "stepP99Before": float(np.median([x["band_base"]["stepP99"] for x in sub if x["band_base"]])),
                     "stepP99All": float(np.median([x["band_all"]["stepP99"] for x in sub if x["band_all"]]))}
    summary["byVerdict"] = by
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
