#!/usr/bin/env python3
"""Brush select on the objects Vision merges: a simulated stroke into GenerateIterativeSegmentationRequest(seedScribbleBuffer:).

    python scribble_merged.py --davis DAVIS_ROOT --b DIR [--width 0.02] [--quality balanced]

For each object of experiment B (DIR/results.json from prompts_merged.py), the stroke is the label's skeleton
(skimage), drawn --width of the frame's long edge wide and kept inside the label: a brush run down the middle of
the object. It goes to masklab-iterative --seed-scribble as a one-channel 8-bit mask (255 = stroke) at the image's
size, top-left origin. Writes the masks to DIR/scribble/ and adds a "scribble" entry (iou, ms) per object to
results.json, next to click, clicks and box.
"""
import argparse, json, os, subprocess

import numpy as np
from PIL import Image
from skimage.morphology import dilation, disk, skeletonize

F = os.environ.get("F", "/Volumes/LuminaFactory")
ITER = os.path.join(F, "build/iterative/masklab-iterative")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--davis", required=True)
    ap.add_argument("--b", required=True)
    ap.add_argument("--width", type=float, default=0.02)
    ap.add_argument("--quality", default="balanced")
    ap.add_argument("--frame", type=int, default=0)
    a = ap.parse_args()
    path = os.path.join(a.b, "results.json")
    res = json.load(open(path))
    out = os.path.join(a.b, "scribble")
    os.makedirs(out, exist_ok=True)
    model = f"vision-{a.quality}"
    for key, r in res.items():
        seq, obj = key.rsplit("_", 1)
        lab = np.array(Image.open(os.path.join(a.davis, "Annotations/480p", seq, f"{a.frame:05d}.png"))) == int(obj)
        rad = max(1, round(a.width * max(lab.shape) / 2))
        stroke = dilation(skeletonize(lab), disk(rad)) & lab
        sp = os.path.join(out, f"{key}-stroke.png")
        Image.fromarray((stroke * 255).astype(np.uint8)).save(sp)
        jpg = os.path.join(a.davis, "JPEGImages/480p", seq, f"{a.frame:05d}.jpg")
        o = os.path.join(out, key)
        p = subprocess.run([ITER, jpg, "--out", o, "--quality", a.quality, "--seed-scribble", sp], capture_output=True, text=True)
        if p.returncode or not os.path.exists(o + "-0.png"):
            r.setdefault(model, {})["scribble"] = {"iou": 0.0, "ms": [], "error": p.stderr.strip()[-200:]}
        else:
            ms = json.loads(p.stdout.strip().splitlines()[-1])["ms"]
            m = np.array(Image.open(o + "-0.png").convert("L").resize(lab.shape[::-1], Image.BILINEAR)) >= 128
            iou = float((m & lab).sum() / max(1, (m | lab).sum()))
            r.setdefault(model, {})["scribble"] = {"iou": round(iou, 4), "ms": [round(x, 1) for x in ms], "stroke_px": int(stroke.sum())}
        print(key, r[model].get("click", {}).get("iou"), r[model].get("box", {}).get("iou"), r[model]["scribble"]["iou"], flush=True)
    json.dump(res, open(path, "w"), indent=1)


if __name__ == "__main__":
    main()
