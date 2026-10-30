#!/usr/bin/env python3
"""The "better" scores (docs/editing/RAPIDRAW-PARITY.md): what a slider does to a photo, judged on
its own terms rather than against Lightroom. Runs on any sweep: Lumina renders, Lightroom exports,
RapidRAW exports.

    python3 Tools/parity/better.py <folder> [<folder> …] [--px 1024] [--json out.json] [--md out.md] [--label name]
    python3 Tools/parity/better.py --refs refs.json …        # a refs.json from import_refs.py / lr_cc_sweep.py ingest

A folder holds one sweep per photo, named like the Lightroom sweep: `<stem>__base.<ext>` and
`<stem>__<Slider>__<value>.<ext>` (a `.lumina` before the extension is allowed, as parity.py writes
its renders). Every slider image is compared with its photo's base. Scores, per photo, then the
median over photos:

- **isolation**: median ΔE2000 outside the slider's own luma band (base L*), e.g. what Highlights
  does to pixels below L* 35. Lower is better. Sliders without a band (Exposure, Saturation, …)
  report none. `leak` is that number over the median ΔE inside the band.
- **hue drift**: Oklab hue change on the base's skin, sky and neutral pixels, in degrees,
  chroma-weighted, signed mean and median |Δh|; for neutrals the chroma added (Oklab C × 100).
  White balance moves hue on purpose: reported, flagged `intended`.
- **step evenness**: the mean ΔE between neighbouring positions per slider unit (the base sits at
  0 for sliders whose rest is 0). `evenness` = coefficient of variation of those per-unit steps:
  0 = every step looks the same size.
- **added clipping**: % of pixels clipped (any channel ≥ 254.5/255, or all ≤ 0.5/255) in the slider
  image minus the base, per position; `clipMid` = the worst over positions short of the slider's
  end, which is clipping the user didn't ask for yet.
- **flicker** (video, `flicker()`): frame-to-frame ΔE2000 on regions the source clip holds still;
  for Skim's video prompts. Not part of a stills sweep run.
- **halo**: edge overshoot. The change in L* is split into a global tone curve (median change per
  base-L* bin over the whole frame) and a residual; on a ring 1–6 px around strong edges the residual
  signed by the side of the edge (brighter or darker than the local mean) is the overshoot, in L*.
  A global curve scores ~0; an unsharp-mask-like local contrast scores > 0.

Numbers only; photo content stays in ~/LuminaEvidence. numpy (+ Pillow / tifffile to read files),
no Core Image: runs on Linux (tests/test_better.py).
"""
import argparse
import glob
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402

# The slider's own band on the base's L*: (inside, outside). Outside is kept clear of the inside
# by a margin, so a soft mask edge isn't counted as a leak.
BANDS = {
    "Highlights": (lambda L: L > 60, lambda L: L < 35),
    "Shadows": (lambda L: L < 40, lambda L: L > 65),
    "Whites": (lambda L: L > 75, lambda L: L < 50),
    "Blacks": (lambda L: L < 25, lambda L: L > 50),
}
INTENDED_HUE = {"Temperature", "Tint"}
# Where each slider rests, for step evenness (absolute-value sliders such as Temperature have no
# shared rest; their steps are measured between positions only).
REST = {"Temperature": None, "Tint": None}
# Each slider's end (|value|); clipping before it is clipping the user didn't ask for yet.
RANGE = {"Exposure": 5.0, "Temperature": None, "Tint": 150.0}
NAME = re.compile(r"^(?P<stem>.+?)__(?P<slider>[A-Za-z]+)__(?P<value>-?\d+(?:\.\d+)?)(?:\.(?:lumina|skim))?\.(?:tif|tiff|jpg|jpeg|png)$", re.I)
BASE = re.compile(r"^(?P<stem>.+?)__base(?:\.(?:lumina|skim))?\.(?:tif|tiff|jpg|jpeg|png)$", re.I)

