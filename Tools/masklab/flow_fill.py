#!/usr/bin/env python3
"""Flow fill: the first half of "flow + LaMa", the healer that borrows the real background from nearby frames.

    python flow_fill.py FRAMES_DIR HOLES_DIR OUT_DIR [--reach 5]

For each frame t and each neighbour t±1 … t±reach (nearest first), the optical flow from t to the neighbour
(OpenCV Farneback on grey frames) is completed inside t's hole by inpainting the flow field from around it (the hole
has no flow of its own), and each hole pixel takes the neighbour's pixel there when that pixel is not in the
neighbour's own hole. What no neighbour shows stays a hole. Writes OUT_DIR/frames/<n:05d>.png (the frame, filled where
it could be) and OUT_DIR/left/<n:05d>.png (white where it couldn't), for LaMa to finish:

    iopaint run --model lama --image OUT_DIR/frames --mask OUT_DIR/left --output HEALED

The hole is grown by 2 px first, so the object's own edge isn't propagated. Measures only; not in the app.
"""
import argparse, os, re, sys, time

import cv2
import numpy as np

FRAME = re.compile(r"^(\d+)\.(png|jpe?g)$", re.IGNORECASE)


def frames(d):
    return {int(m.group(1)): os.path.join(d, f) for f in os.listdir(d) if (m := FRAME.match(f))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("holes")
    ap.add_argument("out")
    ap.add_argument("--reach", type=int, default=5)
    a = ap.parse_args()
    F, H = frames(a.frames), frames(a.holes)
    ns = sorted(F)
    img = {n: cv2.imread(F[n]) for n in ns}
    h, w = img[ns[0]].shape[:2]
    k = np.ones((5, 5), np.uint8)
    hole = {}
    for n in ns:
        m = cv2.imread(H[n], cv2.IMREAD_GRAYSCALE) if n in H else np.zeros((h, w), np.uint8)
        m = cv2.resize(m, (w, h), interpolation=cv2.INTER_NEAREST) >= 128
        hole[n] = cv2.dilate(m.astype(np.uint8), k) > 0
    grey = {n: cv2.cvtColor(img[n], cv2.COLOR_BGR2GRAY) for n in ns}
    os.makedirs(os.path.join(a.out, "frames"), exist_ok=True)
    os.makedirs(os.path.join(a.out, "left"), exist_ok=True)
    gx, gy = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    t0, filled_share = time.perf_counter(), []
    for i, n in enumerate(ns):
        out, left = img[n].copy(), hole[n].copy()
        if left.any():
            order = sorted((j for j in range(max(0, i - a.reach), min(len(ns), i + a.reach + 1)) if j != i), key=lambda j: abs(j - i))
            for j in order:
                if not left.any():
                    break
                m = ns[j]
                flow = cv2.calcOpticalFlowFarneback(grey[n], grey[m], None, 0.5, 4, 21, 3, 5, 1.1, 0)
                # complete the flow inside the hole from around it (both channels), so the hole moves with its surroundings
                hm = hole[n].astype(np.uint8)
                for c in range(2):
                    ch = flow[..., c]
                    lo, hi = float(ch.min()), float(ch.max())
                    if hi - lo < 1e-6:
                        continue
                    u8 = ((ch - lo) / (hi - lo) * 255).astype(np.uint8)
                    flow[..., c] = cv2.inpaint(u8, hm, 5, cv2.INPAINT_TELEA).astype(np.float32) / 255 * (hi - lo) + lo
                mx, my = gx + flow[..., 0], gy + flow[..., 1]
                warped = cv2.remap(img[m], mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
                theirs = cv2.remap(hole[m].astype(np.uint8), mx, my, cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=1) > 0
                inside = (mx >= 0) & (mx <= w - 1) & (my >= 0) & (my <= h - 1)
                take = left & ~theirs & inside
                out[take] = warped[take]
                left &= ~take
        filled_share.append(1 - left.sum() / max(1, hole[n].sum()))
        cv2.imwrite(os.path.join(a.out, "frames", f"{n:05d}.png"), out)
        cv2.imwrite(os.path.join(a.out, "left", f"{n:05d}.png"), (left * 255).astype(np.uint8))
    dt = time.perf_counter() - t0
    print(f"{os.path.basename(os.path.normpath(a.frames))}: {len(ns)} frames, {np.mean(filled_share):.0%} of the hole from other frames, "
          f"{len(ns) / dt:.1f} fps")


if __name__ == "__main__":
    sys.exit(main())
