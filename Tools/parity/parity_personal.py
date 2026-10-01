#!/usr/bin/env python3
"""Parity against your own Lightroom edits: `make parity-personal`.

    python3 Tools/parity/parity_personal.py [--exports <JPEG folder> --raws <RAW folder>]   (remembered after the first run)
                                            [--root $LUMINA_PERSONAL_SET] [--rules path] [--decoder 9]
                                            [--ablate] [--force-render] [--workers N] [--compare-px 1024] [--label name]

The Lightroom Classic sweep (parity.py) needs a catalog; this needs only exports. One run:
  1. import   import_lr_edits.py: XMP → settings, look strings, buckets, refs.json (cached as-shot)
  2. render   one `lumina-render batch` for every edit (and with --ablate, the same look without
              each slider in turn); developed RAWs cached on disk across runs (`--cache`), renders
              skipped when look, size, rules and binary are unchanged
  3. ΔE       both images at a 1024 px long edge (area average), ΔE2000 as delta_e.py measures it,
              in parallel (--workers, default half the cores up to 6)
  4. report   per bucket (as-shot = the decoder / default-render gap, basic-only, unsupported-
              features), mean ΔL*/Δa*/Δb*, error by L*, per-slider evidence (ablation Δ with
              --ablate, rank correlation with the slider's magnitude always), alignment check

Everything it writes lives under --root (default ~/LuminaEvidence/parity-personal): refs, renders,
caches, heatmaps and the report with numbers. Nothing goes into the repo: these are someone's
photos and their edits. It measures only; it never touches rules-v1.json (fitting to these edits
is a human ruling).
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402
import lookmath  # noqa: E402

BUCKETS = ["as-shot", "basic-only", "unsupported-features"]
BRIGHTNESS_MATCHED = 2.0  # |mean ΔL*| below which a frame counts as brightness-matched for the ablation column
# look keys an ablation removes, with the value that switches the stage off
ABLATE = {"ev": 0.0, "wb": None, "con": 0.0, "hl": 0.0, "sh": 0.0, "wh": 0.0, "bl": 0.0, "vib": 0.0, "sat": 0.0, "clr": 0.0, "shp": 0.0, "vig": 0.0}
KEY_SLIDER = {"ev": "Exposure", "wb": "WhiteBalance", "con": "Contrast", "hl": "Highlights", "sh": "Shadows", "wh": "Whites", "bl": "Blacks",
              "vib": "Vibrance", "sat": "Saturation", "clr": "Clarity", "shp": "Sharpness", "vig": "PostCropVignette"}


def expand(p):
    return os.path.abspath(os.path.expanduser(p))


def prune_develop_cache(cache_dir, since):
    """Keep only the develops the last render used. The cache is keyed by the rawDevelop
    coefficients, so every rules variant tried leaves a full copy of every developed RAW behind
    (a scan of four lens strengths was 7 GB); lumina-render touches the entries it reads or
    writes, anything older than the run's start goes. Returns the bytes freed."""
    freed = 0
    if not os.path.isdir(cache_dir):
        return 0
    for name in os.listdir(cache_dir):
        path = os.path.join(cache_dir, name)
        try:
            if os.path.isfile(path) and os.path.getmtime(path) < since - 1:
                freed += os.path.getsize(path)
                os.remove(path)
        except OSError:
            pass
    return freed


def prune_heatmaps(report_root, keep):
    """Heatmaps are per-pixel pictures of every frame, per run: keep them for the newest `keep`
    reports only. The reports' numbers (report.md, summary.json) always stay."""
    runs = sorted(d for d in os.listdir(report_root) if os.path.isdir(os.path.join(report_root, d))) if os.path.isdir(report_root) else []
    for d in runs[:-keep] if keep > 0 else runs:
        shutil.rmtree(os.path.join(report_root, d, "heatmaps"), ignore_errors=True)


def personal_root():
    return expand(os.environ.get("LUMINA_PERSONAL_SET", "~/LuminaEvidence/parity-personal"))


# ---- measuring one pair (runs in worker processes) ------------------------------------------------

def resize_to(rgb, size):
    """(H, W, 3) floats → size (w, h) with an area average (Pillow BOX, per channel, float32)."""
    from PIL import Image
    if (rgb.shape[1], rgb.shape[0]) == tuple(size):
        return rgb
    return np.stack([np.asarray(Image.fromarray(rgb[..., c].astype(np.float32)).resize(size, Image.BOX)) for c in range(3)], -1).astype(np.float64)


def compare_size(w, h, long_edge):
    s = long_edge / float(max(w, h))
    return (max(1, int(round(w * s))), max(1, int(round(h * s))))


