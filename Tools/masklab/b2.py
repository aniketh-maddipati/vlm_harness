#!/usr/bin/env python3
"""B2 / E4: skim tracks the box, Apple's prompted segmenter makes the mask.

    python3 Tools/masklab/b2.py --skim RUN/skim --davis DAVIS_ROOT --out RUN [--quality balanced]

For every clip of a masklab-skim run on DAVIS: each frame's box is the bounding box of skim's mask there (the last
non-empty one when skim's is empty; none before the first), handed to `masklab-iterative --track`, which writes
RUN/iterative-on-skim/<clip>/ in the mask lab layout. Then RUN/skim+iterative-fallback/<clip>/ mixes the two: skim's
own mask on frames skim calls sure, the prompted mask on shaky and lost ones (E4 with Apple's model), and its
timing.json counts skim's time plus the model's on those frames only, so its fps is what the app would see.
"""
import argparse, json, os, subprocess, sys

import numpy as np
from PIL import Image

F = os.environ.get("F", "/Volumes/LuminaFactory")
ITER = os.path.join(F, "build/iterative/masklab-iterative")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skim", required=True)
    ap.add_argument("--davis", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--quality", default="balanced")
    ap.add_argument("--objects", default="")
    a = ap.parse_args()
    if not os.path.isdir("/Volumes/T7/Lumina"):
        sys.exit("b2: the T7 isn't mounted")
    clips = [c for c in a.objects.split(",") if c] or sorted(d for d in os.listdir(a.skim) if os.path.isdir(os.path.join(a.skim, d)))
    it_name, fb_name = "iterative-on-skim", "skim+iterative-fallback"
    for clip in clips:
        sdir = os.path.join(a.skim, clip)
        timing = json.load(open(os.path.join(sdir, "timing.json")))
        seq = clip.rsplit("_", 1)[0]
        jdir = os.path.join(a.davis, "JPEGImages/480p", seq)
        jpgs = sorted(f for f in os.listdir(jdir) if f.endswith(".jpg"))
        start = int(timing.get("start_frame", 0))
        frames, box = [], None
        for n in range(start, len(jpgs)):
            p = os.path.join(sdir, f"{n:06d}.png")
            if os.path.exists(p):
                m = np.array(Image.open(p).convert("L")) >= 128
                ys, xs = np.nonzero(m)
                if len(xs):
                    h, w = m.shape
                    box = [xs.min() / w, ys.min() / h, (xs.max() + 1 - xs.min()) / w, (ys.max() + 1 - ys.min()) / h]
            frames.append({"n": n, "image": os.path.join(jdir, jpgs[n]), "box": box})
        job = os.path.join(F, "tmp", f"b2-{clip}.json")
        json.dump({"clip": clip, "frames": frames}, open(job, "w"))
        out = os.path.join(a.out, it_name, clip)
        r = subprocess.run([ITER, "--track", job, "--out", out, "--quality", a.quality, "--tracker", it_name],
                           capture_output=True, text=True)
        os.remove(job)
        if r.returncode:
            print(f"{clip}: failed {r.stderr.strip()[-300:]}", flush=True)
            continue
        print(r.stdout.strip(), flush=True)
        it = json.load(open(os.path.join(out, "timing.json")))
        # E4: skim's mask where it says sure, the prompted mask elsewhere.
        states = timing.get("sure_frames") or []
        fb = os.path.join(a.out, fb_name, clip)
        os.makedirs(fb, exist_ok=True)
        extra, used = 0.0, 0
        for k, n in enumerate(range(start, len(jpgs))):
            st = states[k] if k < len(states) else "lost"
            src = os.path.join(sdir if st == "sure" else out, f"{n:06d}.png")
            if os.path.exists(src):  # skim's masks are at its proxy size: bring them to the frame's
                Image.open(src).convert("L").resize(tuple(it["proxy"]), Image.NEAREST).save(os.path.join(fb, f"{n:06d}.png"))
            if st != "sure":
                extra += it["per_frame_ms"][k] if k < len(it["per_frame_ms"]) else 0
                used += 1
        json.dump({"tracker": fb_name, "clip": clip, "start_frame": start, "frames": len(jpgs) - start,
                   "total_ms": float(timing.get("total_ms", 0)) + extra, "model_frames": used,
                   "sure_frames": states, "proxy": it.get("proxy")}, open(os.path.join(fb, "timing.json"), "w"))


if __name__ == "__main__":
    main()
