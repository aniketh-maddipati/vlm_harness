#!/usr/bin/env python3
"""A contact sheet of mask lab runs: one row per clip (frames spread over it), one column per tracker plus the truth.

    python3 Tools/masklab/sheet.py OUT.jpg --clips DIR --labels DIR \
        --run vision-instance=RUN/vision-instance --run skim=RUN/skim [--objects a_1,b_2] [--per 6] [--width 2400]

Each tile is the frame with a mask tinted on it (green: the ground truth, magenta: the tracker) and a caption with
the tracker, the frame, its IoU against the label and, for skim, the frame's sure / shaky / lost state. Each frame
is a small grid of tiles (truth first, then each tracker), and a row holds --per frames of one clip. Frames come from
the clip (ffmpeg), so only clips you may show belong on a sheet: the public sets, not the owner's footage.
Writes a JPEG at quality 80, at most --width wide, and shrinks it until it is under --max-kb.
"""
import argparse, io, json, os, subprocess, sys, tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

GREEN = np.array([40, 220, 90], float)
MAGENTA = np.array([235, 40, 200], float)
STATE = {"sure": (60, 200, 90), "shaky": (240, 170, 30), "lost": (230, 60, 60)}


def frame(clip, n, tmp):
    out = os.path.join(tmp, f"{os.path.basename(clip)}-{n}.png")
    if not os.path.exists(out):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", clip, "-vf", f"select=eq(n\\,{n})", "-vsync", "0",
                        "-frames:v", "1", out], check=True)
    return Image.open(out).convert("RGB")


def mask(path, size):
    if not os.path.exists(path):
        return None
    return np.array(Image.open(path).convert("L").resize(size, Image.NEAREST)) >= 128


def tint(img, m, colour, alpha=0.5):
    a = np.array(img, float)
    if m is not None and m.any():
        a[m] = a[m] * (1 - alpha) + colour * alpha
        edge = m ^ np.pad(m, 1, mode="edge")[2:, 1:-1] | m ^ np.pad(m, 1, mode="edge")[1:-1, 2:]
        a[edge] = colour
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def iou(a, b):
    if a is None or b is None:
        return None
    u = (a | b).sum()
    return 1.0 if u == 0 else float((a & b).sum() / u)


def find(folder, n):
    for name in (f"{n:06d}.png", f"{n}.png", f"{n:05d}.png"):
        if os.path.exists(os.path.join(folder, name)):
            return os.path.join(folder, name)
    return os.path.join(folder, f"{n:06d}.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--clips", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--run", action="append", default=[], help="name=path to a tracker's run folder")
    ap.add_argument("--states", action="append", default=[],
                    help="name=states.json (calibrate.py --states-out): that column's strip from the file, not timing.json")
    ap.add_argument("--objects", default="")
    ap.add_argument("--per", type=int, default=6)
    ap.add_argument("--tile", type=int, default=0, help="tile width (default: fits --width)")
    ap.add_argument("--width", type=int, default=2400)
    ap.add_argument("--max-kb", type=int, default=600)
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    runs = [r.split("=", 1) for r in a.run]
    objects = [o for o in a.objects.split(",") if o] or sorted(os.listdir(a.labels))
    cols = 1 + len(runs)
    gc = 2 if cols > 2 else 1          # each frame's tiles as a small grid, gc tiles wide
    gr = -(-cols // gc)
    tile_w = a.tile or a.width // (a.per * gc)
    font = ImageFont.load_default()
    rows = []
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as tmp:
        for obj in objects:
            lab = os.path.join(a.labels, obj)
            frames = sorted(int(os.path.splitext(f)[0]) for f in os.listdir(lab) if f.endswith(".png"))
            pick = [frames[round(i * (len(frames) - 1) / max(1, a.per - 1))] for i in range(a.per)]
            clip = os.path.join(a.clips, obj + ".mov")
            states = {}
            for spec in a.states:
                sname, spath = spec.split("=", 1)
                for run_states in json.load(open(spath)).values():
                    if obj in run_states:
                        states[sname] = (run_states[obj]["start_frame"], run_states[obj]["sure_frames"])
            for name, path in runs:
                if name in states:
                    continue
                t = os.path.join(path, obj, "timing.json")
                if os.path.exists(t):
                    tj = json.load(open(t))
                    if tj.get("sure_frames"):
                        states[name] = (tj.get("start_frame", 0), tj["sure_frames"])
            blocks = []
            for n in pick:
                img = frame(clip, n, tmp)
                size = img.size
                gt = mask(find(lab, n), size)
                tiles = [(tint(img, gt, GREEN), f"{obj}  f{n}  truth")]
                for name, path in runs:
                    m = mask(find(os.path.join(path, obj), n), size)
                    v = iou(m, gt)
                    cap = f"{name}  IoU {'n/a' if v is None else f'{v:.2f}'}"
                    st = None
                    if name in states:
                        s0, sf = states[name]
                        if 0 <= n - s0 < len(sf):
                            st = sf[n - s0]
                            cap += f"  {st}"
                    tiles.append((tint(img, m, MAGENTA), cap, st))
                th = round(size[1] * tile_w / size[0])
                block = Image.new("RGB", (tile_w * gc + 4, th * gr), (20, 20, 20))
                for k, t in enumerate(tiles):
                    im = t[0].resize((tile_w, th), Image.LANCZOS)
                    d = ImageDraw.Draw(im)
                    d.rectangle([0, 0, tile_w, 14], fill=(0, 0, 0))
                    d.text((3, 1), t[1], fill=(255, 255, 255), font=font)
                    if len(t) > 2 and t[2] in STATE:
                        d.rectangle([0, th - 5, tile_w, th], fill=STATE[t[2]])
                    block.paste(im, ((k % gc) * tile_w, (k // gc) * th))
                blocks.append(block)
            bw = blocks[0].size[0]
            row = Image.new("RGB", (bw * len(blocks), max(b.size[1] for b in blocks) + 6), (0, 0, 0))
            for i, b in enumerate(blocks):
                row.paste(b, (i * bw, 0))
            rows.append(row)
    head = 22 if a.title else 0
    sheet = Image.new("RGB", (max(r.size[0] for r in rows), sum(r.size[1] for r in rows) + head), (0, 0, 0))
    if a.title:
        ImageDraw.Draw(sheet).text((6, 4), a.title, fill=(255, 255, 255), font=font)
    y = head
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.size[1]
    scale = 1.0
    while True:
        im = sheet if scale == 1.0 else sheet.resize((round(sheet.size[0] * scale), round(sheet.size[1] * scale)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=80, optimize=True)
        if buf.tell() <= a.max_kb * 1024 or scale < 0.3:
            break
        scale *= 0.9
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "wb") as fh:
        fh.write(buf.getvalue())
    print(f"{a.out}: {im.size[0]}×{im.size[1]}, {buf.tell() // 1024} KB")


if __name__ == "__main__":
    sys.exit(main())
