#!/usr/bin/env python3
"""Which photos each Lightroom sweep (lr_cc_sweep.py, sweeps 4–13) is applied to.

    python3 Tools/parity/sweep_photos.py [--out ~/LuminaEvidence/parity/sweeps/photos]
        → <out>/sweepNN.txt (sweep 5: sweep05-<hue>.txt and sweep05-bw.txt), one RAW name a line,
          <out>/sweepNN/ with a link to each RAW (Lightroom ▸ Add Photos takes the folder), and
          <out>/photos.json (every pick with its score, and every photo's measures).

The pools are the Death Valley 156 and the portraits set, read through their Lightroom base exports
(`<pool>/base-refs/<stem>__base.jpg`, Adobe Color with every slider at 0) and their RAW links
(`<pool>/raw/<stem>.ARW`). The picks follow the feature prompts in docs/editing/prompts:

  4  Texture / Clarity / Dehaze   40 Death Valley photos spread over fine detail
  5  HSL                          per hue, the 4 photos with the most of it (≥ 2 % of the frame, or
                                  ≥ 0.1 % for a hue the pools barely have); B&W: the 6 most varied in hue
  6  colour grading               15 Death Valley spread over brightness + 5 portraits (skin)
  7  parametric curve             20 Death Valley spread over brightness
  8  sharpening                   the 8 most detailed Death Valley photos + the 2 most detailed portraits
  9  noise reduction              none: the ISO ladder the owner shoots (SWEEP9-ISO-LADDER.md)
  10 lens CA / distortion         the 20 with the most straight lines in both directions
  11 vignette                     30 from both pools spread over brightness
  12 grain                        the 10 flattest, closest to mid grey
  13 masks                        Sky: 30 Death Valley photos with sky over ≥ 30 % of the top third, spread
                                  over brightness; Subject: 30 portraits spread over brightness

A photo whose base export carries a crop, masks or healing is left out: a Lightroom CC preset
resets none of those, so every sweep export of it would carry them too (3 Death Valley photos' sweep-1
refs do). Deterministic: the same pools give the same lists. Measures only; nothing here is fitted.
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lr_cc_sweep  # noqa: E402

POOLS = {"dv": "~/LuminaEvidence/parity/dv-tone", "portraits": "~/LuminaEvidence/parity/portraits"}
OUT = "~/LuminaEvidence/parity/sweeps/photos"
# Lightroom's eight HSL bands (centre hue, degrees).
BANDS = [("Red", 0), ("Orange", 30), ("Yellow", 60), ("Green", 120), ("Aqua", 180), ("Blue", 225), ("Purple", 270), ("Magenta", 315)]
SIDE = 384


def measures(rgb):
    """Numbers the picks use, from an sRGB image as floats 0…1 (h × w × 3)."""
    rgb = np.asarray(rgb, dtype=np.float64)
    y = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    lap = np.abs(4 * y[1:-1, 1:-1] - y[:-2, 1:-1] - y[2:, 1:-1] - y[1:-1, :-2] - y[1:-1, 2:])
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    chroma = mx - mn
    sat = np.where(mx > 0, chroma / np.maximum(mx, 1e-9), 0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    c = np.maximum(chroma, 1e-9)
    hue = np.where(mx == r, ((g - b) / c) % 6, np.where(mx == g, (b - r) / c + 2, (r - g) / c + 4)) * 60
    colourful = (sat > 0.25) & (mx > 0.15) & (mx < 0.97) & (chroma > 0.06)
    centres = np.array([c for _, c in BANDS], dtype=np.float64)
    dist = np.abs((hue[..., None] - centres + 180) % 360 - 180)
    band = dist.argmin(axis=-1)
    shares = {name: float((colourful & (band == i)).mean()) for i, (name, _) in enumerate(BANDS)}
    p = np.array(list(shares.values()))
    p = p / p.sum() if p.sum() > 0 else p
    entropy = float(-(p[p > 0] * np.log(p[p > 0])).sum() / np.log(len(BANDS)))
    # Straight lines: strong gradients whose direction is within 4° of horizontal or vertical.
    gx = y[1:-1, 2:] - y[1:-1, :-2]
    gy = y[2:, 1:-1] - y[:-2, 1:-1]
    mag = np.hypot(gx, gy)
    strong = (mag >= np.quantile(mag, 0.9)) & (mag > 1e-6) if mag.size else mag > 0
    ang = np.degrees(np.arctan2(gy, gx)) % 180
    horiz_edges = strong & (np.abs(ang - 90) < 4)          # gradient vertical: a horizontal line
    vert_edges = strong & ((ang < 4) | (ang > 176))         # gradient horizontal: a vertical line
    n = max(int(strong.sum()), 1)
    # Sky: the share of the top third that is smooth and bright (clear blue, haze or cloud).
    third = max(lap.shape[0] // 3, 1)
    top = rgb[1:1 + third, 1:-1]
    sky = (lap[:third] < 0.02) & (top.max(axis=2) > 0.45)
    return {
        "luma": float(y.mean()), "contrast": float(y.std()), "detail": float(lap.mean()),
        "chroma": float(chroma.mean()), "hue": shares, "hueEntropy": entropy,
        "lines": float(2 * min(horiz_edges.sum(), vert_edges.sum()) / n),
        "sky": float(sky.mean()) if sky.size else 0.0,
    }


def load(path):
    from PIL import Image
    with Image.open(path) as im:
        im.draft("RGB", (SIDE, SIDE))
        im = im.convert("RGB")
        im.thumbnail((SIDE, SIDE))
        return np.asarray(im, dtype=np.float64) / 255


def spread(items, key, n):
    """n items evenly spaced along `key` (all of them if there are fewer)."""
    items = sorted(items, key=lambda it: (key(it), it["stem"]))
    if len(items) <= n:
        return items
    idx = sorted({round(i * (len(items) - 1) / (n - 1)) for i in range(n)})
    return [items[i] for i in idx]


def top(items, key, n, reverse=True):
    return sorted(items, key=lambda it: (-key(it) if reverse else key(it), it["stem"]))[:n]


def pick(photos):
    """{list name: [(stem, score)]} from [{stem, pool, …measures}]."""
    dv = [p for p in photos if p["pool"] == "dv"]
    people = [p for p in photos if p["pool"] == "portraits"]
    out = {}

    def put(name, items, score):
        out[name] = [(it["stem"], round(score(it), 4)) for it in items]

    put("sweep04", spread(dv, lambda p: p["detail"], 40), lambda p: p["detail"])
    for hue, _ in BANDS:
        rich = [p for p in photos if p["hue"][hue] >= 0.02]
        if len(rich) < 4:   # a hue the pools barely have: the photos with the most of it, if any at all
            rich = [p for p in photos if p["hue"][hue] >= 0.001]
        put(f"sweep05-{hue.lower()}", top(rich, lambda p, h=hue: p["hue"][h], 4), lambda p, h=hue: p["hue"][h])
    put("sweep05-bw", top(photos, lambda p: p["hueEntropy"], 6), lambda p: p["hueEntropy"])
    put("sweep06", spread(dv, lambda p: p["luma"], 15) + spread(people, lambda p: p["luma"], 5), lambda p: p["luma"])
    put("sweep07", spread(dv, lambda p: p["luma"], 20), lambda p: p["luma"])
    put("sweep08", top(dv, lambda p: p["detail"], 8) + top(people, lambda p: p["detail"], 2), lambda p: p["detail"])
    put("sweep10", top(photos, lambda p: p["lines"], 20), lambda p: p["lines"])
    put("sweep11", spread(photos, lambda p: p["luma"], 30), lambda p: p["luma"])
    d = max((p["detail"] for p in photos), default=1) or 1

    def flat(p):
        return p["detail"] / d + 2 * abs(p["luma"] - 0.45) + p["chroma"]
    put("sweep12", top(photos, flat, 10, reverse=False), flat)
    skies = [p for p in dv if p["sky"] >= 0.3]
    put("sweep13-sky", spread(top(skies, lambda p: p["sky"], 60), lambda p: p["luma"], 30), lambda p: p["sky"])
    put("sweep13-subject", spread(people, lambda p: p["luma"], 30), lambda p: p["luma"])
    return out


def read_pool(name, root):
    root = os.path.expanduser(root)
    base = os.path.join(root, "base-refs")
    out, skipped = [], []
    for n in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        if n.startswith(".") or not n.endswith("__base.jpg"):
            continue
        stem = n[: -len("__base.jpg")]
        crs = lr_cc_sweep.read_xmp(os.path.join(base, n)) or {}
        why = lr_cc_sweep.not_clean(crs)
        if why:
            skipped.append({"stem": stem, "pool": name, "why": why})
            continue
        raw = os.path.join(root, "raw", stem + ".ARW")
        out.append({"stem": stem, "pool": name, "raw": os.path.realpath(raw) if os.path.exists(raw) else None,
                    **measures(load(os.path.join(base, n)))})
    return out, skipped


def write(out, photos, picks, skipped=()):
    os.makedirs(out, exist_ok=True)
    by = {p["stem"]: p for p in photos}
    for name, chosen in picks.items():
        with open(os.path.join(out, name + ".txt"), "w") as f:
            f.write("".join(f"{s}.ARW\n" for s, _ in chosen))
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        for old in os.listdir(d):
            if os.path.islink(os.path.join(d, old)):
                os.remove(os.path.join(d, old))
        for s, _ in chosen:
            if by[s]["raw"]:
                os.symlink(by[s]["raw"], os.path.join(d, s + ".ARW"))
    with open(os.path.join(out, "photos.json"), "w") as f:
        json.dump({"picks": {k: [{"stem": s, "score": v} for s, v in c] for k, c in picks.items()}, "skipped": list(skipped),
                   "photos": photos}, f, indent=1)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=OUT)
    for k, v in POOLS.items():
        ap.add_argument(f"--{k}", default=v, help=f"pool folder with base-refs/ and raw/ (default {v})")
    a = ap.parse_args(argv)
    photos, skipped = [], []
    for k in POOLS:
        pool, skip = read_pool(k, getattr(a, k))
        skipped += skip
        if not pool:
            print(f"no base exports under {os.path.expanduser(getattr(a, k))}/base-refs (is the T7 plugged in?)")
            return 2
        photos += pool
    picks = pick(photos)
    out = os.path.expanduser(a.out)
    write(out, photos, picks, skipped)
    no_raw = sorted(p["stem"] for p in photos if not p["raw"])
    for name, chosen in picks.items():
        print(f"{name}: {len(chosen)} photos")
    if skipped:
        print(f"left out {len(skipped)} photos with a crop, masks or healing: {', '.join(s['stem'] for s in skipped)}")
    if no_raw:
        print(f"no RAW link for {len(no_raw)} photos: {', '.join(no_raw[:10])}")
    print(f"→ {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
