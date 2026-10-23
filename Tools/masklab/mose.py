#!/usr/bin/env python3
"""MOSE v1 (crowds, look-alikes, heavy occlusion) → a mask lab evidence folder.

    python3 Tools/masklab/mose.py OUT [--max-objects 100] [--per-video 3] [--data DIR]

MOSE's val split has no public truth past the first frame, so its train split is used as a held-out set (nothing
here trains on it). train.tar.gz (22 GB) sits inside MOSE_release.zip on Hugging Face (FudanCVL/MOSE); it is read
as one stream (remotezip + tarfile), only the chosen videos are written to DATA/mose/, and the stream stops once
they are all in, so most of the 22 GB is never fetched. Video ids are hashes, so taking them in sorted order is a
fair sample; up to --per-video objects per video keep the cap spread over more scenes. Clips are ProRes at 480 px
high; the number of objects in the video is a tag (crowd when it has 4 or more). Licence: CC BY-NC-SA 4.0.
"""
import argparse, json, os, sys, tarfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_common import Writer, make_clip  # noqa: E402
from remotezip import RemoteZip  # noqa: E402

URL = "https://huggingface.co/datasets/FudanCVL/MOSE/resolve/main/MOSE_release.zip"
H = 480


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--max-objects", type=int, default=100)
    ap.add_argument("--per-video", type=int, default=3)
    ap.add_argument("--data", default="/Volumes/LuminaFactory/datasets")
    a = ap.parse_args()
    if not os.path.isdir("/Volumes/T7/Lumina"):
        sys.exit("mose: the T7 isn't mounted")
    root = os.path.join(a.data, "mose")
    z = RemoteZip(URL)
    meta = json.loads(z.read("MOSE_release/meta_train.json"))["videos"]
    picked, n = [], 0
    for vid in sorted(meta):
        if n >= a.max_objects:
            break
        k = min(a.per_video, len(meta[vid]["objects"]), a.max_objects - n)
        picked.append((vid, meta[vid]["objects"][:k]))
        n += k
    want = {v for v, _ in picked}
    done = {v: os.path.isdir(os.path.join(root, "train/JPEGImages", v)) for v in want}
    if not all(done.values()):
        with z.open("MOSE_release/train.tar.gz") as src, tarfile.open(fileobj=src, mode="r|gz") as tar:
            seen_jpg = set()
            for m in tar:
                parts = m.name.strip("./").split("/")
                if len(parts) >= 3 and parts[-2] in want and m.isfile():
                    tar.extract(m, root, filter="data")
                    if parts[-3] == "JPEGImages":
                        seen_jpg.add(parts[-2])
                # The tar lists a video's folder in one run: once every chosen video's frames went by
                # and we are past the last one, stop reading.
                if len(parts) >= 3 and parts[-3] == "JPEGImages" and seen_jpg >= want and parts[-2] > max(want):
                    break
            print(f"MOSE: {z.remote.fetched / 1e9:.1f} GB of 22.1 read", flush=True)
    w = Writer(a.out)
    for vid, objs in picked:
        jdir = os.path.join(root, "train/JPEGImages", vid)
        adir = os.path.join(root, "train/Annotations", vid)
        jpgs = sorted(os.path.join(jdir, f) for f in os.listdir(jdir) if f.endswith(".jpg"))
        clip = w.clip_path(vid)
        make_clip(jpgs, clip, fps=24, height=H)
        W0, H0 = Image.open(jpgs[0]).size
        size = (round(W0 * H / H0 / 2) * 2, H)
        per = {o: {} for o in objs}
        for i, j in enumerate(jpgs):
            p = os.path.join(adir, os.path.splitext(os.path.basename(j))[0] + ".png")
            if os.path.exists(p):
                m = np.array(Image.open(p).resize(size, Image.NEAREST))
                for o in objs:
                    per[o][i] = m == o
        crowd = ["crowd"] if len(meta[vid]["objects"]) >= 4 else []
        for o in objs:
            w.add(vid, f"{vid}_{o}", per[o], len(jpgs), extra_tags=crowd + [f"objects-{len(meta[vid]['objects'])}"])
        print(f"{vid}: {len(jpgs)} frames, objects {objs} of {len(meta[vid]['objects'])}", flush=True)
    w.save()
    print(f"{len(w.prompts)} objects → {a.out}")


if __name__ == "__main__":
    main()
