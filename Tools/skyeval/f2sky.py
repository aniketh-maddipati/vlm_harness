"""F2's other number: with the meter's ev applied, does the sky's white share rise? Sky frames
(fine / recoverable from f1) rendered at ev 0 and at F2's ev, clamp and sigmoid mapper; white =
any channel ≥ 0.99 in the sRGB render, measured inside the sky mask.

  python f2sky.py --rows ~/LuminaEvidence/skyeval/f1/rows.jsonl --out ~/LuminaEvidence/skyeval/f2sky --sigmoid /Volumes/LuminaFactory/tmp/fits/rules-mapper-sigmoid.json
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import delta_e  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--sigmoid", required=True)
    ap.add_argument("--limit", type=int, default=60)
    a = ap.parse_args()
    out = os.path.expanduser(a.out)
    f1dir = os.path.dirname(os.path.expanduser(a.rows))
    rows = [json.loads(l) for l in open(os.path.expanduser(a.rows))]
    rows = [r for r in rows if r.get("truth") in ("fine", "recoverable") and "meter" in r and r["meter"]["ev"] > 0][: a.limit]
    for mapper, rules in (("clamp", None), ("sigmoid", a.sigmoid)):
        d = os.path.join(out, mapper)
        os.makedirs(d, exist_ok=True)
        jobs = []
        for r in rows:
            for k, look in (("base", ""), ("f2", f"ev:{r['meter']['ev']:+.2f}")):
                o = os.path.join(d, f"{r['stem']}__{k}.tif")
                if not os.path.exists(o):
                    jobs.append({"image": r["image"], "look": look, "px": 768, "space": "srgb", "out": o})
        if jobs:
            json.dump(jobs, open(os.path.join(d, "jobs.json"), "w"))
            subprocess.run([RENDER, "batch", os.path.join(d, "jobs.json")] + (["--rules", rules] if rules else []), stdout=subprocess.DEVNULL, check=False)
    res = []
    for r in rows:
        row = {"stem": r["stem"], "ev": r["meter"]["ev"], "verdict": r["truth"]}
        for mapper in ("clamp", "sigmoid"):
            for k in ("base", "f2"):
                p = os.path.join(out, mapper, f"{r['stem']}__{k}.tif")
                if not os.path.exists(p):
                    continue
                rgb = delta_e.read_rgb01(p)[0]
                H, W = rgb.shape[:2]
                sky = np.asarray(Image.open(os.path.join(f1dir, r["stem"], "sky.png")).convert("L").resize((W, H), Image.BILINEAR), np.float32) / 255 >= 0.5
                if sky.sum() == 0:
                    continue
                row[f"{mapper}_{k}"] = float((rgb.max(-1)[sky] >= 0.99).mean())
        res.append(row)
    summary = {"n": len(res), "evMedian": float(np.median([r["ev"] for r in res]))}
    for mapper in ("clamp", "sigmoid"):
        b = np.array([r[f"{mapper}_base"] for r in res if f"{mapper}_f2" in r]); f = np.array([r[f"{mapper}_f2"] for r in res if f"{mapper}_f2" in r])
        summary[mapper] = {"whiteBeforeMean": float(b.mean()), "whiteAfterMean": float(f.mean()), "rose>1pt": int(((f - b) > 0.01).sum()), "riseMedianPts": float(np.median(f - b) * 100), "riseP90Pts": float(np.percentile(f - b, 90) * 100)}
    json.dump({"summary": summary, "rows": res}, open(os.path.join(out, "f2sky.json"), "w"), indent=1)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