# ---- colour ----------------------------------------------------------------------------------

BRADFORD = np.array([[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]])
XYZ_TO_LMS = np.array([[0.8189330101, 0.3618667424, -0.1288597137],
                       [0.0329845436, 0.9293118715, 0.0361456387],
                       [0.0482003018, 0.2643662691, 0.6338517070]])
LMS_TO_OKLAB = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                         [1.9779984951, -2.4285922050, 0.4505937099],
                         [0.0259040371, 0.7827717662, -0.8086757660]])


def _d50_to_d65():
    s = BRADFORD @ delta_e.D50
    d = BRADFORD @ delta_e.D65
    return np.linalg.inv(BRADFORD) @ np.diag(d / s) @ BRADFORD


def oklab(rgb01, space):
    xyz = delta_e.to_xyz(rgb01, space)
    if space == "prophoto":
        xyz = xyz @ _d50_to_d65().T
    lms = np.cbrt(np.maximum(xyz @ XYZ_TO_LMS.T, 0.0))
    return lms @ LMS_TO_OKLAB.T


def masks(lab):
    """skin / sky / neutral on the base, from CIELAB (the skin gate is delta_e's)."""
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    C = np.hypot(a, b)
    h = np.degrees(np.arctan2(b, a)) % 360
    rows = np.linspace(0, 1, lab.shape[0])[:, None] * np.ones((1, lab.shape[1]))
    return {
        "skin": (h >= 15) & (h <= 55) & (C >= 8) & (C <= 45) & (L >= 30) & (L <= 85),
        "sky": (h >= 200) & (h <= 290) & (C >= 6) & (L >= 40) & (rows < 0.6),
        "neutral": (C < 4) & (L > 15) & (L < 95),
    }


# ---- the scores ------------------------------------------------------------------------------

def _f(x):
    return None if x is None or not np.isfinite(x) else float(x)


def isolation(lab0, lab1, slider):
    band = BANDS.get(slider)
    if band is None:
        return None
    inside, outside = band[0](lab0[..., 0]), band[1](lab0[..., 0])
    if outside.sum() < 50 or inside.sum() < 50:
        return None
    de = delta_e.delta_e2000(lab0, lab1)
    out, ins = float(np.median(de[outside])), float(np.median(de[inside]))
    return {"outside": out, "inside": ins, "leak": out / ins if ins > 1e-6 else None}


def hue_drift(ok0, ok1, m):
    """Per mask: signed chroma-weighted mean Δh and median |Δh| (degrees); neutral: chroma added."""
    out = {}
    C0, C1 = np.hypot(ok0[..., 1], ok0[..., 2]), np.hypot(ok1[..., 1], ok1[..., 2])
    h0, h1 = np.arctan2(ok0[..., 2], ok0[..., 1]), np.arctan2(ok1[..., 2], ok1[..., 1])
    dh = np.degrees(np.angle(np.exp(1j * (h1 - h0))))
    for k in ("skin", "sky"):
        sel = m[k] & (C0 > 0.02) & (C1 > 0.02)
        if sel.sum() < 50:
            out[k] = None
            continue
        w = np.minimum(C0[sel], C1[sel])
        out[k] = {"mean": float(np.sum(w * dh[sel]) / np.sum(w)), "abs": float(np.median(np.abs(dh[sel]))), "n": int(sel.sum())}
    sel = m["neutral"]
    out["neutral"] = None if sel.sum() < 50 else {"chroma": float(np.median(C1[sel] - C0[sel]) * 100), "n": int(sel.sum())}
    return out


def clipped(rgb01):
    hi = np.any(rgb01 >= 254.5 / 255, axis=-1)
    lo = np.all(rgb01 <= 0.5 / 255, axis=-1)
    return float(hi.mean() * 100), float(lo.mean() * 100)


