#!/usr/bin/env python3
"""LaSOT (long single-object tracking: ~2,500 frames a clip, fast motion, small targets) → a mask lab evidence folder.

    python3 Tools/masklab/lasot.py OUT [--max-objects 100] [--every 10] [--data DIR]

Takes videos from LaSOT's test split (testing_set.txt, 4 per category): one per category first, then a second
from as many categories as the cap allows. Each video's frames are read out of its category zip on Hugging Face
(l-lt/LaSOT) with range requests, encoded into an H.264 clip at 480 px high, and then deleted: only the clip and
the labels are kept. LaSOT's truth is a box, so labels are filled boxes (tag box-only: IoU and F are box measures
there), written every --every frames, and empty where LaSOT marks the target fully occluded or out of view.
LaSOT's own flags become tags (occluded, out-of-view). Licence: LaSOT's terms (research use), see the homepage.
"""
import argparse, os, shutil, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_common import Writer, make_clip  # noqa: E402
from remotezip import RemoteZip  # noqa: E402

BASE = "https://huggingface.co/datasets/l-lt/LaSOT/resolve/main"
H = 480


def flags(z, name):
    try:
        raw = z.read(name).decode().replace(",", " ").split()
        return np.array([int(float(v)) for v in raw], bool)
    except KeyError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--max-objects", type=int, default=100)
    ap.add_argument("--every", type=int, default=10)
    ap.add_argument("--data", default="/Volumes/LuminaFactory/datasets")
    a = ap.parse_args()
    if not os.path.isdir("/Volumes/T7/Lumina"):
        sys.exit("lasot: the T7 isn't mounted")
    import urllib.request
    test = urllib.request.urlopen(f"{BASE}/testing_set.txt").read().decode().split()
    by = {}
    for v in test:
        by.setdefault(v.rsplit("-", 1)[0], []).append(v)
    picked = []
    for rnd in range(4):
        for cat in sorted(by):
            if len(picked) < a.max_objects and len(by[cat]) > rnd:
                picked.append(by[cat][rnd])
    tmp = os.path.join(os.environ.get("TMPDIR", "/Volumes/LuminaFactory/tmp"), "lasot")
    w = Writer(a.out)
    zips = {}
    for v in picked:
        if v in w.prompts:
            continue
        cat = v.rsplit("-", 1)[0]
        if cat not in zips:
            zips.clear()
            zips[cat] = RemoteZip(f"{BASE}/{cat}.zip")
        z = zips[cat]
        imgs = sorted(n for n in z.namelist() if n.startswith(f"{v}/img/") and n.endswith(".jpg"))
        gt = np.array([[float(x) for x in l.replace(",", " ").split()] for l in z.read(f"{v}/groundtruth.txt").decode().splitlines() if l.strip()])
        occ, oov = flags(z, f"{v}/full_occlusion.txt"), flags(z, f"{v}/out_of_view.txt")
        clip = w.clip_path(v)
        if not os.path.exists(clip):
            shutil.rmtree(os.path.join(tmp, v), ignore_errors=True)
            z.extract_many(imgs, tmp)
            make_clip([os.path.join(tmp, n) for n in imgs], clip, fps=30, codec="h264", height=H)
        from PIL import Image
        z.extract_many(imgs[:1], tmp)  # the source size, which the boxes are in
        W0, H0 = Image.open(os.path.join(tmp, imgs[0])).size
        shutil.rmtree(os.path.join(tmp, v), ignore_errors=True)
        s = H / H0
        size = (round(W0 * s / 2) * 2, H)
        absent = np.zeros(len(gt), bool)
        for f in (occ, oov):
            if f is not None and len(f) == len(gt):
                absent |= f
        masks = {}
        for i in range(0, len(gt), a.every):
            m = np.zeros((size[1], size[0]), bool)
            x, y, bw, bh = gt[i]
            if not absent[i] and bw > 0 and bh > 0:
                x0, y0 = max(0, round(x * s)), max(0, round(y * s))
                m[y0:max(y0 + 1, round((y + bh) * s)), x0:max(x0 + 1, round((x + bw) * s))] = True
            masks[i] = m
        extra = [cat]
        if occ is not None and occ.any():
            extra.append("occluded")
        if oov is not None and oov.any():
            extra.append("out-of-view")
        w.add(v, v, masks, len(imgs), extra_tags=extra, box_only=True)
        w.save()
        print(f"{v}: {len(imgs)} frames, {z.remote.fetched / 1e9:.1f} GB read from {cat}.zip", flush=True)
    w.save()
    print(f"{len(w.prompts)} objects → {a.out}")


if __name__ == "__main__":
    main()
