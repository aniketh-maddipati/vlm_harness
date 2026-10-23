#!/usr/bin/env python3
"""VOST (objects that change shape: cutting, peeling, folding) → a mask lab evidence folder.

    python3 Tools/masklab/vost.py OUT [--split val] [--max-objects 100] [--data DIR]

Reads only the chosen videos out of the 54 GB VOST.zip with range requests (remotezip.py) into
DATA/vost/ (default /Volumes/LuminaFactory/datasets/vost), then writes OUT/clips, OUT/labels and
OUT/prompts.json (convert_common.py). Frames are 5 fps, as VOST samples them; clips and labels are
scaled to 480 px high, like DAVIS 480p. The action in the name ("cut", "peel", …) is kept as a tag.
Licence: CC BY-NC-SA 4.0.
"""
import argparse, os, sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_common import Writer, make_clip  # noqa: E402
from remotezip import RemoteZip  # noqa: E402

URL = "https://tri-ml-public.s3.amazonaws.com/datasets/VOST.zip"
H = 480


def spread(videos, cap_objects, objects_of):
    """Round-robin over the action verbs so the subset covers every kind of change."""
    by = {}
    for v in videos:
        by.setdefault(v.split("_")[1], []).append(v)
    picked, n = [], 0
    while n < cap_objects and any(by.values()):
        for verb in sorted(by):
            if by[verb] and n < cap_objects:
                v = by[verb].pop(0)
                picked.append(v)
                n += objects_of(v)
    return picked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--split", default="val")
    ap.add_argument("--max-objects", type=int, default=100)
    ap.add_argument("--data", default="/Volumes/LuminaFactory/datasets")
    a = ap.parse_args()
    if not os.path.isdir("/Volumes/T7/Lumina"):
        sys.exit("vost: the T7 isn't mounted")
    root = os.path.join(a.data, "vost")
    z = RemoteZip(URL)
    names = z.namelist()
    videos = [v for v in z.read(f"VOST/ImageSets/{a.split}.txt").decode().split() if v]

    def members(v):
        return [n for n in names if (n.startswith(f"VOST/JPEGImages/{v}/") or n.startswith(f"VOST/Annotations/{v}/"))
                and not n.endswith("/")]

    def objects_of(v):
        ann = sorted(n for n in members(v) if "/Annotations/" in n)
        z.extract_many(ann[:1], root)
        m = np.array(Image.open(os.path.join(root, ann[0])))
        return max(1, len([x for x in np.unique(m) if x not in (0, 255)]))

    picked = spread(videos, a.max_objects, objects_of)
    w = Writer(a.out)
    for v in picked:
        z.extract_many(members(v), root)
        jpgs = sorted(os.path.join(root, n) for n in members(v) if "/JPEGImages/" in n and n.endswith(".jpg"))
        anns = {os.path.splitext(os.path.basename(n))[0]: os.path.join(root, n)
                for n in members(v) if "/Annotations/" in n and n.endswith(".png")}
        clip = w.clip_path(v)
        if not os.path.exists(clip):
            make_clip(jpgs, clip, fps=5)
        W0, H0 = Image.open(jpgs[0]).size
        size = (round(W0 * H / H0 / 2) * 2, H)
        per = {}
        for i, j in enumerate(jpgs):
            stem = os.path.splitext(os.path.basename(j))[0]
            if stem in anns:
                m = np.array(Image.open(anns[stem]).resize(size, Image.NEAREST))
                for obj in np.unique(m):
                    if obj not in (0, 255):
                        per.setdefault(int(obj), {})[i] = m == obj
        for obj, masks in sorted(per.items()):
            for i in range(len(jpgs)):
                if i in masks or any(s in anns for s in []):
                    pass
            # frames with a label file but no pixels of this object count as "gone"
            for i, j in enumerate(jpgs):
                if os.path.splitext(os.path.basename(j))[0] in anns and i not in masks:
                    masks[i] = np.zeros((size[1], size[0]), bool)
            w.add(v, f"{v}_{obj}", masks, len(jpgs), extra_tags=("shape-change", v.split("_")[1]))
        print(f"{v}: {len(jpgs)} frames, {len(per)} objects, {z.remote.fetched / 1e6:.0f} MB read so far", flush=True)
    w.save()
    print(f"{len(w.prompts)} objects → {a.out}")


if __name__ == "__main__":
    main()