def _box(x, r):
    """Mean over a (2r+1)² box, edges replicated (integral image)."""
    p = np.pad(x, r + 1, mode="edge")
    c = p.cumsum(0).cumsum(1)
    k = 2 * r + 1
    s = c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]
    return s[:x.shape[0], :x.shape[1]] / (k * k)


def _dilate(mask, r):
    return _box(mask.astype(float), r) > 1e-9


def halo(L0, L1, ring=(1, 6), edge_pct=97.0, bins=32):
    """Edge overshoot in L*: the residual after a global per-L* curve, signed by the side of the edge,
    averaged on a ring around the strongest edges. None when the photo has no usable edges."""
    gy, gx = np.gradient(L0)
    g = np.hypot(gx, gy)
    thr = np.percentile(g, edge_pct)
    if thr < 2.0:
        return None
    edges = g >= thr
    near = _dilate(edges, ring[1]) & ~_dilate(edges, ring[0] - 1 if ring[0] > 1 else 0)
    near &= ~edges
    if near.sum() < 50:
        return None
    dL = L1 - L0
    idx = np.clip((L0 / 100 * bins).astype(int), 0, bins - 1)
    far = ~_dilate(edges, ring[1] * 2)
    curve = np.zeros(bins)
    for i in range(bins):
        sel = (idx == i) & far
        if sel.sum() < 20:
            sel = idx == i
        curve[i] = np.median(dL[sel]) if sel.any() else 0.0
    resid = dL - curve[idx]
    side = np.sign(L0 - _box(L0, ring[1] * 2))
    s = (side * resid)[near & (side != 0)]
    if s.size < 50:
        return None
    return {"overshoot": float(np.mean(s)), "p95": float(np.percentile(np.abs(s), 95))}


def evenness(points):
    """points: [(value, lab)] sorted by value. Per-unit ΔE of each neighbouring step and their CV."""
    steps = []
    for (v0, a), (v1, b) in zip(points, points[1:]):
        dv = abs(v1 - v0)
        if dv <= 0:
            continue
        steps.append({"from": v0, "to": v1, "perUnit": float(np.mean(delta_e.delta_e2000(a, b)) / dv)})
    if len(steps) < 2:
        return {"steps": steps, "cv": None}
    pu = np.array([s["perUnit"] for s in steps])
    return {"steps": steps, "cv": float(pu.std() / pu.mean()) if pu.mean() > 1e-9 else None}


def flicker(frames, source=None, space="srgb", static=1.0):
    """Video: frame-to-frame ΔE2000 on static regions. frames: rendered frames in order, (H, W, 3)
    0…1. A pixel is static between two frames when the source frames (the clip before the look)
    differ there by less than `static` ΔE; without sources, every pixel counts. A look that holds
    still on a still scene scores ~0; one that pumps or shimmers scores its jump. Returns the
    median and p95 over frame pairs of each pair's mean ΔE on static pixels, and the worst pair."""
    if len(frames) < 2:
        return None
    labs = [delta_e.to_lab(f, space) for f in frames]
    srcs = [delta_e.to_lab(f, space) for f in source] if source is not None else None
    per = []
    for i in range(len(labs) - 1):
        de = delta_e.delta_e2000(labs[i], labs[i + 1])
        sel = np.ones(de.shape, bool) if srcs is None else delta_e.delta_e2000(srcs[i], srcs[i + 1]) < static
        if sel.sum() < 50:
            continue
        per.append(float(np.mean(de[sel])))
    if not per:
        return None
    v = np.array(per)
    return {"pairs": len(per), "median": float(np.median(v)), "p95": float(np.percentile(v, 95)), "worst": int(np.argmax(v))}


