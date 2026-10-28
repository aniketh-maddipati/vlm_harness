#!/usr/bin/env python3
"""Scores video healing (Remove: a shape taken out and the hole filled) frame by frame. Numbers only.

  heal_score.py --out DIR --holes DIR [--truth DIR] [--ring PX] [--report heal.json] [--quiet]

DIR folders hold one image per frame, named by frame number (`000123.png` or `.jpg`; `120.png` and
`000120.png` are the same frame). --out is the healed video, --holes the hole masks (8-bit, >= 128 is
in the hole), --truth the clean frames when they exist (RORD's before/after pairs, or DAVIS frames
with made-up holes from make_holes.py). Frames are compared at the truth's (or the holes') size.

With truth, inside the hole's box grown by --ring pixels:
  psnr        dB against the truth in the hole (the pixels that were filled)
  ssim        structural similarity on the hole's box (grey, 7×7 Gaussian window)
  psnr_frame  dB on the whole frame (a fill must also leave the rest alone)
Always (no truth needed), the things a viewer sees on a real clip:
  flicker     mean change of the fill between consecutive frames, in the hole, over the same change
              in the ring of pixels just outside it (1 = as steady as its surroundings; healing that
              boils or swims scores well above 1)
  seam        mean gradient across the hole's edge over the mean gradient in the ring (1 = no seam)
  leak        mean change outside the grown hole against the original (--src, the clip before
              healing): a patch must not touch the rest of the frame
Per run: the means over frames, and the worst 10 % (p90 of flicker and seam, p10 of psnr and ssim).
"""
import argparse, json, math, os, re, sys

import numpy as np

try:
    from PIL import Image
except ImportError:
    Image = None

FRAME = re.compile(r"^(\d+)\.(png|jpe?g)$", re.IGNORECASE)


def frames(folder):
    out = {}
    if folder and os.path.isdir(folder):
        for name in os.listdir(folder):
            m = FRAME.match(name)
            if m:
                out[int(m.group(1))] = os.path.join(folder, name)
    return out


def load_rgb(path, size=None):
    im = Image.open(path).convert("RGB")
    if size and im.size != size:
        im = im.resize(size, Image.BILINEAR)
    return np.asarray(im, dtype=np.float64)


def load_hole(path, size=None):
    im = Image.open(path).convert("L")
    if size and im.size != size:
        im = im.resize(size, Image.NEAREST)
    return np.asarray(im) >= 128


def grey(rgb):
    return rgb @ np.array([0.299, 0.587, 0.114])


def dilate(m, r):
    if r <= 0:
        return m.copy()
    out = m.copy()
    h, w = m.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            ys, yd = (slice(dy, h), slice(0, h - dy)) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
            xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
            out[yd, xd] |= m[ys, xs]
    return out


def box(m, grow, shape):
    ys, xs = np.nonzero(m)
    if not len(ys):
        return None
    h, w = shape
    return max(0, ys.min() - grow), min(h, ys.max() + grow + 1), max(0, xs.min() - grow), min(w, xs.max() + grow + 1)


def psnr(a, b, m=None):
    d = (a - b) ** 2
    if m is not None:
        if not m.any():
            return None
        d = d[m]
    mse = float(d.mean())
    return 99.0 if mse <= 1e-10 else 10 * math.log10(255.0 ** 2 / mse)


def _gauss(sigma=1.5, r=3):
    k = np.exp(-(np.arange(-r, r + 1) ** 2) / (2 * sigma * sigma))
    return k / k.sum()


def _blur(x, k):
    r = len(k) // 2
    p = np.pad(x, r, mode="reflect")
    y = sum(k[i] * p[:, i:i + x.shape[1]] for i in range(len(k)))
    return sum(k[i] * y[i:i + x.shape[0], :] for i in range(len(k)))


