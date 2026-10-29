"""F3 / F4 against the photographer's own edits: on frames with sky and a Lightroom export, render
the export's own look (its global sliders, as refs.json gives them) alone and with F3 / F4 / both
added, and measure sky-pixel ΔE2000, ΔL*, ΔC* and hue to the export. Also the look-free base.
Tells whether the sky features move toward or away from what the photographer did.

  python f34ref.py --root ~/LuminaEvidence/parity-dv-edits --rows ~/LuminaEvidence/skyeval/f1/rows.jsonl --out ~/LuminaEvidence/skyeval/f34ref
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import delta_e  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")
VARIANTS = {"base": "", "ref": "{look}", "ref+f3": "{look} mask:sky/ev=-1.00", "ref+f3half": "{look} mask:sky/ev=-0.50",
            "ref+f4": "{look} mask:sky/blu=60", "ref+all": "{look} mask:sky/ev=-0.50,blu=40"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--rows", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--rules")
    ap.add_argument("--label", default="clamp")
    a = ap.parse_args()
    root, out = os.path.expanduser(a.root), os.path.join(os.path.expanduser(a.out), a.label)
    os.makedirs(os.path.join(out, "render"), exist_ok=True)
    cfg = json.load(open(os.path.join(root, "config.json")))
    refs = [r for r in json.load(open(os.path.join(root, "refs.json")))["refs"] if r.get("kind") == "edit" and not r.get("crop")]
    f1dir = os.path.dirname(os.path.expanduser(a.rows))
    rows = {json.loads(l)["stem"]: json.loads(l) for l in open(os.path.expanduser(a.rows))}
    seen, picks = set(), []
    for r in refs:
        stem = r["id"].split("__")[0]
        if stem in seen or rows.get(stem, {}).get("sky", 0) < 0.05:
            continue
        seen.add(stem)
        picks.append((stem, r))
    jobs = []
    for stem, r in picks:
        for k, t in VARIANTS.items():
            o = os.path.join(out, "render", f"{stem}__{k}.tif")
            if not os.path.exists(o):
                jobs.append({"image": os.path.join(cfg["raws"], stem + ".ARW"), "look": t.format(look=r["look"]), "px": 1024, "space": "srgb", "out": o, "sky": "mask:" in t})
    if jobs:
        json.dump(jobs, open(os.path.join(out, "jobs.json"), "w"))
        subprocess.run([RENDER, "batch", os.path.join(out, "jobs.json")] + (["--rules", a.rules] if a.rules else []),
                       env={**os.environ, "LUMINA_SKY": "1"}, stdout=subprocess.DEVNULL, check=False)
    res = []
    for stem, r in picks:
        exp = os.path.join(cfg["exports"], r["export"])
        ref_rgb, _ = delta_e.read_rgb01(exp)
        row = {"stem": stem, "verdict": rows[stem].get("truth"), "look": r["look"], "sky": rows[stem]["sky"]}
        for k in VARIANTS:
            p = os.path.join(out, "render", f"{stem}__{k}.tif")
            if not os.path.exists(p):
                continue
            ren, _ = delta_e.read_rgb01(p)
            H, W = ren.shape[:2]
            if ref_rgb.shape[:2] != (H, W):
                ref = np.asarray(Image.fromarray((ref_rgb * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS), np.float32) / 255
            else:
                ref = ref_rgb
            sky = np.asarray(Image.open(os.path.join(f1dir, stem, "sky.png")).convert("L").resize((W, H), Image.BILINEAR), np.float32) / 255 >= 0.5
            if sky.sum() < 100:
                continue
            la, lb = delta_e.to_lab(delta_e.median3(ref), "srgb"), delta_e.to_lab(delta_e.median3(ren), "srgb")
            de = delta_e.delta_e2000(la, lb)
            ca, cb = np.hypot(la[..., 1], la[..., 2]), np.hypot(lb[..., 1], lb[..., 2])
            row[k] = {"skyDE": float(np.median(de[sky])), "skyDEp95": float(np.percentile(de[sky], 95)), "dL": float((lb[..., 0] - la[..., 0])[sky].mean()),
                      "dC": float((cb - ca)[sky].mean()), "landDE": float(np.median(de[~sky])) if (~sky).any() else None}
        res.append(row)
    json.dump(res, open(os.path.join(out, "f34ref.json"), "w"), indent=1)
    summary = {"n": len(res)}
    for k in VARIANTS:
        v = [x[k] for x in res if k in x]
        if v:
            summary[k] = {m: float(np.median([x[m] for x in v if x[m] is not None])) for m in ("skyDE", "skyDEp95", "dL", "dC", "landDE")}
            summary[k]["betterThanRef"] = float(np.mean([x[k]["skyDE"] < x["ref"]["skyDE"] for x in res if k in x and "ref" in x])) if k != "ref" else None
    print(json.dumps(summary, indent=1))
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
