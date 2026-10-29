"""F1 contact sheet for the owner's labels: 30 frames, 10 per verdict, each as base render |
sky mask (cyan) + white (yellow) + clipped-at-sensor (red) overlay, with the app's verdict and the
numbers. The owner marks any row whose verdict looks wrong.

  python sheet_f1.py --rows ~/LuminaEvidence/skyeval/f1/rows.jsonl --out ~/LuminaEvidence/skyeval/f1/sheet.jpg
"""
import argparse
import json
import os
import random
import subprocess

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")
W, H = 360, 240


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--per", type=int, default=10)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(os.path.expanduser(a.rows))]
    d = os.path.dirname(os.path.expanduser(a.rows))
    random.seed(3)
    pick = []
    for v in ("fine", "recoverable", "clipped-at-capture"):
        s = [r for r in rows if r.get("truth") == v]
        pick += random.sample(s, min(a.per, len(s)))
    rdir = os.path.join(d, "sheet-render")
    os.makedirs(rdir, exist_ok=True)
    jobs = [{"image": r["image"], "look": "", "px": W, "space": "srgb", "out": os.path.join(rdir, r["stem"] + ".jpg")} for r in pick
            if not os.path.exists(os.path.join(rdir, r["stem"] + ".jpg"))]
    if jobs:
        json.dump(jobs, open(os.path.join(rdir, "jobs.json"), "w"))
        subprocess.run([RENDER, "batch", os.path.join(rdir, "jobs.json")], stdout=subprocess.DEVNULL, check=False)
    cols = 2
    sheet = Image.new("RGB", (cols * (2 * W + 10) + 10, (len(pick) + cols - 1) // cols * (H + 34) + 10), "white")
    dr = ImageDraw.Draw(sheet)
    for i, r in enumerate(pick):
        base = Image.open(os.path.join(rdir, r["stem"] + ".jpg")).convert("RGB").resize((W, H))
        ov = np.asarray(base, np.float32).copy()
        def plane(n):
            p = os.path.join(d, r["stem"], n)
            return np.asarray(Image.open(p).convert("L").resize((W, H)), np.float32) / 255 if os.path.exists(p) else np.zeros((H, W), np.float32)
        sky, white, clip = plane("sky.png"), plane("white.png"), plane("clipped.png")
        for m, col, k in ((sky, (0, 200, 255), 0.35), (white, (255, 230, 0), 0.6), (clip, (255, 40, 40), 0.8)):
            ov = ov * (1 - k * m[..., None]) + np.array(col)[None, None] * (k * m[..., None])
        x = 10 + (i % cols) * (2 * W + 10)
        y = 10 + (i // cols) * (H + 34)
        sheet.paste(base, (x, y + 24)); sheet.paste(Image.fromarray(ov.clip(0, 255).astype(np.uint8)), (x + W, y + 24))
        txt = f"{i + 1:2d} {r['stem']}  app: {r['verdict']}  sky {r['sky'] * 100:.0f}%  white {r['white'] * 100:.0f}%  clipped(app) {r['clipped'] * 100:.0f}%  clipped(raw) {r['truthClipped'] * 100:.0f}%"
        dr.text((x, y + 6), txt, fill="black")
    dr.text((10, sheet.height - 8), "overlay: cyan = sky mask · yellow = white in today's render · red = clipped at the sensor (Apple decoder, recovery on vs off)", fill="black")
    sheet.save(os.path.expanduser(a.out), quality=88)
    json.dump([{"n": i + 1, "stem": r["stem"], "app": r["verdict"], "raw": r["truth"]} for i, r in enumerate(pick)], open(os.path.splitext(os.path.expanduser(a.out))[0] + ".json", "w"), indent=1)
    print(a.out, len(pick))


if __name__ == "__main__":
    main()
