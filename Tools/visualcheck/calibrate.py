#!/usr/bin/env python3
"""Calibrate check.py on pairs with known answers: hit and false-alarm rates, time per pair.

    ~/LuminaEvidence/venv-parity/bin/python Tools/visualcheck/calibrate.py \
        --sources <img> [<img> …] --out ~/LuminaEvidence/visualcheck/calib-<date> [--real <pairs dir>]

Each source photo becomes one A image (sRGB, 1600 px) and B images with a known change:
positives (exposure ±0.3 EV, green / magenta / warm tint, shadows crushed, a blurred patch, a
whole-frame blur, a tile seam) and negatives (identical, JPEG q90 re-encode, a resize round trip).
`--real` adds pairs whose answer is "changed" (e.g. the camera-profile before/after). Scores the
numbers, the model and their OR, writes calibration.json + calibration.md beside the run's report.
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check as C  # noqa: E402

SRC_PX = 1600


def to8(rgb):
    return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))


def lin(e):
    return C.DE.decode_srgb(e)


def enc(x):
    return C.DE.encode_srgb(x)


def ev(rgb, stops):
    return enc(lin(rgb) * 2 ** stops)


def gains(rgb, r, g, b):
    return enc(lin(rgb) * np.array([r, g, b]))


def crush(rgb):
    """Shadows crushed: everything below ~L* 25 pulled toward black (a toe that clips)."""
    t = 0.22
    y = np.where(rgb < t, t * (rgb / t) ** 2.2, rgb)
    return y


def blur_patch(img, frac=0.3):
    w, h = img.size
    box = (int(w * 0.35), int(h * 0.3), int(w * (0.35 + frac)), int(h * (0.3 + frac)))
    out = img.copy()
    out.paste(img.crop(box).filter(ImageFilter.GaussianBlur(2.5)), box[:2])
    return out


def seam(rgb):
    """A tile seam: one 512 px tile developed 4 % brighter (the kind a tiled RAW path makes)."""
    out = rgb.copy()
    h, w = rgb.shape[:2]
    y0, x0 = h // 2 - 256, w // 2 - 256
    out[y0:y0 + 512, x0:x0 + 512] = enc(lin(rgb[y0:y0 + 512, x0:x0 + 512]) * 1.04)
    return out


POSITIVES = {
    "ev+0.3": lambda im, a: to8(ev(a, 0.3)),
    "ev-0.3": lambda im, a: to8(ev(a, -0.3)),
    "tint-green": lambda im, a: to8(gains(a, 0.97, 1.04, 0.97)),
    "tint-magenta": lambda im, a: to8(gains(a, 1.03, 0.95, 1.03)),
    "warm": lambda im, a: to8(gains(a, 1.05, 1.0, 0.93)),
    "shadows-crushed": lambda im, a: to8(crush(a)),
    "blur-patch": lambda im, a: blur_patch(im),
    "blur-all": lambda im, a: im.filter(ImageFilter.GaussianBlur(1.2)),
    "seam": lambda im, a: to8(seam(a)),
}
NEGATIVES = {
    "identical": lambda im, a: im,
    "jpeg-q90": None,       # written as a JPEG at q90 below
    "resize-roundtrip": lambda im, a: im.resize((im.width * 3 // 4, im.height * 3 // 4), Image.LANCZOS)
                                        .resize(im.size, Image.LANCZOS),
}
# words a correct model reason should contain, per change
WORDS = {
    "ev+0.3": ["bright", "light", "exposure"], "ev-0.3": ["dark", "dim", "exposure"],
    "tint-green": ["green"], "tint-magenta": ["magenta", "pink", "purple", "red"],
    "warm": ["warm", "yellow", "orange"], "shadows-crushed": ["shadow", "dark", "contrast", "crush"],
    "blur-patch": ["blur", "soft", "patch"], "blur-all": ["blur", "soft", "sharp"],
    "seam": ["seam", "patch", "square", "line", "bright", "block", "edge"],
}


def build(sources, pairs_dir):
    pairs_dir.mkdir(parents=True, exist_ok=True)
    truth = []
    for src in sources:
        rgb, space = C.read_rgb01(src)
        a = C.resize01(C.display_srgb(rgb, space), SRC_PX)
        im = to8(a)
        a = np.asarray(im, dtype=np.float64) / 255.0
        stem = Path(src).stem.split("__")[0].replace("-before", "")
        pa = pairs_dir / f"{stem}-A.png"
        im.save(pa)
        for kind, fn in list(POSITIVES.items()) + list(NEGATIVES.items()):
            if kind == "jpeg-q90":
                pb = pairs_dir / f"{stem}-{kind}.jpg"
                im.save(pb, "JPEG", quality=90)
            else:
                pb = pairs_dir / f"{stem}-{kind}.png"
                fn(im, a).save(pb)
            truth.append({"name": f"{stem}:{kind}", "a": str(pa), "b": str(pb), "kind": kind,
                          "changed": kind in POSITIVES})
    return truth


def rates(rows, key):
    rows = [r for r in rows if not r.get("no_op")]
    pos = [r for r in rows if r["changed"]]
    neg = [r for r in rows if not r["changed"]]
    hit = sum(r[key] for r in pos)
    fa = sum(r[key] for r in neg)
    return {"hits": hit, "positives": len(pos), "hit_rate": hit / max(len(pos), 1),
            "false_alarms": fa, "negatives": len(neg), "false_alarm_rate": fa / max(len(neg), 1)}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", nargs="+", required=True)
    ap.add_argument("--real", help="dir of real before/after pairs whose answer is 'changed'")
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-model", action="store_true")
    ap.add_argument("--model", default=C.MODEL)
    args = ap.parse_args(argv)
    out = Path(args.out).expanduser()
    truth = build(args.sources, out / "pairs")
    if args.real:
        for p in C.load_pairs(args.real):
            truth.append({"name": f"{p.name}:real", "a": p.a, "b": p.b, "kind": "real", "changed": True})
    rows, results = [], []
    for t in truth:
        t0 = time.monotonic()
        r = C.check_pair(C.Pair(t["name"], t["a"], t["b"]), out, not args.no_model,
                         model=args.model)
        results.append(r)
        m = r.model or {}
        reason = m.get("reason", "")
        row = {**t, "numbers": bool(r.reasons), "model": bool(m.get("visible_difference")),
               "either": r.flagged, "model_reason": reason, "numbers_reasons": r.reasons,
               "median": r.numbers["median"], "p95": r.numbers["p95"], "block": r.numbers["block"],
               "sharp": r.numbers["sharp"], "seam": r.numbers["seam"],
               "model_seconds": m.get("seconds"), "seconds": time.monotonic() - t0,
               "error": r.error}
        n = r.numbers
        if t["changed"] and t["kind"] in POSITIVES and n["pixel_p95"] < 0.5 \
                and n["sharp_block_lo"] > 0.9 and n["seam"] < 3:
            row["no_op"] = True    # the change did nothing to this photo (no shadows to crush)
        row["reason_right"] = (row["model"] and t["kind"] in WORDS
                               and any(w in reason.lower() for w in WORDS[t["kind"]]))
        rows.append(row)
        print(f"{t['name']:<34} truth {'Y' if t['changed'] else 'n'} · numbers "
              f"{'Y' if row['numbers'] else 'n'} · model {'Y' if row['model'] else 'n'} · "
              f"{reason[:70]}", flush=True)
    summary = {k: rates(rows, k) for k in ("numbers", "model", "either")}
    ms = [r["model_seconds"] for r in rows if r["model_seconds"]]
    summary["model_seconds"] = {"median": float(np.median(ms)) if ms else None,
                                "max": float(max(ms)) if ms else None}
    summary["reason_right"] = sum(r["reason_right"] for r in rows if r["model"] and r["changed"])
    per_kind = {}
    for r in rows:
        k = per_kind.setdefault(r["kind"], {"n": 0, "numbers": 0, "model": 0})
        k["n"] += 1
        k["numbers"] += r["numbers"]
        k["model"] += r["model"]
    summary["per_kind"] = per_kind
    summary["no_op"] = [r["name"] for r in rows if r.get("no_op")]
    (out / "calibration.json").write_text(json.dumps({"model": None if args.no_model else args.model,
                                                      "summary": summary, "rows": rows}, indent=2))
    md = [f"# Calibration · model {args.model if not args.no_model else 'off'}", "",
          "| signal | hits | false alarms |", "|---|---|---|"]
    for k in ("numbers", "model", "either"):
        s = summary[k]
        md.append(f"| {k} | {s['hits']}/{s['positives']} ({s['hit_rate']:.0%}) | "
                  f"{s['false_alarms']}/{s['negatives']} ({s['false_alarm_rate']:.0%}) |")
    md += ["", f"model s/pair: median {summary['model_seconds']['median']} · max "
           f"{summary['model_seconds']['max']} · model reasons naming the change: "
           f"{summary['reason_right']}/{summary['model']['hits']}", "",
           f"excluded (the change did nothing to the photo): {', '.join(summary['no_op']) or 'none'}",
           "", "| change | n | numbers | model |", "|---|---|---|---|"]
    for k, v in per_kind.items():
        md.append(f"| {k} | {v['n']} | {v['numbers']} | {v['model']} |")
    (out / "calibration.md").write_text("\n".join(md) + "\n")
    C.write_report(results, out, {"run": out.name, "model": None if args.no_model else args.model,
                                  "pairs": "calibration"})
    print("\n".join(md))
    return 0


if __name__ == "__main__":
    sys.exit(main())
