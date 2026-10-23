#!/usr/bin/env python3
"""Experiment B (docs/masking/OUTLINING.md): prompted masks on the objects Vision merges, on one frame.

    python prompts_merged.py --davis DAVIS_ROOT --oracle RUN/vision-oracle --out DIR \
        [--seqs lab-coat,gold-fish,pigs,shooting] [--frame 0] [--models vision-balanced,vision-accurate,sam2.1-small]

For every labelled object on the frame, each model is prompted three ways and scored (IoU) against the label:
  click   one include point: the label's pixel nearest its centroid
  clicks  that point plus one exclude point on the neighbour Vision merged in: the pixel of (Vision's best instance −
          the label) nearest that region's centroid; with nothing merged, the nearest other object's centre
  box     the label's bounding box
next to Vision's best instance on that frame (vision-oracle). Writes DIR/results.json, and DIR/<model>/<key>-<prompt>.png
for the sheet. Models: vision-fast|balanced|accurate (masklab-iterative, Vision's GenerateIterativeSegmentationRequest),
sam2.1-small|large and edgetam (the SAM 2 image predictor; edgetam needs its own venv). Times are ms for the
first request and for the request after the exclude point.
"""
import argparse, json, os, subprocess, sys, time

import numpy as np
from PIL import Image

F = os.environ.get("F", "/Volumes/LuminaFactory")
ITER = os.path.join(F, "build/iterative/masklab-iterative")


def nearest(mask, p):
    ys, xs = np.nonzero(mask)
    i = np.argmin((xs - p[0]) ** 2 + (ys - p[1]) ** 2)
    return float(xs[i]), float(ys[i])


def centre(mask):
    ys, xs = np.nonzero(mask)
    return nearest(mask, (xs.mean(), ys.mean()))


def iou(a, b):
    u = (a | b).sum()
    return 1.0 if u == 0 else float((a & b).sum() / u)


class Sam:
    def __init__(self, model):
        import torch
        from sam2.build_sam import build_sam2
        from sam2.sam2_image_predictor import SAM2ImagePredictor
        self.torch = torch
        dev = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
        if model == "edgetam":
            cfg, ck = "configs/edgetam.yaml", os.path.join(F, "src/EdgeTAM/checkpoints/edgetam.pt")
        else:
            size = model.split("-")[1]
            cfg ={"small": "configs/sam2.1/sam2.1_hiera_s.yaml", "large": "configs/sam2.1/sam2.1_hiera_l.yaml"}[size]
            ck = os.path.join(F, "models/sam2.1", f"sam2.1_hiera_{size}.pt")
        self.p = SAM2ImagePredictor(build_sam2(cfg, ck, device=dev))
        self.img = None

    def run(self, img, path, prompt):
        """prompt: ("click", [(x,y)]) | ("clicks", [(x,y,+1),(x,y,0)]) | ("box", [x0,y0,x1,y1]). Returns mask, ms list."""
        t = []
        with self.torch.inference_mode():
            if self.img is not path:
                t0 = time.perf_counter()
                self.p.set_image(img)
                self.enc = (time.perf_counter() - t0) * 1000
                self.img = path
            kind, v = prompt
            t0 = time.perf_counter()
            if kind == "box":
                m, _, _ = self.p.predict(box=np.array(v, np.float32), multimask_output=False)
            else:
                pts = np.array([[x, y] for x, y, *_ in v], np.float32)
                lab = np.array([(1 if len(q) < 3 else q[2]) for q in v], np.int32)
                m, s, _ = self.p.predict(point_coords=pts, point_labels=lab, multimask_output=len(v) == 1)
                m = m[int(np.argmax(s))][None] if len(v) == 1 else m
            t.append((time.perf_counter() - t0) * 1000)
        return m[0] > 0, t