def score_sweep(base, positions, slider, space="srgb"):
    """base: (H, W, 3) 0…1; positions: {value: image}. One photo's scores for one slider."""
    lab0, ok0 = delta_e.to_lab(base, space), oklab(base, space)
    m = masks(lab0)
    clip0 = clipped(base)
    per = {}
    labs = {}
    for v in sorted(positions):
        img = positions[v]
        lab1 = delta_e.to_lab(img, space)
        labs[v] = lab1
        c1 = clipped(img)
        per[v] = {
            "isolation": isolation(lab0, lab1, slider),
            "hue": hue_drift(ok0, oklab(img, space), m),
            "clipAdded": {"high": c1[0] - clip0[0], "low": c1[1] - clip0[1]},
            "halo": halo(lab0[..., 0], lab1[..., 0]),
        }
    rest = REST.get(slider, 0.0)
    pts = sorted(labs.items())
    if rest is not None and rest not in labs:
        pts = sorted(pts + [(rest, lab0)], key=lambda t: t[0])
    end = RANGE.get(slider, 100.0)
    mids = [] if end is None else [v for v in per if abs(v) < end]
    clip_mid = max((per[v]["clipAdded"]["high"] + per[v]["clipAdded"]["low"] for v in mids), default=None)
    return {"slider": slider, "positions": per, "even": evenness(pts), "clipMid": clip_mid,
            "intendedHue": slider in INTENDED_HUE}


# ---- summary over photos ---------------------------------------------------------------------

def _med(xs):
    xs = [x for x in xs if x is not None and np.isfinite(x)]
    return float(np.median(xs)) if xs else None


def summarise(per_photo):
    """per_photo: {stem: {slider: score_sweep(...)}} → {slider: medians over photos}."""
    out = {}
    sliders = sorted({s for d in per_photo.values() for s in d})
    for s in sliders:
        runs = [d[s] for d in per_photo.values() if s in d]
        pos = [p for r in runs for p in r["positions"].values()]
        g = lambda f: _med([f(p) for p in pos])  # noqa: E731

        def hue(k, field):
            return g(lambda p: (p["hue"].get(k) or {}).get(field))
        out[s] = {
            "photos": len(runs),
            "isolation": g(lambda p: (p["isolation"] or {}).get("outside")),
            "leak": g(lambda p: (p["isolation"] or {}).get("leak")),
            "hueSkin": hue("skin", "abs"), "hueSky": hue("sky", "abs"),
            "hueSkinMean": hue("skin", "mean"), "hueSkyMean": hue("sky", "mean"),
            "neutralChroma": hue("neutral", "chroma"),
            "evenness": _med([r["even"]["cv"] for r in runs]),
            "clipMid": _med([r["clipMid"] for r in runs]),
            "clipEnd": g(lambda p: p["clipAdded"]["high"] + p["clipAdded"]["low"]),
            "halo": g(lambda p: (p["halo"] or {}).get("overshoot")),
            "intendedHue": runs[0]["intendedHue"],
        }
    return out


