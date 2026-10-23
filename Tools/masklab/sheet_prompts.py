#!/usr/bin/env python3
"""Sheet for experiment B (prompts_merged.py): per object, the truth, Vision's best instance and each prompt's mask.

    python3 Tools/masklab/sheet_prompts.py OUT.jpg --davis DAVIS_ROOT --oracle RUN/vision-oracle --b DIR \
        --objects lab-coat_3,gold-fish_2 [--model vision-balanced] [--frame 0] [--width 2400] [--max-kb 600]

Columns: truth (green), Vision's best instance, then one click, click + exclude, box (magenta), each captioned with
its IoU; include points are drawn as green +, exclude points as red −, boxes as a white frame.
"""
import argparse, io, json, os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from sheet import GREEN, MAGENTA, tint


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--davis", required=True)
    ap.add_argument("--oracle", required=True)
    ap.add_argument("--b", required=True)
    ap.add_argument("--objects", required=True)
    ap.add_argument("--model", default="vision-balanced")
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--width", type=int, default=2400)
    ap.add_argument("--max-kb", type=int, default=600)
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    res = json.load(open(os.path.join(a.b, "results.json")))
    font = ImageFont.load_default()
    cols = ["truth", "vision", "click", "clicks", "box"]
    tw = a.width // len(cols)
    rows = []
    for key in a.objects.split(","):
        seq, obj = key.rsplit("_", 1)
        img = Image.open(os.path.join(a.davis, "JPEGImages/480p", seq, f"{a.frame:05d}.jpg")).convert("RGB")
        w, h = img.size
        lab = np.array(Image.open(os.path.join(a.davis, "Annotations/480p", seq, f"{a.frame:05d}.png"))) == int(obj)
        r = res[key]
        tiles = []
        for c in cols:
            if c == "truth":
                t, cap = tint(img, lab, GREEN), f"{key}  truth"
            elif c == "vision":
                p = os.path.join(a.oracle, key, f"{a.frame:06d}.png")
                m = np.array(Image.open(p).convert("L").resize((w, h), Image.NEAREST)) >= 128
                t, cap = tint(img, m, MAGENTA), f"Vision best instance  IoU {r['vision_oracle']:.2f}"
            else:
                if c not in r[a.model]:
                    tiles.append((Image.new("RGB", (w, h)), f"{c}: n/a"))
                    continue
                m = np.array(Image.open(os.path.join(a.b, a.model, f"{key}-{c}.png")).convert("L")) >= 128
                t = tint(img, m, MAGENTA)
                d = ImageDraw.Draw(t)
                s = max(4, w // 80)
                if c == "box":
                    d.rectangle(r["box"], outline=(255, 255, 255), width=2)
                else:
                    x, y = r["pos"]
                    d.line([x - s, y, x + s, y], fill=(40, 255, 90), width=3)
                    d.line([x, y - s, x, y + s], fill=(40, 255, 90), width=3)
                    if c == "clicks" and r.get("neg"):
                        x, y = r["neg"]
                        d.line([x - s, y, x + s, y], fill=(255, 50, 50), width=3)
                names = {"click": "1 click", "clicks": "click + exclude", "box": "box"}
                cap = f"{a.model} {names[c]}  IoU {r[a.model][c]['iou']:.2f}"
            tiles.append((t, cap))
        th = round(h * tw / w)
        row = Image.new("RGB", (tw * len(cols), th + 4))
        for i, (t, cap) in enumerate(tiles):
            t = t.resize((tw, th), Image.LANCZOS)
            d = ImageDraw.Draw(t)
            d.rectangle([0, 0, tw, 14], fill=(0, 0, 0))
            d.text((3, 1), cap, fill=(255, 255, 255), font=font)
            row.paste(t, (i * tw, 0))
        rows.append(row)
    head = 22 if a.title else 0
    sheet = Image.new("RGB", (rows[0].size[0], sum(r.size[1] for r in rows) + head))
    if a.title:
        ImageDraw.Draw(sheet).text((6, 4), a.title, fill=(255, 255, 255), font=font)
    y = head
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.size[1]
    scale = 1.0
    while True:
        im = sheet if scale == 1 else sheet.resize((round(sheet.size[0] * scale), round(sheet.size[1] * scale)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=80, optimize=True)
        if buf.tell() <= a.max_kb * 1024 or scale < 0.3:
            break
        scale *= 0.9
    open(a.out, "wb").write(buf.getvalue())
    print(f"{a.out}: {im.size[0]}×{im.size[1]}, {buf.tell() // 1024} KB")


if __name__ == "__main__":
    main()
