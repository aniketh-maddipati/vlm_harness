#!/usr/bin/env python3
"""Skim's look vs Lightroom on the stills sweeps: how far Skim's simpler display-referred maths
(the page's LOOK-BEGIN block, run in Node by skim_look.mjs) is from Lightroom, slider by slider,
next to the fitted stills maths (parity.py). Measures only; never edits Skim.

    python3 Tools/parity/skim_parity.py --refs ~/LuminaEvidence/parity/sweep/refs.json [--refs …/sweep2/refs.json]
                                        [--px 1024] [--out ~/LuminaEvidence/parity/skim] [--label name] [--report dir]

Input is Lightroom's own base export of each photo (sRGB, Adobe Color, every slider at 0): Skim
works on display-referred frames, so the base export stands in for a frame. Each sweep position
becomes a Skim look:

- Exposure → ev (stops); Contrast, Highlights, Shadows, Whites, Blacks, Vibrance, Saturation → the
  same key and value (both ±100).
- Temperature / Tint: Lightroom's are absolute (Kelvin, tint) and Skim's are relative ±100 with no
  unit, so each position is scored at the Skim value (−100…100, step 5) that matches Lightroom best
  on that photo; the chosen values are reported. This flatters Skim: it is the best its shape can do.
- Combos with Temperature or Tint use, per photo, the line through the chosen singles (Skim value
  against Lightroom's mired / tint change); combos are otherwise mapped key by key.
- No Skim equivalent: Clarity, Sharpness, Texture, Dehaze, and anything outside the keys above.

Renders (16-bit TIFF, `<stem>__<Slider>__<value>.skim.tif` + `<stem>__base.skim.tif`) go to --out so
better.py can score them; numbers to --report.
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import better  # noqa: E402
import delta_e  # noqa: E402

KEYS = {"Exposure": "ev", "Contrast": "con", "Highlights": "hl", "Shadows": "sh", "Whites": "wh", "Blacks": "bl",
        "Vibrance": "vib", "Saturation": "sat"}
WB = {"Temperature": "temp", "Tint": "tint"}
SEARCH = list(range(-100, 101, 5))


def expand(p):
    return os.path.abspath(os.path.expanduser(p))


def wb_delta(slider, value, as_shot):
    """Lightroom's move from as-shot: mired change for Temperature (positive = warmer), tint change."""
    if slider == "Temperature":
        t0 = float(as_shot.get("Temperature", 5500))
        return 1e6 / t0 - 1e6 / float(value)
    return float(value) - float(as_shot.get("Tint", 0))


def skim_render(base, looks, node="node"):
    """base (H, W, 3) 0…1 → [image per look] through skim_look.mjs."""
    h, w = base.shape[:2]
    with tempfile.TemporaryDirectory() as d:
        base.astype(np.float32).tofile(os.path.join(d, "in.f32"))
        job = {"width": w, "height": h, "input": "in.f32", "looks": [{"look": L, "out": f"o{i}.f32"} for i, L in enumerate(looks)]}
        json.dump(job, open(os.path.join(d, "job.json"), "w"))
        subprocess.run([node, os.path.join(HERE, "skim_look.mjs"), os.path.join(d, "job.json")], check=True, capture_output=True)
        return [np.fromfile(os.path.join(d, f"o{i}.f32"), dtype=np.float32).reshape(h, w, 3).astype(np.float64) for i in range(len(looks))]


def de_median(ref, img):
    return float(np.median(delta_e.delta_e2000(delta_e.to_lab(ref, "srgb"), delta_e.to_lab(img, "srgb"))))


def write_tif(path, img):
    import tifffile
    tifffile.imwrite(path, (np.clip(img, 0, 1) * 65535 + 0.5).astype(np.uint16), photometric="rgb")


def pooled(samples):
    if not samples:
        return {"pairs": 0}
    v = np.concatenate(samples)
    return {"pairs": len(samples), "median": float(np.median(v)), "p95": float(np.percentile(v, 95)), "mean": float(np.mean(v))}


