#!/usr/bin/env python3
"""RapidRAW vs Lightroom on the stills sweeps (prompt 25, step 1–2): the same ΔE2000 numbers Lumina
and Skim are scored on, so a RapidRAW form is adopted (clean-room, cited) only where it measurably wins.
Measures only. RapidRAW is AGPL: this reads its *exports*; nothing of its code enters the repo.

    python3 Tools/parity/rapidraw_parity.py --refs ~/LuminaEvidence/parity/sweep/refs.json --raws ~/LuminaEvidence/parity/sweep/raw
                                            [--refs …/sweep2/refs.json --raws …/sweep2/raw] [--tonemapper basic|agx]
                                            [--app /Applications/RapidRAW.app] [--px 1024] [--report dir] [--label name]

Renders go through RapidRAW's own headless export (1.6.4: `RapidRAW export <src> --output <dir>
--adjustments <json>`, which overrides every sidecar with one look), one launch per look over a folder
holding every sweep RAW, so a look costs one launch for all photos. Each render is shrunk to --px and
cached (`<cache>/<look hash>/<stem>.npy`), so a rerun or a second report is free.

Mapping (written to the report):
- Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance, Saturation → the RapidRAW key of the
  same name at Lightroom's value × k, one k per slider fitted at Lightroom's ±50 (Exposure ±1) positions
  on median ΔE. This compares forms, not unit choices (prompt 25: "fit only the scale").
- Temperature / Tint: Lightroom's are absolute, RapidRAW's are relative multipliers (shader
  `apply_white_balance`), so each position is scored at the RapidRAW value (−100…100, step 10) that
  matches best on that photo, as skim_parity.py does. This flatters RapidRAW.
- Two scores per position: `raw`, RapidRAW's render as it is, and `matched`, after a per-photo colour
  map fitted from RapidRAW's base to Lightroom's base (3 × 3 + per-channel cubic, least squares) and
  applied unchanged to every slider render. `matched` takes away the difference in default look
  (RapidRAW's base is not Adobe Color) and leaves the slider's own shape.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import better  # noqa: E402
import delta_e  # noqa: E402
from skim_parity import pooled, wb_delta  # noqa: E402

KEYS = {"Exposure": "exposure", "Contrast": "contrast", "Highlights": "highlights", "Shadows": "shadows",
        "Whites": "whites", "Blacks": "blacks", "Vibrance": "vibrance", "Saturation": "saturation"}
WB = {"Temperature": "temperature", "Tint": "tint"}
RANGE = {"exposure": 5.0}                     # RapidRAW's UI ranges; everything else ±100
K_GRID = {"exposure": [0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.4]}
K_DEFAULT = [0.25, 0.4, 0.6, 0.8, 1.0, 1.25, 1.5, 2.0]
WB_SEARCH = list(range(-100, 101, 10))
FIT_AT = {"exposure": 1.0}                    # |Lightroom value| the scale is fitted at; else 50


def expand(p):
    return os.path.abspath(os.path.expanduser(p))


class Renderer:
    def __init__(self, app, raws, cache, tonemapper, px):
        self.exe = os.path.join(expand(app), "Contents", "MacOS", "RapidRAW")
        if not os.access(self.exe, os.X_OK):
            raise SystemExit(f"RapidRAW not found at {self.exe}")
        self.raws, self.cache, self.tm, self.px = raws, cache, tonemapper, px
        self.launches = 0

    def look(self, adj):
        a = dict(adj, toneMapper=self.tm)
        h = hashlib.sha1(json.dumps(a, sort_keys=True).encode()).hexdigest()[:16]
        return a, os.path.join(self.cache, h)

    def render(self, adj, stems):
        """{stem: (H, W, 3) 0…1 at px} for one look, every stem in one launch."""
        a, d = self.look(adj)
        if not all(os.path.exists(os.path.join(d, s + ".npy")) for s in stems):
            os.makedirs(d, exist_ok=True)
            with tempfile.TemporaryDirectory() as t:
                src, out = os.path.join(t, "src"), os.path.join(t, "out")
                os.makedirs(src)
                for s in stems:
                    os.symlink(self.raws[s], os.path.join(src, os.path.basename(self.raws[s])))
                adj_path = os.path.join(t, "adj.json")
                json.dump(a, open(adj_path, "w"))
                r = subprocess.run([self.exe, "export", src, "--output", out, "--format", "jpeg", "--quality", "98",
                                    "--adjustments", adj_path], capture_output=True, text=True, timeout=900)
                self.launches += 1
                files = {re.sub(r"_edited$", "", os.path.splitext(f)[0].split(".")[0]): os.path.join(dp, f)   # 1.6.9+: <stem>_edited.jpeg
                         for dp, _, fs in os.walk(out) for f in fs if not f.startswith("._")}
                for s in stems:
                    if s not in files:
                        raise SystemExit(f"RapidRAW wrote no {s} (exit {r.returncode}): {r.stdout[-400:]} {r.stderr[-400:]}")
                    img, _ = delta_e.read_rgb01(files[s])
                    shape = better.target_shape(img.shape, self.px)
                    np.save(os.path.join(d, s + ".npy"), better.resize_to(img, shape).astype(np.float32))
            json.dump(a, open(os.path.join(d, "look.json"), "w"))
        return {s: np.load(os.path.join(d, s + ".npy")).astype(np.float64) for s in stems}


def fit_map(src, dst):
    """Per-photo colour map src → dst: per-channel cubic, then 3 × 3. Fitted on a pixel sample."""
    rng = np.random.default_rng(0)
    x, y = src.reshape(-1, 3), dst.reshape(-1, 3)
    i = rng.choice(len(x), min(len(x), 60000), replace=False)
    x, y = x[i], y[i]
    polys = [np.polyfit(x[:, c], y[:, c], 3) for c in range(3)]
    xp = np.stack([np.polyval(polys[c], x[:, c]) for c in range(3)], 1)
    m, *_ = np.linalg.lstsq(np.c_[xp, np.ones(len(xp))], y, rcond=None)

    def apply(img):
        f = img.reshape(-1, 3)
        p = np.stack([np.polyval(polys[c], f[:, c]) for c in range(3)], 1)
        with np.errstate(all="ignore"):   # Accelerate's matmul raises spurious FP flags; the result is finite
            return np.clip(np.c_[p, np.ones(len(p))] @ m, 0, 1).reshape(img.shape)
    return apply


def de_median(ref, img):
    return float(np.median(delta_e.delta_e2000(delta_e.to_lab(ref, "srgb"), delta_e.to_lab(img, "srgb"))))


def rr_value(key, lr_value, k):
    lim = RANGE.get(key, 100.0)
    return float(np.clip(lr_value * k, -lim, lim))


def run(refs_paths, raw_dirs, rend):
    refs = []
    for p in refs_paths:
        refs += [r for r in json.load(open(expand(p)))["refs"] if not r.get("error")]
    raws = {}
    for d in raw_dirs:
        for f in os.listdir(expand(d)):
            if f.lower().endswith(".arw") and not f.startswith("._"):
                raws[os.path.splitext(f)[0]] = os.path.join(expand(d), f)
    rend.raws = raws
    by_stem = {}
    for r in refs:
        if r["stem"] in raws:
            by_stem.setdefault(r["stem"], []).append(r)
    stems = sorted(s for s, rs in by_stem.items() if any(r["kind"] == "base" for r in rs))
    if not stems:
        raise SystemExit("no sweep photo has both a base export and a RAW")

    lr = {}
    def lr_img(r, shape):
        if r["id"] not in lr:
            lr[r["id"]] = better.resize_to(delta_e.read_rgb01(r["path"])[0], shape)
        return lr[r["id"]]

    rr_base = rend.render({}, stems)
    shapes = {s: rr_base[s].shape for s in stems}
    base_ref = {s: next(r for r in by_stem[s] if r["kind"] == "base") for s in stems}
    maps = {s: fit_map(rr_base[s], lr_img(base_ref[s], shapes[s])) for s in stems}
    samples = {"raw": {}, "matched": {}}
    for s in stems:
        for mode, img in (("raw", rr_base[s]), ("matched", maps[s](rr_base[s]))):
            m = delta_e.measure(lr_img(base_ref[s], shapes[s]), img, "srgb", sample=20000)
            samples[mode].setdefault("base", []).append(m["sample"])

    singles = [r for s in stems for r in by_stem[s] if r["kind"] == "single"]
    scale, wb_pick = {}, {}
    # scale per slider, fitted on the matched score at ±FIT_AT
    for slider, key in KEYS.items():
        at = FIT_AT.get(key, 50.0)
        fit_refs = [r for r in singles if r["slider"] == slider and abs(r["value"]) == at]
        if not fit_refs:
            continue
        errs = []
        for k in K_GRID.get(key, K_DEFAULT):
            e = []
            for v in sorted({r["value"] for r in fit_refs}):
                imgs = rend.render({key: rr_value(key, v, k)}, stems)
                e += [de_median(lr_img(r, shapes[r["stem"]]), maps[r["stem"]](imgs[r["stem"]]))
                      for r in fit_refs if r["value"] == v]
            errs.append((float(np.median(e)), k))
        scale[slider] = min(errs)[1]
    # white balance: best RapidRAW value per photo and position
    for slider, key in WB.items():
        wr = [r for r in singles if r["slider"] == slider]
        if not wr:
            continue
        grid = {v: rend.render({key: float(v)}, stems) for v in WB_SEARCH}
        for r in wr:
            errs = [de_median(lr_img(r, shapes[r["stem"]]), maps[r["stem"]](grid[v][r["stem"]])) for v in WB_SEARCH]
            as_shot = r.get("asShot") or {}
            wb_pick.setdefault(slider, []).append({"stem": r["stem"], "value": r["value"],
                                                    "lrDelta": wb_delta(slider, r["value"], as_shot) if as_shot else None,
                                                    "rapidraw": WB_SEARCH[int(np.argmin(errs))]})
    # score every single
    skipped = {}
    for r in singles:
        sl, s = r["slider"], r["stem"]
        if sl in KEYS and sl in scale:
            look = {KEYS[sl]: rr_value(KEYS[sl], r["value"], scale[sl])}
        elif sl in WB and sl in wb_pick:
            look = {WB[sl]: float(next(c["rapidraw"] for c in wb_pick[sl] if c["stem"] == s and c["value"] == r["value"]))}
        else:
            skipped[sl] = skipped.get(sl, 0) + 1
            continue
        img = rend.render(look, stems)[s]
        ref = lr_img(r, shapes[s])
        for mode, im in (("raw", img), ("matched", maps[s](img))):
            m = delta_e.measure(ref, im, "srgb", sample=20000)
            samples[mode].setdefault(sl, []).append(m["sample"])
            samples[mode].setdefault((sl, r["value"]), []).append(m["sample"])
    return samples, scale, wb_pick, skipped, stems


def report(samples, scale, wb_pick, skipped, stems, criteria, label, px, tm, launches):
    c = criteria["singles"]
    L = [f"# RapidRAW vs Lightroom — {label}\n",
         f"{dt.datetime.now():%Y-%m-%d %H:%M} · RapidRAW 1.6.4 headless export, tone mapper `{tm}` · {len(stems)} photos · "
         f"compare {px} px · ΔE2000 · criteria median ≤ {c['median']}, p95 ≤ {c['p95']} · {launches} RapidRAW launches.\n",
         "`raw`: RapidRAW's render as it is. `matched`: after a per-photo colour map from RapidRAW's base to Lightroom's base, "
         "the same map on every slider render (the slider's shape, without the default-look difference).\n",
         "| slider | k (RapidRAW = LR × k) | pairs | raw median / p95 | matched median / p95 | pass (matched) |",
         "|---|---:|---:|---:|---:|:---:|"]
    sliders = sorted(k for k in samples["matched"] if isinstance(k, str))
    for k in sliders:
        r, m = pooled(samples["raw"][k]), pooled(samples["matched"][k])
        ok = m["median"] <= c["median"] and m["p95"] <= c["p95"]
        ks = f"{scale[k]:g}" if k in scale else ("best per photo" if k in WB else "–")
        L.append(f"| {k} | {ks} | {m['pairs']} | {r['median']:.2f} / {r['p95']:.2f} | {m['median']:.2f} / {m['p95']:.2f} | "
                 f"{'' if k == 'base' else ('✓' if ok else '✗')} |")
    L += ["", "## By position (matched median / p95)\n", "| slider | positions |", "|---|---|"]
    tup = [x for x in samples["matched"] if isinstance(x, tuple)]
    for k in sliders:
        pos = sorted(v for (s, v) in tup if s == k)
        if pos:
            L.append(f"| {k} | " + " · ".join(f"{v:g}: {pooled(samples['matched'][(k, v)])['median']:.2f} / "
                                              f"{pooled(samples['matched'][(k, v)])['p95']:.2f}" for v in pos) + " |")
    if wb_pick:
        L += ["", "## White balance: best RapidRAW value per position (median over photos)\n",
              "| slider | Lightroom | RapidRAW |", "|---|---:|---:|"]
        for k, cs in wb_pick.items():
            for v in sorted({x["value"] for x in cs}):
                L.append(f"| {k} | {v:g} | {np.median([x['rapidraw'] for x in cs if x['value'] == v]):+.0f} |")
    if skipped:
        L.append("\nNot mapped (positions skipped): " + ", ".join(f"{k} ({n})" for k, n in sorted(skipped.items())))
    return "\n".join(L) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--refs", action="append", required=True)
    ap.add_argument("--raws", action="append", required=True)
    ap.add_argument("--app", default="/Applications/RapidRAW.app")
    ap.add_argument("--tonemapper", default="basic", choices=["basic", "agx"])
    ap.add_argument("--px", type=int, default=1024)
    ap.add_argument("--cache", default="~/LuminaEvidence/parity/rapidraw/cache")
    ap.add_argument("--report")
    ap.add_argument("--label", default="")
    a = ap.parse_args(argv)
    criteria = json.load(open(os.path.join(HERE, "criteria.json")))
    rend = Renderer(a.app, {}, expand(os.path.join(a.cache, a.tonemapper)), a.tonemapper, a.px)
    samples, scale, wb_pick, skipped, stems = run(a.refs, a.raws, rend)
    label = a.label or f"rapidraw-{a.tonemapper}"
    md = report(samples, scale, wb_pick, skipped, stems, criteria, label, a.px, a.tonemapper, rend.launches)
    if a.report:
        os.makedirs(expand(a.report), exist_ok=True)
        open(os.path.join(expand(a.report), "report.md"), "w").write(md)
        summ = {mode: {str(k): pooled(v) for k, v in s.items()} for mode, s in samples.items()}
        json.dump({"label": label, "px": a.px, "tonemapper": a.tonemapper, "scale": scale, "wb": wb_pick,
                   "skipped": skipped, "scores": summ}, open(os.path.join(expand(a.report), "summary.json"), "w"), indent=1)
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
