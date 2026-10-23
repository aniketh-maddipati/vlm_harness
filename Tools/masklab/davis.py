#!/usr/bin/env python3
"""Turn DAVIS 2017 (480p) into a mask lab evidence folder, so run-tracker-test.sh and score.py
measure the trackers against DAVIS's own ground truth.

    python3 Tools/masklab/davis.py DAVIS_ROOT OUT [--set val] [--seqs a,b]

DAVIS_ROOT is the unzipped DAVIS folder (Annotations/, JPEGImages/, ImageSets/). OUT gets:

    OUT/clips/<seq>.mov             the sequence as ProRes 4444 (near lossless), 24 fps
    OUT/clips/<seq>_<obj>.mov       a symlink per annotated object, so each object is its own clip
    OUT/labels/<seq>_<obj>/<n>.png  that object's ground truth on every frame, white on black
    OUT/prompts.json                each object's box on frame 0 (DAVIS's semi-supervised protocol
                                    gives the first-frame mask; the mask lab trackers take a box)

Then: LUMINA_VIDEO_DIR=OUT/clips MASKLAB_EVIDENCE=OUT bash Tools/masklab/run-tracker-test.sh
Needs numpy, Pillow and ffmpeg. Nothing is written outside OUT.
"""
import argparse, json, os, subprocess, sys

import numpy as np
from PIL import Image


def boxes(mask):
    """Object id → normalised [x, y, w, h] of its pixels in a DAVIS palette mask."""
    h, w = mask.shape
    out = {}
    for obj in sorted(int(v) for v in np.unique(mask) if v not in (0, 255)):
        ys, xs = np.nonzero(mask == obj)
        out[obj] = [round(xs.min() / w, 4), round(ys.min() / h, 4),
                    round((xs.max() + 1 - xs.min()) / w, 4), round((ys.max() + 1 - ys.min()) / h, 4)]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--set", default="val")
    ap.add_argument("--seqs", default="")
    a = ap.parse_args()

    seqs = [s for s in open(os.path.join(a.root, "ImageSets/2017", a.set + ".txt")).read().split() if s]
    if a.seqs:
        seqs = [s for s in seqs if s in a.seqs.split(",")]
    clips = os.path.join(a.out, "clips")
    os.makedirs(clips, exist_ok=True)
    prompts = {}
    for seq in seqs:
        jpg = os.path.join(a.root, "JPEGImages/480p", seq)
        ann = os.path.join(a.root, "Annotations/480p", seq)
        frames = sorted(f for f in os.listdir(ann) if f.endswith(".png"))
        mov = os.path.join(clips, seq + ".mov")
        if not os.path.exists(mov):
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", "24",
                            "-i", os.path.join(jpg, "%05d.jpg"), "-c:v", "prores_ks", "-profile:v", "4444",
                            "-pix_fmt", "yuv444p10le", "-vendor", "apl0", mov], check=True)
        first = np.array(Image.open(os.path.join(ann, frames[0])))
        for obj, box in boxes(first).items():
            key = f"{seq}_{obj}"
            link = os.path.join(clips, key + ".mov")
            if not os.path.lexists(link):
                os.symlink(seq + ".mov", link)
            prompts[key] = {"start": 0, "box": box, "frames": len(frames)}
            lab = os.path.join(a.out, "labels", key)
            os.makedirs(lab, exist_ok=True)
            for i, f in enumerate(frames):
                m = np.array(Image.open(os.path.join(ann, f)))
                Image.fromarray(((m == obj) * 255).astype(np.uint8)).save(os.path.join(lab, f"{i:06d}.png"))
        print(f"{seq}: {len(frames)} frames, {len(boxes(first))} objects", flush=True)
    # The sequence files themselves have no prompt: mark them so the runner lists them as skipped.
    with open(os.path.join(a.out, "prompts.json"), "w") as fh:
        json.dump(prompts, fh, indent=1)
    print(f"{len(prompts)} objects in {len(seqs)} sequences → {a.out}")


if __name__ == "__main__":
    sys.exit(main())