def run(refs_paths, px, out_dir, node="node"):
    refs = []
    for p in refs_paths:
        refs += [r for r in json.load(open(expand(p)))["refs"] if not r.get("error")]
    by_stem = {}
    for r in refs:
        by_stem.setdefault(r["stem"], []).append(r)
    os.makedirs(out_dir, exist_ok=True)
    samples, chosen, skipped = {}, {}, {}
    for stem, rs in sorted(by_stem.items()):
        base_ref = next((r for r in rs if r["kind"] == "base"), None)
        if not base_ref:
            continue
        raw, space = delta_e.read_rgb01(base_ref["path"])
        if (space or "srgb") != "srgb":
            raise SystemExit(f"{base_ref['path']}: Skim takes display sRGB; this export is {space}")
        shape = better.target_shape(raw.shape, px)
        base = better.resize_to(raw, shape)
        write_tif(os.path.join(out_dir, f"{stem}__base.skim.tif"), base)
        as_shot = next((r.get("asShot") for r in rs if r.get("asShot")), {}) or {}
        # white balance singles first: search the Skim value that matches best
        line = {}
        for r in rs:
            if r["kind"] != "single" or r["slider"] not in WB:
                continue
            ref = better.resize_to(delta_e.read_rgb01(r["path"])[0], shape)
            outs = skim_render(base, [{WB[r["slider"]]: v} for v in SEARCH], node)
            errs = [de_median(ref, o) for o in outs]
            v = SEARCH[int(np.argmin(errs))]
            chosen.setdefault(r["slider"], []).append({"stem": stem, "value": r["value"], "lrDelta": wb_delta(r["slider"], r["value"], as_shot), "skim": v})
            line.setdefault(r["slider"], []).append((wb_delta(r["slider"], r["value"], as_shot), v))
        slope = {k: float(np.polyfit([a for a, _ in pts], [b for _, b in pts], 1)[0]) if len(pts) >= 2 else None for k, pts in line.items()}
        jobs = []
        for r in rs:
            if r["kind"] == "base":
                continue
            look, missing = {}, []
            for k, v in r["settings"].items():
                if k in KEYS:
                    look[KEYS[k]] = float(v)
                elif k in WB:
                    if r["kind"] == "single":
                        look[WB[k]] = next(c["skim"] for c in chosen[k] if c["stem"] == stem and c["value"] == r["value"])
                    elif slope.get(k) is not None:
                        look[WB[k]] = float(np.clip(slope[k] * wb_delta(k, v, as_shot), -100, 100))
                    else:
                        missing.append(k)
                elif float(v) != 0:
                    missing.append(k)
            if missing:
                for k in missing:
                    skipped[k] = skipped.get(k, 0) + 1
                continue
            jobs.append((r, look))
        outs = skim_render(base, [L for _, L in jobs], node)
        for (r, _), img in zip(jobs, outs):
            ref = better.resize_to(delta_e.read_rgb01(r["path"])[0], shape)
            m = delta_e.measure(ref, img, "srgb", sample=20000)
            key = r["slider"] if r["kind"] == "single" else "combo"
            samples.setdefault(key, []).append(m["sample"])
            if r["kind"] == "single":
                samples.setdefault((key, r["value"]), []).append(m["sample"])
                write_tif(os.path.join(out_dir, f"{stem}__{r['slider']}__{r['value']:g}.skim.tif"), img)
    return samples, chosen, skipped


def report(samples, chosen, skipped, criteria, label, px):
    c = criteria["singles"]
    L = [f"# Skim's look vs Lightroom — {label}\n",
         f"{dt.datetime.now():%Y-%m-%d %H:%M} · Skim `LOOK-BEGIN` block (design/handoff/lumina-skim/Lumina Skim v3.dc.html) on Lightroom's base export · "
         f"compare {px} px · ΔE2000 after a 3 × 3 median · criteria median ≤ {c['median']}, p95 ≤ {c['p95']} (combos ≤ {criteria['combos']['median']} / {criteria['combos']['p95']}).\n",
         "Temperature / Tint: scored at the best-matching Skim value per photo and position (see below), the most Skim's shape can do.\n",
         "| slider | pairs | median | p95 | mean | pass |", "|---|---:|---:|---:|---:|:---:|"]
    sliders = [k for k in samples if isinstance(k, str) and k not in ("base", "combo")]
    for k in sorted(sliders) + [k for k in ("combo",) if k in samples]:
        s = pooled(samples[k])
        lim = criteria["combos"] if k == "combo" else c
        ok = s["median"] <= lim["median"] and s["p95"] <= lim["p95"]
        L.append(f"| {k} | {s['pairs']} | {s['median']:.2f} | {s['p95']:.2f} | {s['mean']:.2f} | {'✓' if ok else '✗'} |")
    L.append("")
    L.append("## By position (median / p95)\n")
    L.append("| slider | positions |")
    L.append("|---|---|")
    for k in sorted(sliders):
        pos = sorted(v for (s, v) in [x for x in samples if isinstance(x, tuple)] if s == k)
        L.append(f"| {k} | " + " · ".join(f"{v:g}: {pooled(samples[(k, v)])['median']:.2f} / {pooled(samples[(k, v)])['p95']:.2f}" for v in pos) + " |")
    L.append("")
    if chosen:
        L.append("## White balance: best Skim value per position\n")
        L.append("| slider | Lightroom | Lightroom move (mired / tint) | Skim value (median over photos) |")
        L.append("|---|---:|---:|---:|")
        for k, cs in chosen.items():
            for v in sorted({x["value"] for x in cs}):
                sel = [x for x in cs if x["value"] == v]
                L.append(f"| {k} | {v:g} | {np.median([x['lrDelta'] for x in sel]):+.0f} | {np.median([x['skim'] for x in sel]):+.0f} |")
        L.append("")
    if skipped:
        L.append("No Skim equivalent (positions skipped): " + ", ".join(f"{k} ({n})" for k, n in sorted(skipped.items())) + "\n")
    return "\n".join(L) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--refs", action="append", required=True)
    ap.add_argument("--px", type=int, default=1024)
    ap.add_argument("--out", default="~/LuminaEvidence/parity/skim")
    ap.add_argument("--report")
    ap.add_argument("--label", default="skim")
    ap.add_argument("--node", default="node")
    a = ap.parse_args(argv)
    criteria = json.load(open(os.path.join(HERE, "criteria.json")))
    samples, chosen, skipped = run(a.refs, a.px, expand(a.out), a.node)
    md = report(samples, chosen, skipped, criteria, a.label, a.px)
    if a.report:
        os.makedirs(expand(a.report), exist_ok=True)
        open(os.path.join(expand(a.report), "report.md"), "w").write(md)
        summ = {str(k): pooled(v) for k, v in samples.items()}
        json.dump({"label": a.label, "px": a.px, "sliders": summ, "wb": chosen, "skipped": skipped},
                  open(os.path.join(expand(a.report), "summary.json"), "w"), indent=1)
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