def ssim(a, b):
    """Mean SSIM of two grey images (Wang et al. 2004: 7×7 Gaussian σ 1.5, K1 .01, K2 .03, L 255)."""
    if min(a.shape) < 7:
        return None
    k, c1, c2 = _gauss(), (0.01 * 255) ** 2, (0.03 * 255) ** 2
    ma, mb = _blur(a, k), _blur(b, k)
    va, vb, cov = _blur(a * a, k) - ma * ma, _blur(b * b, k) - mb * mb, _blur(a * b, k) - ma * mb
    s = ((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
    return float(s.mean())


def grad(g):
    gy, gx = np.zeros_like(g), np.zeros_like(g)
    gy[1:-1] = (g[2:] - g[:-2]) / 2
    gx[:, 1:-1] = (g[:, 2:] - g[:, :-2]) / 2
    return np.hypot(gx, gy)


def percentile(v, q):
    v = [x for x in v if x is not None]
    return float(np.percentile(v, q)) if v else None


def mean(v):
    v = [x for x in v if x is not None]
    return float(np.mean(v)) if v else None


def score(out_dir, holes_dir, truth_dir=None, src_dir=None, ring=8):
    O, H, T, S = frames(out_dir), frames(holes_dir), frames(truth_dir), frames(src_dir)
    common = sorted(set(O) & set(H))
    rep = {"frames": len(common), "missing": len(set(H) - set(O)), "per_frame": []}
    prev = None
    for n in common:
        hole0 = Image.open(H[n])
        size = Image.open(T[n]).size if n in T else hole0.size
        out, hole = load_rgb(O[n], size), load_hole(H[n], size)
        grown = dilate(hole, ring)
        band = grown & ~hole
        f = {"frame": n, "hole": float(hole.mean())}
        g = grey(out)
        gr = grad(g)
        # the band across the hole's edge: a pixel either side of it (in the hole next to the outside, or outside next to the hole)
        edge = dilate(hole, 1) & dilate(~hole, 1) if hole.any() else hole
        f["seam"] = (float(gr[edge].mean()) / max(1e-6, float(gr[band].mean()))) if edge.any() and band.any() else None
        if n in T:
            tr = load_rgb(T[n], size)
            f["psnr"] = psnr(out, tr, hole)
            f["psnr_frame"] = psnr(out, tr)
            b = box(hole, ring, hole.shape)
            f["ssim"] = ssim(g[b[0]:b[1], b[2]:b[3]], grey(tr)[b[0]:b[1], b[2]:b[3]]) if b else None
        if n in S:
            sr = load_rgb(S[n], size)
            outside = ~grown
            f["leak"] = float(np.abs(out - sr)[outside].mean()) if outside.any() else None
        if prev is not None and prev[0] == n - 1:
            pg, ph = prev[1], prev[2]
            both, around = hole & ph, band & ~ph
            if both.any() and around.any():
                f["flicker"] = float(np.abs(g - pg)[both].mean()) / max(1.0, float(np.abs(g - pg)[around].mean()))
        prev = (n, g, hole)
        rep["per_frame"].append(f)
    pf = rep["per_frame"]
    for k in ("psnr", "psnr_frame", "ssim", "flicker", "seam", "leak", "hole"):
        rep[k] = mean([f.get(k) for f in pf])
    rep["psnr_p10"] = percentile([f.get("psnr") for f in pf], 10)
    rep["ssim_p10"] = percentile([f.get("ssim") for f in pf], 10)
    rep["flicker_p90"] = percentile([f.get("flicker") for f in pf], 90)
    rep["seam_p90"] = percentile([f.get("seam") for f in pf], 90)
    return rep


def main(argv=None):
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("--out", required=True)
    a.add_argument("--holes", required=True)
    a.add_argument("--truth")
    a.add_argument("--src")
    a.add_argument("--ring", type=int, default=8)
    a.add_argument("--report")
    a.add_argument("--quiet", action="store_true")
    o = a.parse_args(argv)
    if Image is None:
        sys.exit("heal_score.py needs Pillow")
    rep = score(o.out, o.holes, o.truth, o.src, o.ring)
    if o.report:
        with open(o.report, "w") as f:
            json.dump(rep, f, indent=1)
    if not o.quiet:
        fmt = lambda v, s=".3f": "—" if v is None else format(v, s)
        print(f"frames {rep['frames']} (missing {rep['missing']}) · psnr {fmt(rep['psnr'], '.2f')} dB (p10 {fmt(rep['psnr_p10'], '.2f')})"
              f" · ssim {fmt(rep['ssim'])} · flicker {fmt(rep['flicker'], '.2f')} (p90 {fmt(rep['flicker_p90'], '.2f')})"
              f" · seam {fmt(rep['seam'], '.2f')} · leak {fmt(rep['leak'], '.2f')}")
    return rep


if __name__ == "__main__":
    main()
