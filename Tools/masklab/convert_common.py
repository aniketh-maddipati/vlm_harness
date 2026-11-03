"""What every dataset converter shares: frames → a clip, per-object labels, prompts.json with attribute tags.

A converter (davis.py, vost.py, lasot.py, …) hands `Writer.add` one object at a time: the clip it lives in, and its
ground truth as {frame index: bool mask} (sparse is fine). The writer saves the labels, the first labelled frame's
box as the prompt, and tags measured from the masks:

    small     median area under 1 % of the frame
    long      the clip has more than 1,000 frames
    occluded  on some labelled frame the area drops under 30 % of its median (0 counts: the object is gone)
    fast      the box centre moves more than 5 % of the frame's diagonal per frame, on average
    box-only  the ground truth is a box, not a mask (LaSOT): IoU and F there are box measures

plus the set's own tags. prompts.json keeps them under "_tags" (keys starting with _ are ignored by the runner).
"""
import json, os, subprocess

import numpy as np
from PIL import Image


def make_clip(pattern, out, fps=24, start=0, codec="prores", height=None):
    """pattern: an ffmpeg image pattern (…/%05d.jpg) or a list of files (written as a concat list).
    codec "prores" (4444, near lossless) for short sets; "h264" (CRF 14) for long ones (LaSOT, LVOS), where ProRes
    would take tens of GB. height scales the frames (even width kept)."""
    if os.path.exists(out):
        return out
    os.makedirs(os.path.dirname(out), exist_ok=True)
    scale = f"scale=-2:{height}" if height else "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    if codec == "h264":
        common = ["-c:v", "libx264", "-crf", "14", "-preset", "medium", "-pix_fmt", "yuv420p", "-vf", scale]
    else:
        common = ["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuv444p10le", "-vendor", "apl0", "-vf", scale]
    if isinstance(pattern, list):
        lst = out + ".txt"
        with open(lst, "w") as fh:
            for p in pattern:
                fh.write(f"file '{os.path.abspath(p)}'\nduration {1 / fps:.6f}\n")
        cmd = ["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-r", str(fps)]
    else:
        cmd = ["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-start_number", str(start), "-i", pattern]
    subprocess.run(cmd + common + [out + ".part.mov"], check=True)
    os.replace(out + ".part.mov", out)
    if isinstance(pattern, list):
        os.remove(lst)
    return out


def box_of(m):
    ys, xs = np.nonzero(m)
    if not len(xs):
        return None
    h, w = m.shape
    return [xs.min() / w, ys.min() / h, (xs.max() + 1 - xs.min()) / w, (ys.max() + 1 - ys.min()) / h]


def tags_of(masks, n_frames, extra=()):
    idx = sorted(masks)
    areas = np.array([masks[i].mean() for i in idx])
    t = set(extra)
    nz = areas[areas > 0]
    med = float(np.median(nz)) if len(nz) else 0.0
    if med < 0.01:
        t.add("small")
    if n_frames > 1000:
        t.add("long")
    if med and (areas < 0.3 * med).any():
        t.add("occluded")
    centres = []
    for i in idx:
        b = box_of(masks[i])
        if b:
            centres.append((i, b[0] + b[2] / 2, b[1] + b[3] / 2))
    steps = [np.hypot(x1 - x0, y1 - y0) / max(1, f1 - f0) / np.sqrt(2)
             for (f0, x0, y0), (f1, x1, y1) in zip(centres, centres[1:])]
    if steps and float(np.mean(steps)) > 0.05:
        t.add("fast")
    return sorted(t)


class Writer:
    """OUT/clips/<clip>.mov (+ a symlink per object), OUT/labels/<key>/<n>.png, OUT/prompts.json."""

    def __init__(self, out):
        self.out = out
        os.makedirs(os.path.join(out, "clips"), exist_ok=True)
        p = os.path.join(out, "prompts.json")
        self.prompts = json.load(open(p)) if os.path.exists(p) else {}

    def clip_path(self, clip):
        return os.path.join(self.out, "clips", clip + ".mov")

    def add(self, clip, key, masks, n_frames, extra_tags=(), box_only=False):
        """masks: {frame: HxW bool}. The first labelled frame with the object in it is the prompt."""
        first = next((i for i in sorted(masks) if masks[i].any()), None)
        if first is None:
            return False
        link = os.path.join(self.out, "clips", key + ".mov")
        if not os.path.lexists(link) and key != clip:
            os.symlink(clip + ".mov", link)
        lab = os.path.join(self.out, "labels", key)
        os.makedirs(lab, exist_ok=True)
        for i, m in masks.items():
            if i >= first:
                Image.fromarray((m * 255).astype(np.uint8)).save(os.path.join(lab, f"{i:06d}.png"))
        tags = tags_of({i: m for i, m in masks.items() if i >= first}, n_frames,
                       tuple(extra_tags) + (("box-only",) if box_only else ()))
        self.prompts[key] = {"start": first, "box": [round(v, 4) for v in box_of(masks[first])],
                             "frames": n_frames - first, "_tags": tags}
        return True

    def save(self):
        with open(os.path.join(self.out, "prompts.json"), "w") as fh:
            json.dump(self.prompts, fh, indent=1)
