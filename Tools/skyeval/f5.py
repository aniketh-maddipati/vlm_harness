"""F5 exposure across a set: each photo's ev so the set's metered midtones meet at their median.

Sets: photos from f1's rows grouped by capture time (a gap over --gap seconds starts a new set),
sets of 3 or more. Each photo is rendered (lumina-render, sRGB 16-bit, 768 px) at ev 0 and at its
F5 ev; the midtone is then measured on the render itself (median L* of pixels not sky, not at
white, not black), so the score includes everything the pipeline does after exposure.
Score: spread (std) of the measured midtone L* per set before → after (bar: halves); hue
collateral: the shift of the mean hue of non-sky colour (should be ~0); WB is reported, not fixed.

  python f5.py --rows ~/LuminaEvidence/skyeval/f1/rows.jsonl --out ~/LuminaEvidence/skyeval/f5
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import delta_e  # noqa: E402
from f2 import ev_for  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")


def times(paths):
    out = subprocess.run(["exiftool", "-j", "-n", "-DateTimeOriginal", "-SubSecTimeOriginal", "-WhiteBalance", "-ColorTemperature"] + paths,
                         capture_output=True, text=True).stdout
    from datetime import datetime
    res = {}
    for d in json.loads(out):
        t = datetime.strptime(str(d["DateTimeOriginal"]), "%Y:%m:%d %H:%M:%S").timestamp() + float("0." + str(d.get("SubSecTimeOriginal", 0)))
        res[d["SourceFile"]] = t
    return res


def measure(path, sky_png):
    rgb = delta_e.read_rgb01(path)[0]
    H, W = rgb.shape[:2]
    lab = delta_e.to_lab(rgb, "srgb")
    keep = np.ones(rgb.shape[:2], bool)            # every non-sky pixel: a frame that is mostly white counts as white
    if sky_png and os.path.exists(sky_png):
        sky = np.asarray(Image.open(sky_png).convert("L").resize((W, H), Image.BILINEAR), np.float32) / 255
        keep &= sky < 0.5
    L = lab[..., 0][keep]
    a, b = lab[..., 1][keep], lab[..., 2][keep]
    C = np.hypot(a, b)
    col = C > 5
    hue = float(np.degrees(np.arctan2((b[col]).mean(), (a[col]).mean())) % 360) if col.any() else None
    return {"midtone": float(np.median(L)), "hue": hue, "a": float(a.mean()), "b": float(b.mean())}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--gap", type=float, default=60)
    ap.add_argument("--max-sets", type=int, default=12)
    a = ap.parse_args()
    out = os.path.expanduser(a.out)
    os.makedirs(os.path.join(out, "render"), exist_ok=True)
    f1dir = os.path.dirname(os.path.expanduser(a.rows))
    rows = [json.loads(l) for l in open(os.path.expanduser(a.rows))]
    rows = [r for r in rows if "meter" in r]
    t = times([r["image"] for r in rows])
    rows = sorted([r for r in rows if r["image"] in t], key=lambda r: t[r["image"]])
    sets, cur = [], [rows[0]]
    for r in rows[1:]:
        if t[r["image"]] - t[cur[-1]["image"]] > a.gap:
            sets.append(cur); cur = []
        cur.append(r)
    sets.append(cur)
    sets = [s for s in sets if len(s) >= 3]
    sets = sorted(sets, key=len, reverse=True)[: a.max_sets]
    jobs, plan = [], []
    for i, s in enumerate(sets):
        target = float(np.median([r["meter"]["midtone"] for r in s]))
        for r in s:
            ev = ev_for(r["meter"]["midtone"], target)
            r["f5ev"] = ev
            for k, look in (("before", ""), ("after", f"ev:{ev:+.2f}")):
                o = os.path.join(out, "render", f"{r['stem']}__{k}.tif")
                r[k + "Path"] = o
                if not os.path.exists(o):
                    jobs.append({"image": r["image"], "look": look, "px": 768, "space": "srgb", "out": o})
    if jobs:
        json.dump(jobs, open(os.path.join(out, "jobs.json"), "w"))
        subprocess.run([RENDER, "batch", os.path.join(out, "jobs.json")], stdout=subprocess.DEVNULL, check=False)
    res = []
    for i, s in enumerate(sets):
        before = [measure(r["beforePath"], os.path.join(f1dir, r["stem"], "sky.png")) for r in s]
        after = [measure(r["afterPath"], os.path.join(f1dir, r["stem"], "sky.png")) for r in s]
        dh = [((x["hue"] - y["hue"] + 180) % 360) - 180 for x, y in zip(after, before) if x["hue"] is not None and y["hue"] is not None]
        wb = [str(t.get("ColorTemperature")) for t in []]
        res.append({"set": i, "n": len(s), "first": s[0]["stem"], "last": s[-1]["stem"],
                    "stdBefore": float(np.std([x["midtone"] for x in before])), "stdAfter": float(np.std([x["midtone"] for x in after])),
                    "evs": [r["f5ev"] for r in s], "hueShiftMedian": float(np.median(dh)) if dh else None,
                    "hueShiftMaxAbs": float(np.max(np.abs(dh))) if dh else None,
                    "wbSpreadB": float(np.std([x["b"] for x in before]))})
    ratio = [r["stdAfter"] / r["stdBefore"] for r in res if r["stdBefore"] > 0]
    summary = {"sets": len(res), "photos": sum(r["n"] for r in res), "stdBeforeMedian": float(np.median([r["stdBefore"] for r in res])),
               "stdAfterMedian": float(np.median([r["stdAfter"] for r in res])), "ratioMedian": float(np.median(ratio)),
               "setsHalved": int(sum(x <= 0.5 for x in ratio)), "hueShiftMedianAbs": float(np.median([abs(r["hueShiftMedian"]) for r in res if r["hueShiftMedian"] is not None]))}
    json.dump({"summary": summary, "sets": res}, open(os.path.join(out, "f5.json"), "w"), indent=1)
    print(json.dumps(summary, indent=1))
    for r in res:
        print(r["set"], r["n"], r["first"], r["last"], round(r["stdBefore"], 2), "→", round(r["stdAfter"], 2), "hue", r["hueShiftMedian"])


if __name__ == "__main__":
    main()
