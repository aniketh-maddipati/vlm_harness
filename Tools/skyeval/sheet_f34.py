"""F3 / F4 contact sheet: base | F3 (mask:sky/ev=-1) | F4 (mask:sky/blu=60) | all on | Lightroom ref
(where present: the Death Valley base export, Adobe Color, no sky edit). Rows picked per verdict,
plus any photo whose stem is listed in --stems (horizons, trees against sky, buildings).

  python sheet_f34.py --dir ~/LuminaEvidence/skyeval/f34/clamp --rows ~/LuminaEvidence/skyeval/f1/rows.jsonl --refs ~/LuminaEvidence/parity/dv-tone/base-refs --out sheet.jpg
"""
import argparse
import json
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import delta_e  # noqa: E402

W, H = 300, 200


def tile(path):
    if path.lower().endswith((".tif", ".tiff")):
        rgb = delta_e.read_rgb01(path)[0]
        im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    else:
        im = Image.open(path).convert("RGB")
    im.thumbnail((W, H))
    out = Image.new("RGB", (W, H), "black")
    out.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--rows", required=True)
    ap.add_argument("--refs")
    ap.add_argument("--out", required=True)
    ap.add_argument("--per", type=int, default=6)
    ap.add_argument("--stems", default="")
    a = ap.parse_args()
    d = os.path.expanduser(a.dir)
    res = {r["stem"]: r for r in json.load(open(os.path.join(d, "f34.json")))}
    random.seed(5)
    pick = [s for s in a.stems.split(",") if s and s in res]
    for v in ("fine", "recoverable", "clipped-at-capture"):
        s = [k for k, r in res.items() if r["verdict"] == v and k not in pick]
        pick += random.sample(s, min(a.per, len(s)))
    cols = ["base", "f3", "f4", "all"]
    sheet = Image.new("RGB", (10 + 5 * (W + 6), 10 + len(pick) * (H + 30)), "white")
    dr = ImageDraw.Draw(sheet)
    for i, st in enumerate(pick):
        y = 10 + i * (H + 30)
        r = res[st]
        halo = r['f3']['haloP95']
        dr.text((10, y + 4), f"{st}  {r['verdict']}  sky {r['sky'] * 100:.0f}%   F3 halo p95 {halo if halo is None else round(halo, 1)}  F4 hue {r['colour_base']['hue']:.0f}°→{r['colour_f4']['hue']:.0f}° chroma {r['colour_base']['chroma']:.1f}→{r['colour_f4']['chroma']:.1f}  all-on chroma {r['colour_all']['chroma']:.1f}", fill="black")
        for j, k in enumerate(cols):
            sheet.paste(tile(os.path.join(d, "render", f"{st}__{k}.tif")), (10 + j * (W + 6), y + 18))
        ref = os.path.join(os.path.expanduser(a.refs), st + ".jpg") if a.refs else None
        if ref and os.path.exists(ref):
            sheet.paste(tile(ref), (10 + 4 * (W + 6), y + 18))
        else:
            dr.text((10 + 4 * (W + 6) + 8, y + 18 + H // 2), "no LR ref", fill="grey")
    dr.text((10, 2), "base | F3 mask:sky/ev=-1.00 | F4 mask:sky/blu=60 | both | Lightroom (Adobe Color base export, no sky edit)", fill="black")
    sheet.save(os.path.expanduser(a.out), quality=86)
    print(a.out, pick)


if __name__ == "__main__":
    main()