def to_markdown(summary, label=""):
    f = lambda x, d=2: "–" if x is None else f"{x:.{d}f}"  # noqa: E731
    L = [f"# Better scores{(' — ' + label) if label else ''}\n",
         "Medians over photos and positions. isolation = ΔE outside the slider's luma band (lower is better), leak = outside / inside; "
         "hue = median |Δh| in Oklab degrees (skin / sky), neutral = chroma added ×100; evenness = CV of ΔE per unit step (0 = even); "
         "clip = % pixels newly clipped (mid = short of the slider's end); halo = edge overshoot in L* (0 = none).\n",
         "| slider | photos | isolation | leak | hue skin | hue sky | neutral C | evenness | clip mid | clip all | halo |",
         "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for s, v in summary.items():
        star = " (wb: hue intended)" if v["intendedHue"] else ""
        L.append(f"| {s}{star} | {v['photos']} | {f(v['isolation'])} | {f(v['leak'])} | {f(v['hueSkin'], 1)} | {f(v['hueSky'], 1)} | "
                 f"{f(v['neutralChroma'])} | {f(v['evenness'])} | {f(v['clipMid'])} | {f(v['clipEnd'])} | {f(v['halo'])} |")
    return "\n".join(L) + "\n"


# ---- files -----------------------------------------------------------------------------------

def target_shape(shape, px):
    """The size every image of one photo is compared at: the base's, long edge at most px."""
    h, w = shape[:2]
    if not px or max(h, w) <= px:
        return (h, w)
    k = px / max(h, w)
    return (max(1, round(h * k)), max(1, round(w * k)))


def resize_to(img, shape):
    """img at shape's size, area-averaged (box filter) so every image of a sweep goes through the
    same filter. Exports of one sweep can differ in size (Lightroom's base vs its singles), never
    in aspect."""
    h, w = shape[:2]
    ih, iw = img.shape[:2]
    if (ih, iw) == (h, w):
        return img
    if abs(iw / ih - w / h) > 0.02 * (w / h):
        raise ValueError(f"aspect mismatch: {iw}×{ih} vs {w}×{h}")
    from PIL import Image
    out = np.zeros((h, w, 3))
    for c in range(3):
        out[..., c] = np.asarray(Image.fromarray(img[..., c].astype(np.float32)).resize((w, h), Image.BOX))
    return out


def index_folders(folders):
    """{stem: {"base": path, "sweeps": {slider: {value: path}}}}"""
    idx = {}
    for d in folders:
        for p in sorted(glob.glob(os.path.join(os.path.expanduser(d), "*"))):
            n = os.path.basename(p)
            if n.startswith("._"):
                continue
            m = BASE.match(n)
            if m:
                idx.setdefault(m["stem"], {"base": None, "sweeps": {}})["base"] = p
                continue
            m = NAME.match(n)
            if m:
                e = idx.setdefault(m["stem"], {"base": None, "sweeps": {}})
                e["sweeps"].setdefault(m["slider"], {})[float(m["value"])] = p
    return idx


def index_refs(path):
    d = json.load(open(os.path.expanduser(path)))
    idx = {}
    for r in d["refs"]:
        e = idx.setdefault(r["stem"], {"base": None, "sweeps": {}})
        if r["kind"] == "base":
            e["base"] = r["path"]
        elif r["kind"] == "single":
            e["sweeps"].setdefault(r["slider"], {})[float(r["value"])] = r["path"]
    return idx


def run(idx, px=1024, space=None):
    per_photo = {}
    for stem, e in sorted(idx.items()):
        if not e["base"] or not e["sweeps"]:
            continue
        base, sp = delta_e.read_rgb01(e["base"])
        sp = space or sp or "srgb"
        shape = target_shape(base.shape, px)
        base = resize_to(delta_e.median3(base), shape)
        per_photo[stem] = {}
        for slider, pos in e["sweeps"].items():
            imgs = {}
            for v, p in pos.items():
                img, _ = delta_e.read_rgb01(p)
                img = resize_to(delta_e.median3(img), shape)
                imgs[v] = img
            per_photo[stem][slider] = score_sweep(base, imgs, slider, sp)
    return per_photo


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("folders", nargs="*")
    ap.add_argument("--refs", action="append", default=[], help="refs.json (import_refs.py / lr_cc_sweep.py ingest)")
    ap.add_argument("--px", type=int, default=1024)
    ap.add_argument("--space", choices=["srgb", "prophoto"])
    ap.add_argument("--json")
    ap.add_argument("--md")
    ap.add_argument("--label", default="")
    a = ap.parse_args(argv)
    idx = index_folders(a.folders)
    for r in a.refs:
        for k, v in index_refs(r).items():
            e = idx.setdefault(k, {"base": None, "sweeps": {}})
            e["base"] = e["base"] or v["base"]
            for s, pos in v["sweeps"].items():
                e["sweeps"].setdefault(s, {}).update(pos)
    per_photo = run(idx, a.px, a.space)
    summary = summarise(per_photo)
    md = to_markdown(summary, a.label)
    if a.json:
        json.dump({"label": a.label, "px": a.px, "summary": summary}, open(a.json, "w"), indent=1)
    if a.md:
        open(a.md, "w").write(md)
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