def shift_estimate(a, b):
    """Global (dy, dx) between two same-size grey images from phase correlation of their
    gradient magnitude, and the peak height (≈1 aligned, low = unrelated or badly misaligned)."""
    def edges(g):
        gy, gx = np.gradient(g)
        return np.hypot(gx, gy)
    ea, eb = edges(a), edges(b)
    A = np.fft.rfft2(ea - ea.mean())
    B = np.fft.rfft2(eb - eb.mean())
    R = A * np.conj(B)
    R /= np.abs(R) + 1e-12
    r = np.fft.irfft2(R, s=ea.shape)
    i = np.unravel_index(int(np.argmax(r)), r.shape)
    dy, dx = [int(v) if v < n // 2 else int(v - n) for v, n in zip(i, r.shape)]
    return dy, dx, float(r.max())


def reference_lab(ref, space):
    return delta_e.to_lab(delta_e.median3(ref), space)


def measure_images(ref, ren, space, sample=4000, seed=0, lab_ref=None):
    """ΔE2000 of two same-size images as delta_e.measure does (3 × 3 median, then Lab), plus the
    mean signed differences render − reference (L*, a*, b*, C*), the centre vs border error and a
    global alignment check. `lab_ref` skips the reference's half when it is cached. Returns
    (numbers, ΔE map, a fixed-size sample of the ΔE values)."""
    if lab_ref is None:
        lab_ref = reference_lab(ref, space)
    lab_ren = delta_e.to_lab(delta_e.median3(ren), space)
    de = delta_e.delta_e2000(lab_ref, lab_ren)
    out = {"all": delta_e.stats(de)}
    for name, mask in delta_e.regions(lab_ref).items():
        out[name] = delta_e.stats(de, mask)
    L = lab_ref[..., 0]
    out["byL"] = [float(np.mean(de[(L >= lo) & (L < lo + 10)])) if np.any((L >= lo) & (L < lo + 10)) else None for lo in range(0, 100, 10)]
    d = lab_ren - lab_ref
    out["dL"], out["da"], out["db"] = (float(np.mean(d[..., i])) for i in range(3))
    out["dC"] = float(np.mean(np.hypot(lab_ren[..., 1], lab_ren[..., 2]) - np.hypot(lab_ref[..., 1], lab_ref[..., 2])))
    out["refL"] = float(np.mean(L))
    h, w = de.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((yy - (h - 1) / 2) / (h / 2), (xx - (w - 1) / 2) / (w / 2)) / np.sqrt(2)
    out["centre"] = delta_e.stats(de, r < 0.4)
    out["border"] = delta_e.stats(de, r > 0.8)
    out["dLborder"] = float(np.mean(d[..., 0][r > 0.8]) - np.mean(d[..., 0][r < 0.4]))
    # mean ΔL* by distance from the centre (fifths of the half diagonal): lens vignetting shows as a fall-off
    out["dLradial"] = [float(np.mean(d[..., 0][(r >= lo) & (r < lo + 0.2)])) if np.any((r >= lo) & (r < lo + 0.2)) else None
                       for lo in (0.0, 0.2, 0.4, 0.6, 0.8)]
    dy, dx, peak = shift_estimate(lab_ref[..., 0], lab_ren[..., 0])
    out["shift"] = {"dy": dy, "dx": dx, "peak": peak}
    flat = de.ravel()
    idx = np.random.default_rng(seed).choice(flat.size, size=min(sample, flat.size), replace=False)
    return out, de, flat[idx].astype(np.float32)


def measure_job(job):
    """One pair from paths: the reference at compare_px long edge, the render resized to exactly
    the reference's size (their aspect ratios must agree within 2 %)."""
    np.seterr(all="ignore")  # numpy's Accelerate matmul raises spurious FP warnings on macOS
    t0 = time.time()
    try:
        space = job.get("space") or "srgb"
        cached = None
        if job.get("refCache"):
            key = hashlib.sha256(f"{os.path.realpath(job['ref'])}|{file_sig(job['ref'])}|{job['comparePx']}|{space}".encode()).hexdigest()[:24]
            cached = os.path.join(job["refCache"], key + ".npy")
        lab_ref = np.load(cached) if cached and os.path.exists(cached) else None
        if lab_ref is None:
            ref, ref_space = delta_e.read_rgb01(job["ref"])
            rh, rw = ref.shape[:2]
            size = compare_size(rw, rh, job["comparePx"])
            ref = resize_to(ref, size)
            lab_ref = reference_lab(ref, space)
            if cached:
                os.makedirs(job["refCache"], exist_ok=True)
                np.save(cached, lab_ref.astype(np.float32))
        else:
            lab_ref = lab_ref.astype(np.float64)
        size = (lab_ref.shape[1], lab_ref.shape[0])
        ren, _ = delta_e.read_rgb01(job["render"])
        nh, nw = ren.shape[:2]
        if abs((nw / nh) / (size[0] / size[1]) - 1) > 0.02:
            raise ValueError(f"aspect mismatch: reference {size[0]}×{size[1]} (at compare size), render {nw}×{nh}")
        ren = resize_to(ren, size)
        m, de, sample = measure_images(None, ren, space, lab_ref=lab_ref)
        if job.get("heatmap"):
            os.makedirs(os.path.dirname(job["heatmap"]), exist_ok=True)
            delta_e.heatmap(de, job["heatmap"])
        m["size"] = list(size)
        m["seconds"] = time.time() - t0
        return {"id": job["id"], "ok": True, "measure": m, "sample": sample}
    except Exception as e:  # a missing render, a broken file
        return {"id": job["id"], "ok": False, "error": str(e), "seconds": time.time() - t0}


# ---- statistics -------------------------------------------------------------------------------------

def pooled(samples):
    if not samples:
        return {"n": 0}
    v = np.concatenate(samples)
    return {"n": len(samples), "median": float(np.median(v)), "p95": float(np.percentile(v, 95)), "mean": float(np.mean(v))}


def ranks(x):
    x = np.asarray(x, dtype=float)
    order = np.argsort(x, kind="mergesort")
    r = np.empty(len(x))
    r[order] = np.arange(len(x))
    for v in np.unique(x):  # average ties
        m = x == v
        if m.sum() > 1:
            r[m] = r[m].mean()
    return r


def spearman(x, y):
    x, y = np.asarray(x, float), np.asarray(y, float)
    if len(x) < 4 or np.all(x == x[0]) or np.all(y == y[0]):
        return None
    return float(np.corrcoef(ranks(x), ranks(y))[0, 1])


def slope(x, y):
    """Least-squares slope of y on x (with intercept) and Pearson r."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    if len(x) < 4 or np.all(x == x[0]):
        return None, None
    b = np.polyfit(x, y, 1)[0]
    return float(b), float(np.corrcoef(x, y)[0, 1])


def slider_value(ref, name):
    s = ref.get("settings", {})
    if name == "WhiteBalance":
        # Lightroom's move away from its as shot, in mired (+ = warmer)
        if "Temperature" not in s or not ref.get("lrAsShot"):
            return 0.0
        return 1e6 / ref["lrAsShot"][0] - 1e6 / float(s["Temperature"])
    default = 40.0 if name == "Sharpness" else 0.0
    return float(s.get(name, default)) - default


def aggregate(frames, ablations):
    """frames: [{ref, measure, sample}] (the full looks). ablations: {id: {key: {measure}}}."""
    out = {"buckets": {}, "all": pooled([f["sample"] for f in frames])}
    for b in BUCKETS + ["unsupported-features:excluding-profile"]:
        if b.endswith("excluding-profile"):
            sel = [f for f in frames if f["ref"]["bucket"] == "unsupported-features" and "profile" not in f["ref"]["features"]]
        else:
            sel = [f for f in frames if f["ref"]["bucket"] == b]
        if not sel:
            continue
        st = pooled([f["sample"] for f in sel])
        med = [f["measure"]["all"]["median"] for f in sel]
        st.update({
            "frameMedian": float(np.median(med)), "frameP95": float(np.median([f["measure"]["all"]["p95"] for f in sel])),
            "dL": float(np.mean([f["measure"]["dL"] for f in sel])), "da": float(np.mean([f["measure"]["da"] for f in sel])),
            "db": float(np.mean([f["measure"]["db"] for f in sel])), "dC": float(np.mean([f["measure"]["dC"] for f in sel])),
            "dLborder": float(np.mean([f["measure"]["dLborder"] for f in sel])),
            "dLradial": [float(np.nanmean([f["measure"]["dLradial"][i] if f["measure"]["dLradial"][i] is not None else np.nan for f in sel]))
                         for i in range(5)],
            "regions": {reg: float(np.median([f["measure"][reg]["median"] for f in sel if f["measure"][reg].get("n")] or [np.nan]))
                        for reg in ("shadows", "midtones", "highlights", "skin", "centre", "border")},
            "byL": [float(np.nanmean([f["measure"]["byL"][i] if f["measure"]["byL"][i] is not None else np.nan for f in sel]))
                    for i in range(10)],
        })
        out["buckets"][b] = st
    lenses = {}
    for f in frames:
        lenses.setdefault(f["ref"].get("lens") or "?", []).append(f)
    out["lenses"] = {k: {"n": len(v), "frameMedian": float(np.median([f["measure"]["all"]["median"] for f in v])),
                         "dLborder": float(np.mean([f["measure"]["dLborder"] for f in v])),
                         "asShotN": sum(f["ref"]["bucket"] == "as-shot" for f in v)} for k, v in sorted(lenses.items())}
    feats = {}
    for f in frames:
        for k in f["ref"]["features"]:
            feats.setdefault(k, []).append(f)
    out["features"] = {k: {"n": len(v), "frameMedian": float(np.median([f["measure"]["all"]["median"] for f in v]))} for k, v in sorted(feats.items())}
    edited = [f for f in frames if f["ref"]["bucket"] != "as-shot"]
    sliders = {}
    for key, name in KEY_SLIDER.items():
        vals = [slider_value(f["ref"], name) for f in edited]
        de = [f["measure"]["all"]["median"] for f in edited]
        dl = [f["measure"]["dL"] for f in edited]
        active = [abs(v) > 1e-9 for v in vals]
        s = {"active": int(sum(active)), "rhoAbsVsDE": spearman(np.abs(vals), de)}
        b, r = slope(vals, dl)
        s["dLperUnit"], s["rDL"] = b, r
        if name == "WhiteBalance":
            b, r = slope(vals, [f["measure"]["db"] for f in edited])
            s["dbPerMired"], s["rDb"] = b, r
        if name in ("Vibrance", "Saturation"):
            b, r = slope(vals, [f["measure"]["dC"] for f in edited])
            s["dCperUnit"], s["rDC"] = b, r
        abl = [ablations[f["ref"]["id"]][key] for f in edited if key in ablations.get(f["ref"]["id"], {})]
        if abl:
            full = {f["ref"]["id"]: f["measure"] for f in edited}
            deltas = [full[a["id"]]["all"]["median"] - a["measure"]["all"]["median"] for a in abl]
            # The same, only on frames whose full render already matches Lightroom's mean brightness
            # (|ΔL*| < 2): a darkening slider can't look good or bad just because the whole render is too dark.
            matched = [full[a["id"]]["all"]["median"] - a["measure"]["all"]["median"] for a in abl if abs(full[a["id"]]["dL"]) < BRIGHTNESS_MATCHED]
            s["ablation"] = {"n": len(deltas), "medianDelta": float(np.median(deltas)), "meanDelta": float(np.mean(deltas)),
                             "helps": float(np.mean([d < 0 for d in deltas])), "totalDelta": float(np.sum(deltas)),
                             # what the stage itself does to the render's mean L* and C* (full − without)
                             "stageDL": float(np.median([full[a["id"]]["dL"] - a["measure"]["dL"] for a in abl])),
                             "stageDC": float(np.median([full[a["id"]]["dC"] - a["measure"]["dC"] for a in abl])),
                             "matchedN": len(matched), "matchedMedianDelta": float(np.median(matched)) if matched else None,
                             "matchedHelps": float(np.mean([d < 0 for d in matched])) if matched else None}
        sliders[name] = s
    out["sliders"] = sliders
    none = [ablations[f["ref"]["id"]]["none"] for f in edited if "none" in ablations.get(f["ref"]["id"], {})]
    if none:
        full = {f["ref"]["id"]: f["measure"]["all"]["median"] for f in edited}
        deltas = [full[a["id"]] - a["measure"]["all"]["median"] for a in none]
        out["neutral"] = {"n": len(deltas), "medianDelta": float(np.median(deltas)), "helps": float(np.mean([d < 0 for d in deltas])),
                          "neutralFrameMedian": float(np.median([a["measure"]["all"]["median"] for a in none]))}
    shifts = [f for f in frames if abs(f["measure"]["shift"]["dx"]) > 1 or abs(f["measure"]["shift"]["dy"]) > 1]
    out["misaligned"] = [{"id": f["ref"]["id"], **f["measure"]["shift"]} for f in shifts]
    out["worst"] = [{"id": f["ref"]["id"], "bucket": f["ref"]["bucket"], "median": f["measure"]["all"]["median"], "p95": f["measure"]["all"]["p95"],
                     "dL": f["measure"]["dL"], "features": f["ref"]["features"]}
                    for f in sorted(frames, key=lambda f: -f["measure"]["all"]["median"])[:8]]
    return out


# ---- report -----------------------------------------------------------------------------------------

def fmt(x, d=2, signed=False):
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return "–"
    return (f"{x:+.{d}f}" if signed else f"{x:.{d}f}")


def report_md(agg, frames, meta, timing, cal):
    L = [f"# Personal parity — {meta['label']}\n",
         f"{meta['date']} · rules `{meta['rules']}` · {len(frames)} edits of {meta['raws']} RAWs · compare {meta['comparePx']} px long edge · "
         f"space sRGB (Lightroom JPEG exports) · RAW decoder {meta.get('decoder') or 'default'}\n",
         "ΔE2000 per pixel after a 3 × 3 median, pooled with the same number of samples per frame. "
         "`frame median` is the median over frames of each frame's median. ΔL*/Δa*/Δb*/ΔC* are render − Lightroom (mean over frames).\n",
         "## By bucket\n",
         "| bucket | frames | median | p95 | frame median | ΔL* | Δa* | Δb* | ΔC* | shadows | midtones | highlights | skin | border − centre ΔL* |",
         "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for b, s in agg["buckets"].items():
        r = s["regions"]
        L.append(f"| {b} | {s['n']} | {fmt(s['median'])} | {fmt(s['p95'])} | {fmt(s['frameMedian'])} | {fmt(s['dL'], 1, True)} | {fmt(s['da'], 1, True)} | "
                 f"{fmt(s['db'], 1, True)} | {fmt(s['dC'], 1, True)} | {fmt(r['shadows'])} | {fmt(r['midtones'])} | {fmt(r['highlights'])} | {fmt(r['skin'])} | {fmt(s['dLborder'], 1, True)} |")
    a = agg["all"]
    L.append(f"| **all** | {a['n']} | {fmt(a['median'])} | {fmt(a['p95'])} | | | | | | | | | | |\n")
    L.append("Criteria for reference (Tools/parity/criteria.json, written for single-slider sweeps): singles median ≤ 2.0, p95 ≤ 4.0; combos ≤ 3.0 / 5.0.\n")
    L.append("## Mean ΔE by Lightroom L* decile\n")
    L.append("| bucket | " + " | ".join(f"{lo}–{lo + 10}" for lo in range(0, 100, 10)) + " |")
    L.append("|---|" + "---:|" * 10)
    for b, s in agg["buckets"].items():
        L.append(f"| {b} | " + " | ".join(fmt(v, 1) for v in s["byL"]) + " |")
    L.append("")
    L.append("## Mean ΔL* (render − Lightroom) by distance from the centre\n")
    L.append("Fifths of the half diagonal. A fall-off toward the corners that the sliders don't explain is lens vignetting "
             "correction (Lightroom's lens profile is on by default; Lumina has no such stage).\n")
    L.append("| bucket | 0–0.2 | 0.2–0.4 | 0.4–0.6 | 0.6–0.8 | 0.8–1 |")
    L.append("|---|---:|---:|---:|---:|---:|")
    for b, s in agg["buckets"].items():
        L.append(f"| {b} | " + " | ".join(fmt(v, 1, True) for v in s["dLradial"]) + " |")
    L.append("")
    L.append("| lens | frames | as-shot frames | frame median | border − centre ΔL* |")
    L.append("|---|---:|---:|---:|---:|")
    for k, v in agg["lenses"].items():
        L.append(f"| {k} | {v['n']} | {v['asShotN']} | {fmt(v['frameMedian'])} | {fmt(v['dLborder'], 1, True)} |")
    L.append("")
    L.append("## Sliders (edited frames: basic-only + unsupported-features)\n")
    has_abl = any("ablation" in s for s in agg["sliders"].values())
    L.append("`ρ` is the rank correlation of the frame's median ΔE with the slider's magnitude; `ΔL*/unit` is the slope of the frame's "
             "mean ΔL* (render − Lightroom) on the slider's signed value (Exposure per stop, WB per mired of warming, others per slider unit): "
             "a negative slope on a brightening slider means Lumina's stage does less than Lightroom's."
             + (" Ablation Δ = ΔE(full look) − ΔE(look without that slider), per frame, median: negative means the stage moves Lumina "
                "toward Lightroom (helps), positive means the render would be closer without it." if has_abl else "") + "\n")
    if has_abl:
        L.append(f"`stage ΔL*`/`stage ΔC*`: what Lumina's stage itself does to the frame's mean L*/C* (median). `matched`: the ablation "
                 f"Δ only on frames whose full render is within {BRIGHTNESS_MATCHED:g} L* of Lightroom's mean brightness, so a darkening "
                 "slider isn't blamed (or credited) for the whole render being too dark.\n")
    hdr = "| slider | frames active | ρ(|v|, ΔE) | ΔL*/unit | r | other |"
    if has_abl:
        hdr += " ablation Δ median | helps in | Σ Δ | stage ΔL* | stage ΔC* | matched Δ (n) | matched helps |"
    L.append(hdr)
    L.append("|---|---:|---:|---:|---:|---|" + ("---:|---:|---:|---:|---:|---:|---:|" if has_abl else ""))
    for name, s in agg["sliders"].items():
        other = ""
        if s.get("dbPerMired") is not None:
            other = f"Δb*/mired {fmt(s['dbPerMired'], 3, True)} (r {fmt(s['rDb'])})"
        if s.get("dCperUnit") is not None:
            other = f"ΔC*/unit {fmt(s['dCperUnit'], 3, True)} (r {fmt(s['rDC'])})"
        row = f"| {name} | {s['active']} | {fmt(s['rhoAbsVsDE'])} | {fmt(s['dLperUnit'], 3, True)} | {fmt(s['rDL'])} | {other} |"
        if has_abl:
            ab = s.get("ablation")
            row += (f" {fmt(ab['medianDelta'], 2, True)} | {ab['helps'] * 100:.0f} % of {ab['n']} | {fmt(ab['totalDelta'], 1, True)} | "
                    f"{fmt(ab['stageDL'], 2, True)} | {fmt(ab['stageDC'], 2, True)} | {fmt(ab['matchedMedianDelta'], 2, True)} ({ab['matchedN']}) | "
                    + (f"{ab['matchedHelps'] * 100:.0f} %" if ab['matchedHelps'] is not None else "–") + " |"
                    if ab else " – | – | – | – | – | – | – |")
        L.append(row)
    if agg.get("neutral"):
        n = agg["neutral"]
        L.append(f"\nAll sliders at once: the neutral look (crop only) has frame median {fmt(n['neutralFrameMedian'])}; applying the edit's sliders "
                 f"changes each frame's median by {fmt(n['medianDelta'], 2, True)} (median), closer to Lightroom in {n['helps'] * 100:.0f} % of {n['n']} frames.")
    L.append("")
    L.append("## Unsupported features (frames with the feature, their median ΔE)\n")
    for k, v in agg["features"].items():
        L.append(f"- {k}: {v['n']} frames, frame median {fmt(v['frameMedian'])}")
    L.append("")
    if cal and cal.get("n"):
        L.append(f"White balance for non-As-Shot edits: Lightroom's as shot estimated from Apple's with {fmt(cal['mired'], 1, True)} mired "
                 f"(MAD {fmt(cal['miredMAD'], 1)}) and tint {fmt(cal['tint'], 1, True)} (MAD {fmt(cal['tintMAD'], 1)}), from {cal['n']} As Shot exports.\n")
    L.append("## Alignment\n")
    if agg["misaligned"]:
        L.append("Frames whose render is shifted by more than 1 px at the comparison size (phase correlation of gradients):\n")
        for m in agg["misaligned"]:
            L.append(f"- `{m['id']}` dy {m['dy']} dx {m['dx']} (peak {m['peak']:.2f})")
    else:
        L.append("Every render lines up with its reference within 1 px at the comparison size.")
    L.append("")
    L.append("## Worst frames\n")
    for w in agg["worst"]:
        L.append(f"- `{w['id']}` ({w['bucket']}{', ' + ', '.join(w['features']) if w['features'] else ''}) median {fmt(w['median'])}, p95 {fmt(w['p95'])}, ΔL* {fmt(w['dL'], 1, True)}")
    L.append("")
    L.append("## Timing (seconds)\n")
    L.append("| " + " | ".join(timing.keys()) + " |")
    L.append("|" + "---:|" * len(timing))
    L.append("| " + " | ".join(fmt(v, 1) if isinstance(v, float) else str(v) for v in timing.values()) + " |")
    L.append("")
    L.append("## Per frame\n")
    L.append("| id | bucket | median | p95 | ΔL* | Δa* | Δb* | features | look |")
    L.append("|---|---|---:|---:|---:|---:|---:|---|---|")
    for f in sorted(frames, key=lambda f: (BUCKETS.index(f["ref"]["bucket"]), f["ref"]["id"])):
        m = f["measure"]
        L.append(f"| {f['ref']['id']} | {f['ref']['bucket']} | {fmt(m['all']['median'])} | {fmt(m['all']['p95'])} | {fmt(m['dL'], 1, True)} | "
                 f"{fmt(m['da'], 1, True)} | {fmt(m['db'], 1, True)} | {', '.join(f['ref']['features'])} | `{f['ref']['look']}` |")
    return "\n".join(L) + "\n"


# ---- the run ----------------------------------------------------------------------------------------

def file_sig(path):
    st = os.stat(path)
    return f"{st.st_size}:{int(st.st_mtime)}"


def ablation_looks(look_text):
    """(suffix, look text) for the look without each active slider, plus 'none' (every slider off,
    crop and nr kept)."""
    base = lookmath.parse_look(look_text)
    out = []
    for key, off in ABLATE.items():
        if base[key] != off and not (key == "wb" and base[key] is None):
            l2 = dict(base)
            l2[key] = off
            out.append((key, lookmath.format_look(l2)))
    neutral = dict(base)
    neutral.update(ABLATE)
    if out:
        out.append(("none", lookmath.format_look(neutral)))
    return out


def run(a):
    t_start = time.time()
    root = expand(a.root)
    os.makedirs(root, exist_ok=True)
    cfg_path = os.path.join(root, "config.json")
    cfg = json.load(open(cfg_path)) if os.path.exists(cfg_path) else {}
    if a.exports:
        cfg["exports"] = expand(a.exports)
    if a.raws:
        cfg["raws"] = expand(a.raws)
    if not cfg.get("exports") or not cfg.get("raws"):
        print("first run: pass --exports <folder of Lightroom JPEG exports> --raws <folder of their RAWs> "
              "(make parity-personal EXPORTS=… RAWS=…); they're remembered in " + cfg_path, file=sys.stderr)
        return 2
    with open(cfg_path, "w") as f:
        json.dump(cfg, f, indent=1)
    timing = {}

    # 1. import
    import import_lr_edits
    t = time.time()
    refs_doc, _ = import_lr_edits.run(cfg["exports"], cfg["raws"], os.path.join(root, "refs"), a.render_bin, a.compare_px)
    timing["import"] = time.time() - t
    timing["  xmp"] = refs_doc["timing"]["xmpSeconds"]
    timing["  as-shot"] = refs_doc["timing"]["asShotSeconds"]
    refs = [r for r in refs_doc["refs"] if r["kind"] == "edit" and not r.get("error")]
    if a.limit:
        refs = refs[: a.limit]
    if a.bucket:
        refs = [r for r in refs if r["bucket"] == a.bucket]

    # 2. render
    t = time.time()
    render_dir = os.path.join(root, "render")
    os.makedirs(render_dir, exist_ok=True)
    rules_path = expand(a.rules) if a.rules else os.path.join(ROOT, "Lumina", "Sets", "Look", "rules-v1.json")
    stamp_base = hashlib.sha256(open(rules_path, "rb").read()).hexdigest()[:16] + "|" + file_sig(a.render_bin) + f"|{a.decoder or 0}"
    stamps_path = os.path.join(render_dir, "stamps.json")
    stamps = json.load(open(stamps_path)) if os.path.exists(stamps_path) else {}
    jobs, pairs, abl_pairs = [], [], []
    for r in sorted(refs, key=lambda r: (r["raw"], r["id"])):
        looks = [("", r["look"])] + ([("__minus-" + k, lk) for k, lk in ablation_looks(r["look"])] if a.ablate else [])
        for suffix, look in looks:
            out = os.path.join(render_dir, r["id"] + suffix + ".tif")
            stamp = hashlib.sha256(f"{stamp_base}|{look}|{r['renderPx']}".encode()).hexdigest()[:20]
            (pairs if not suffix else abl_pairs).append((r, suffix, out, look))
            if a.force_render or stamps.get(out) != stamp or not os.path.exists(out):
                job = {"image": r["raw"], "look": look, "px": r["renderPx"], "out": out, "space": "srgb"}
                if a.decoder:
                    job["decoder"] = a.decoder
                jobs.append((job, out, stamp))
    lines = []
    if jobs:
        plan = os.path.join(render_dir, "jobs.json")
        with open(plan, "w") as f:
            json.dump([j for j, _, _ in jobs], f)
        develop_cache = os.path.join(root, "cache", "develop")
        cmd = [a.render_bin, "batch", plan, "--cache", develop_cache] + (["--rules", rules_path] if a.rules else [])
        if a.no_develop_cache:
            cmd.append("--no-cache")
        print(f"rendering {len(jobs)} looks …", file=sys.stderr)
        render_started = time.time()
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode == 0 and not a.keep_cache:
            freed = prune_develop_cache(develop_cache, render_started)
            if freed:
                print(f"develop cache: dropped {freed / 1e9:.1f} GB of entries this run did not use", file=sys.stderr)
        for line in p.stdout.splitlines():
            try:
                lines.append(json.loads(line))
            except ValueError:
                pass
        ok = {l["out"] for l in lines if l.get("ok")}
        for _, out, stamp in jobs:
            if out in ok:
                stamps[out] = stamp
            else:
                stamps.pop(out, None)
        bad = [l for l in lines if not l.get("ok")]
        if bad or p.returncode not in (0, 1):
            print(f"{len(bad)} renders failed; first: {bad[0].get('error') if bad else p.stderr[-400:]}", file=sys.stderr)
        with open(stamps_path, "w") as f:
            json.dump(stamps, f, indent=0, sort_keys=True)
    timing["render"] = time.time() - t
    timing["  renders"] = len(jobs)
    timing["  decodes"] = sum(1 for l in lines if l.get("develop") == "decode")
    timing["  develop ms (sum)"] = float(sum(l.get("developMs", 0) for l in lines)) / 1000.0
    timing["  look+encode ms (sum)"] = float(sum(l.get("renderMs", 0) for l in lines)) / 1000.0

    # 3. ΔE
    t = time.time()
    date = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    label = a.label or ("all" + (f"-raw{a.decoder}" if a.decoder else ""))
    evidence = os.path.join(root, "report", f"{date}-{label}")
    heat = os.path.join(evidence, "heatmaps")
    mjobs = [{"id": r["id"] + suffix, "ref": r["path"], "render": out, "comparePx": a.compare_px, "space": r.get("space") or "srgb",
              "heatmap": os.path.join(heat, r["id"] + ".de.png") if not suffix else None, "refCache": os.path.join(root, "cache", "ref-lab")}
             for r, suffix, out, _ in pairs + abl_pairs]
    workers = a.workers or max(1, min(6, (os.cpu_count() or 2) // 2))
    with ProcessPoolExecutor(max_workers=workers) as ex:
        results = {res["id"]: res for res in ex.map(measure_job, mjobs, chunksize=2)}
    timing["ΔE"] = time.time() - t
    timing["  pairs"] = len(mjobs)
    timing["  workers"] = workers
    failed = [r for r in results.values() if not r["ok"]]
    for f in failed[:10]:
        print(f"{f['id']}: {f['error']}", file=sys.stderr)

    # 4. report
    t = time.time()
    frames = [{"ref": r, "measure": results[r["id"]]["measure"], "sample": results[r["id"]]["sample"]}
              for r, _, _, _ in pairs if results.get(r["id"], {}).get("ok")]
    abls = {}
    for r, suffix, _, _ in abl_pairs:
        res = results.get(r["id"] + suffix)
        if res and res["ok"]:
            abls.setdefault(r["id"], {})[suffix[len("__minus-"):]] = {"id": r["id"], "measure": res["measure"]}
    if not frames:
        print("nothing measured", file=sys.stderr)
        return 2
    agg = aggregate(frames, abls)
    timing["report"] = time.time() - t
    timing["total"] = time.time() - t_start
    meta = {"label": label, "date": date, "rules": os.path.relpath(rules_path, ROOT) if rules_path.startswith(ROOT) else rules_path,
            "raws": len({r["raw"] for r in refs}), "comparePx": a.compare_px, "decoder": a.decoder, "ablate": a.ablate,
            "skipped": refs_doc.get("skipped"), "failed": [{"id": f["id"], "error": f["error"]} for f in failed]}
    os.makedirs(evidence, exist_ok=True)
    md = report_md(agg, frames, meta, timing, refs_doc.get("wbCalibration"))
    with open(os.path.join(evidence, "report.md"), "w") as f:
        f.write(md)
    summary = {"meta": meta, "timing": timing, "aggregate": agg, "wbCalibration": refs_doc.get("wbCalibration"),
               "frames": [{"id": fr["ref"]["id"], "bucket": fr["ref"]["bucket"], "features": fr["ref"]["features"], "minor": fr["ref"]["minor"],
                           "look": fr["ref"]["look"], "settings": fr["ref"]["settings"],
                           **{k: fr["measure"][k] for k in ("all", "shadows", "midtones", "highlights", "skin", "centre", "border", "byL", "dL", "da", "db", "dC", "shift")}}
                          for fr in frames],
               "ablations": {i: {k: {**v["measure"]["all"], **{x: v["measure"][x] for x in ("dL", "da", "db", "dC")}} for k, v in d.items()}
                             for i, d in abls.items()}}
    with open(os.path.join(evidence, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, sort_keys=True, default=float)
    prune_heatmaps(os.path.join(root, "report"), a.keep_heatmaps)
    with open(os.path.join(root, "report", "latest.json"), "w") as f:
        json.dump({"report": os.path.join(evidence, "report.md"), "date": date, "label": label}, f, indent=1)
    head = md.split("## Mean ΔE by")[0]
    print(head)
    print("timing: " + " · ".join(f"{k.strip()} {fmt(v, 1) if isinstance(v, float) else v}" for k, v in timing.items()))
    print(f"report → {os.path.join(evidence, 'report.md')}")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exports", help="folder of Lightroom-exported JPEGs (remembered in <root>/config.json)")
    ap.add_argument("--raws", help="folder of the RAWs they came from (remembered)")
    ap.add_argument("--root", default=personal_root(), help="evidence folder (default $LUMINA_PERSONAL_SET or ~/LuminaEvidence/parity-personal)")
    ap.add_argument("--rules", help="rules file (default Lumina/Sets/Look/rules-v1.json)")
    ap.add_argument("--render-bin", default=os.path.join(HERE, "lumina-render", ".build", "release", "lumina-render"))
    ap.add_argument("--decoder", type=int)
    ap.add_argument("--compare-px", type=int, default=1024)
    ap.add_argument("--workers", type=int)
    ap.add_argument("--ablate", action="store_true", help="also render each look without each of its sliders (per-stage evidence; ~6× the renders)")
    ap.add_argument("--force-render", action="store_true", help="render even when look, size, rules and binary are unchanged")
    ap.add_argument("--no-develop-cache", action="store_true", help="decode every RAW again (timing the cold path)")
    ap.add_argument("--keep-cache", action="store_true", help="keep develop-cache entries this run did not use (other rules variants)")
    ap.add_argument("--keep-heatmaps", type=int, default=2, help="reports whose heatmaps are kept (newest first); the numbers always stay")
    ap.add_argument("--bucket", choices=BUCKETS)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--label")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