def vision(img_path, size, quality, prompt, out):
    w, h = size
    kind, v = prompt
    args = [ITER, img_path, "--out", out, "--quality", quality]
    if kind == "box":
        x0, y0, x1, y1 = v
        args += ["--seed-box", f"{x0 / w},{y0 / h},{(x1 - x0) / w},{(y1 - y0) / h}"]
    else:
        args += ["--seed-point", f"{v[0][0] / w},{v[0][1] / h}"]
        for q in v[1:]:
            args += ["--remove", f"{q[0] / w},{q[1] / h}"]
    r = json.loads(subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip().splitlines()[-1])
    last = f"{out}-{len(r['ms']) - 1}.png"
    m = np.array(Image.open(last).convert("L").resize(size, Image.BILINEAR)) >= 128 if os.path.exists(last) else np.zeros((h, w), bool)
    return m, r["ms"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--davis", required=True)
    ap.add_argument("--oracle", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seqs", default="lab-coat,gold-fish,pigs,shooting")
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--models", default="vision-balanced,vision-accurate,sam2.1-small")
    a = ap.parse_args()
    if not os.path.isdir("/Volumes/T7/Lumina"):
        sys.exit("prompts_merged: the T7 isn't mounted")
    res_path = os.path.join(a.out, "results.json")
    results = json.load(open(res_path)) if os.path.exists(res_path) else {}
    models = a.models.split(",")
    sams = {m: Sam(m) for m in models if not m.startswith("vision-")}
    for seq in a.seqs.split(","):
        jpg = os.path.join(a.davis, "JPEGImages/480p", seq, f"{a.frame:05d}.jpg")
        img = np.array(Image.open(jpg).convert("RGB"))
        h, w = img.shape[:2]
        lab = np.array(Image.open(os.path.join(a.davis, "Annotations/480p", seq, f"{a.frame:05d}.png")))
        objs = [int(o) for o in np.unique(lab) if o not in (0, 255)]
        for o in objs:
            key = f"{seq}_{o}"
            truth = lab == o
            if not truth.any():
                continue
            pos = centre(truth)
            om = os.path.join(a.oracle, key, f"{a.frame:06d}.png")
            vis = np.array(Image.open(om).convert("L").resize((w, h), Image.NEAREST)) >= 128 if os.path.exists(om) else np.zeros_like(truth)
            merged = vis & ~truth
            if merged.sum() > 50:
                neg = centre(merged)
            else:
                others = [centre(lab == q) for q in objs if q != o and (lab == q).any()]
                neg = min(others, key=lambda p: (p[0] - pos[0]) ** 2 + (p[1] - pos[1]) ** 2) if others else None
            ys, xs = np.nonzero(truth)
            prompts = {"click": ("click", [pos]), "box": ("box", [xs.min(), ys.min(), xs.max() + 1, ys.max() + 1])}
            if neg:
                prompts["clicks"] = ("clicks", [(pos[0], pos[1], 1), (neg[0], neg[1], 0)])
            r = results.setdefault(key, {"vision_oracle": iou(vis, truth), "merged_px": int(merged.sum()),
                                         "pos": pos, "neg": neg, "box": [int(v) for v in prompts["box"][1]]})
            for m in models:
                d = os.path.join(a.out, m)
                os.makedirs(d, exist_ok=True)
                for pname, pr in prompts.items():
                    png = os.path.join(d, f"{key}-{pname}.png")
                    if m.startswith("vision-"):
                        mask, ms = vision(jpg, (w, h), m.split("-")[1], pr, os.path.join(a.out, "tmp", f"{m}-{key}-{pname}"))
                    else:
                        mask, ms = sams[m].run(img, jpg, pr)
                        ms = [round(sams[m].enc, 1)] + [round(x, 1) for x in ms]
                    Image.fromarray((mask * 255).astype(np.uint8)).save(png)
                    r.setdefault(m, {})[pname] = {"iou": round(iou(mask, truth), 4), "ms": [round(x, 1) for x in ms]}
            print(key, json.dumps({k: (v if not isinstance(v, dict) else {p: q["iou"] for p, q in v.items()}) for k, v in r.items() if k not in ("pos", "neg", "box")}), flush=True)
            with open(res_path, "w") as fh:
                json.dump(results, fh, indent=1)


if __name__ == "__main__":
    main()
