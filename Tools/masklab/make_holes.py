#!/usr/bin/env python3
"""Made-up holes for scoring video healing where the truth is known (the protocol of the video
inpainting papers, E2FGVI and ProPainter, on DAVIS): a free-form hole of a few thick strokes that
drifts across the clip, so the frames themselves are the truth for whatever fills it.

  make_holes.py FRAMES_DIR OUT_DIR [--area 0.10] [--seed NAME] [--still]

FRAMES_DIR holds the clip's frames (`00000.jpg` …, DAVIS's JPEGImages/480p/<clip>); OUT_DIR gets one
8-bit PNG per frame, same number, white in the hole. The hole is the same for the same --seed (the
clip's name by default), covers about --area of the frame, and moves a few pixels a frame,
bouncing off the edges; --still keeps it in one place (a hole a still camera's plate can fill).
"""
import argparse, hashlib, math, os, re, sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    Image = None

FRAME = re.compile(r"^(\d+)\.(png|jpe?g)$", re.IGNORECASE)


def strokes(rng, w, h, area):
    """A few thick strokes around the centre, together about `area` of the frame."""
    n = 2 + int(rng() * 3)
    width = max(6, int(min(w, h) * (0.06 + 0.04 * rng())))
    reach = math.sqrt(area * w * h) * 0.9
    pts = []
    for _ in range(n):
        a, r = rng() * 2 * math.pi, reach * (0.3 + 0.7 * rng())
        pts.append((r * math.cos(a), r * math.sin(a)))
    return [(0.0, 0.0)] + pts, width


def lcg(seed):
    s = int(hashlib.sha1(seed.encode()).hexdigest()[:8], 16) or 1
    def nxt():
        nonlocal s
        s = (1103515245 * s + 12345) % 2 ** 31
        return s / 2 ** 31
    return nxt


def draw(pts, width, cx, cy, w, h):
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    q = [(cx + x, cy + y) for x, y in pts]
    d.line(q, fill=255, width=width, joint="curve")
    for x, y in q:
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=255)
    return m


def make(frames_dir, out_dir, area=0.10, seed=None, still=False):
    names = sorted((int(m.group(1)), f) for f in os.listdir(frames_dir) if (m := FRAME.match(f)))
    if not names:
        raise SystemExit(f"no frames in {frames_dir}")
    w, h = Image.open(os.path.join(frames_dir, names[0][1])).size
    rng = lcg(seed or os.path.basename(os.path.normpath(frames_dir)))
    pts, width = strokes(rng, w, h, area)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    pad = width
    lo_x, hi_x = -min(xs) + pad, w - max(xs) - pad
    lo_y, hi_y = -min(ys) + pad, h - max(ys) - pad
    cx, cy = lo_x + (hi_x - lo_x) * rng(), lo_y + (hi_y - lo_y) * rng()
    speed = 0 if still else min(w, h) * (0.004 + 0.006 * rng())
    a = rng() * 2 * math.pi
    vx, vy = speed * math.cos(a), speed * math.sin(a)
    os.makedirs(out_dir, exist_ok=True)
    for n, _ in names:
        draw(pts, width, cx, cy, w, h).save(os.path.join(out_dir, f"{n:05d}.png"))
        cx, cy = cx + vx, cy + vy
        if not lo_x <= cx <= hi_x:
            vx, cx = -vx, min(max(cx, lo_x), hi_x)
        if not lo_y <= cy <= hi_y:
            vy, cy = -vy, min(max(cy, lo_y), hi_y)
    return len(names)


def main(argv=None):
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("frames")
    a.add_argument("out")
    a.add_argument("--area", type=float, default=0.10)
    a.add_argument("--seed")
    a.add_argument("--still", action="store_true")
    o = a.parse_args(argv)
    if Image is None:
        sys.exit("make_holes.py needs Pillow")
    print(make(o.frames, o.out, o.area, o.seed, o.still), "holes")


if __name__ == "__main__":
    main()
