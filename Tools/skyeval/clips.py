"""Sky + exposure on video frames, through the app's own look pipeline (lumina-render): the sky
gate and mask, the codec clip inside the sky, the meter, and what the new global `dehaze` stage
does to the sky against a frame left alone. One contact sheet and one JSON per clip set.

Sets (one 16-bit frame per clip, taken from the middle of the clip with ffmpeg, see the README):
  --transfer slog3   S-Log3 / S-Gamut3.Cine clips (the friend's a7S III): decoded to scene-linear
                     Rec.709 here (Sony's published curve and matrix), written as a linear-light
                     16-bit PNG that lumina-render develops like any image.
  --transfer 709     Rec.709 clips (his graded ProRes exports, the a7 III card): the frame as is.

Looks rendered per frame: base (no look), dhz:+30, dhz:+60, and the owner's typical Death
Valley move (hl:-68 dhz:+14 vib:+14). Measured per frame (sRGB renders, CIELAB):
  sky share and the Vision gate; codec clip inside the sky per channel (code >= 0.98);
  meter = median L* of what is not sky; the sky's L*, chroma C*ab and hue in each look;
  the non-sky midtone's L* change under each look (a global stage moves everything).

  python Tools/skyeval/clips.py --frames ~/LuminaEvidence/skyeval/video/frames/log --transfer slog3 --out ~/LuminaEvidence/skyeval/video/log
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import delta_e  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")
LOOKS = [("base", ""), ("dhz30", "dhz:+30"), ("dhz60", "dhz:+60"), ("owner", "hl:-68 dhz:+14 vib:+14")]
PX = 1024
W, H = 320, 180

# S-Gamut3.Cine → Rec.709 (D65), Sony's published matrix.
SGC_TO_709 = np.array([[1.6269474, -0.5401385, -0.0868089],
                       [-0.1785155, 1.4179409, -0.2394254],
                       [-0.0444361, -0.1959199, 1.2403560]])


def slog3_to_linear(t):
    """Sony S-Log3 (reflectance), t = code / 1023 in 0…1: 0.18 grey at code 420."""
    t = np.asarray(t, dtype=np.float64)
    cv = t * 1023.0
    hi = np.power(10.0, (cv - 420.0) / 261.5) * (0.18 + 0.01) - 0.01
    lo = (cv - 95.0) * 0.01125 / (171.2102946929 - 95.0)
    return np.where(cv >= 171.2102946929, hi, lo)


def srgb_encode(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def read16(path):
    """A 16-bit (or 8-bit) TIFF as float 0…1, (H, W, 3). PIL drops 16-bit RGB to 8, so tifffile reads and writes them."""
    import tifffile
    a = np.asarray(tifffile.imread(path))
    a = a.astype(np.float64) / (65535.0 if a.dtype == np.uint16 else 255.0)
    return a[..., :3]


def prepare(frame, transfer, out):
    """The image lumina-render reads: the frame itself for 709, or S-Log3 decoded to linear Rec.709
    then sRGB-encoded (lumina-render linearises it again). Returns (path, codes): codes = the frame's
    own code values 0…1, for the clip measure."""
    codes = read16(frame)
    if transfer == "709":
        return frame, codes
    lin = slog3_to_linear(codes) @ SGC_TO_709.T
    enc = (srgb_encode(lin) * 65535 + 0.5).astype(np.uint16)
    import tifffile  # a 16-bit TIFF (PIL writes 8)
    tifffile.imwrite(out, enc, photometric="rgb")
    return out, codes


def sky_mask(image, out):
    r = subprocess.run([RENDER, "sky", image, "--px", str(PX), "--out", out], capture_output=True, text=True)
    info = {}
    for line in (r.stdout + r.stderr).splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                info = json.loads(line)
            except ValueError:
                pass
    mask = None
    if os.path.exists(out):
        mask = np.asarray(Image.open(out).convert("L"), np.float64) / 255
    return mask, info


def lab_stats(rgb, sel):
    if sel.sum() < 50:
        return None
    lab = delta_e.to_lab(np.clip(rgb, 0, 1), "srgb")
    L, a, b = (lab[..., i][sel] for i in range(3))
    C = np.hypot(a, b)
    return {"L": float(np.median(L)), "C": float(np.median(C)), "hue": float(np.degrees(np.arctan2(b.mean(), a.mean())) % 360)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", required=True)
    ap.add_argument("--transfer", choices=("slog3", "709"), required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    out = os.path.expanduser(a.out)
    for d in ("prep", "sky", "render"):
        os.makedirs(os.path.join(out, d), exist_ok=True)
    frames = sorted(f for f in os.listdir(os.path.expanduser(a.frames)) if f.lower().endswith((".tif", ".tiff")))
    rows, jobs = [], []
    for f in frames:
        stem = os.path.splitext(f)[0]
        src = os.path.join(os.path.expanduser(a.frames), f)
        image, codes = prepare(src, a.transfer, os.path.join(out, "prep", stem + ".tif"))
        mask, info = sky_mask(image, os.path.join(out, "sky", stem + ".png"))
        h, w = codes.shape[:2]
        row = {"stem": stem, "image": image, "gate": info.get("gate"), "labels": info.get("labels"), "sky": 0.0, "clip": None}
        if mask is not None:
            m = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR), np.float64) / 255 > 0.5
            row["sky"] = float(m.mean())
            if m.sum() > 50:
                row["clip"] = {c: float((codes[..., i][m] >= 0.98).mean()) for i, c in enumerate("rgb")}
                row["clipAny"] = float((codes[m] >= 0.98).any(axis=-1).mean())
        for name, look in LOOKS:
            o = os.path.join(out, "render", f"{stem}__{name}.tif")
            row[name] = o
            if not os.path.exists(o):
                jobs.append({"image": image, "look": look, "px": PX, "space": "srgb", "out": o})
        rows.append(row)
    if jobs:
        jp = os.path.join(out, "jobs.json")
        json.dump(jobs, open(jp, "w"))
        subprocess.run([RENDER, "batch", jp], stdout=subprocess.DEVNULL, check=False)
    for row in rows:
        maskp = os.path.join(out, "sky", row["stem"] + ".png")
        base = delta_e.read_rgb01(row["base"])[0]
        hh, ww = base.shape[:2]
        sky = np.zeros((hh, ww), bool)
        if os.path.exists(maskp):
            sky = np.asarray(Image.open(maskp).convert("L").resize((ww, hh), Image.BILINEAR), np.float64) / 255 > 0.5
        row["meter"] = lab_stats(base, ~sky)
        row["colour"] = {}
        for name, _ in LOOKS:
            rgb = delta_e.read_rgb01(row[name])[0]
            row["colour"][name] = {"sky": lab_stats(rgb, sky), "rest": lab_stats(rgb, ~sky)}
    json.dump(rows, open(os.path.join(out, "clips.json"), "w"), indent=1)

    # the sheet: frame | sky mask | base | dhz:+30 | dhz:+60 | owner's move
    cols = ["frame", "sky"] + [n for n, _ in LOOKS]
    sheet = Image.new("RGB", (10 + len(cols) * (W + 6), 30 + len(rows) * (H + 34)), "white")
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 4), f"{a.title or a.frames}   columns: frame as shot ({a.transfer}) | sky mask | base render | dhz:+30 | dhz:+60 | hl:-68 dhz:+14 vib:+14 (the owner's Death Valley move)", fill="black")
    for i, row in enumerate(rows):
        y = 30 + i * (H + 34)
        c = row["colour"]
        sk = c["base"]["sky"]
        txt = f"{row['stem']}  gate {row['gate'] if row['gate'] is None else round(row['gate'], 2)}  sky {row['sky'] * 100:.0f}%"
        if row["clip"]:
            txt += f"  clipped in sky r/g/b {row['clip']['r'] * 100:.0f}/{row['clip']['g'] * 100:.0f}/{row['clip']['b'] * 100:.0f}%"
        if row["meter"]:
            txt += f"  midtone L* {row['meter']['L']:.0f}"
        if sk:
            txt += f"  sky L*/C*/hue base {sk['L']:.0f}/{sk['C']:.0f}/{sk['hue']:.0f}°"
            for n in ("dhz30", "dhz60", "owner"):
                s2 = c[n]["sky"]
                if s2:
                    txt += f"  {n} {s2['L']:.0f}/{s2['C']:.0f}/{s2['hue']:.0f}°"
        r0, r1 = c["base"]["rest"], c["dhz60"]["rest"]
        if r0 and r1:
            txt += f"  rest L* {r0['L']:.0f}→{r1['L']:.0f} at dhz60"
        dr.text((10, y), txt, fill="black")
        tiles = [row["image"] if a.transfer == "709" else os.path.join(out, "prep", row["stem"] + ".tif"), os.path.join(out, "sky", row["stem"] + ".png")] + [row[n] for n, _ in LOOKS]
        for j, p in enumerate(tiles):
            if not os.path.exists(p):
                continue
            if p.lower().endswith((".tif", ".tiff")):
                rgb = delta_e.read_rgb01(p)[0]
                im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
            else:
                im = Image.open(p)
            im = im.convert("RGB")
            im.thumbnail((W, H))
            t = Image.new("RGB", (W, H), "black")
            t.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
            sheet.paste(t, (10 + j * (W + 6), y + 14))
    sp = os.path.join(out, "sheet.jpg")
    sheet.save(sp, quality=86)
    print(sp)
    for row in rows:
        sk = row["colour"]["base"]["sky"]
        print(row["stem"], "gate", row["gate"], "sky %.0f%%" % (row["sky"] * 100), "clip", row.get("clipAny"), "meter", row["meter"] and round(row["meter"]["L"]),
              "sky base", sk and (round(sk["L"]), round(sk["C"]), round(sk["hue"])), "dhz60", row["colour"]["dhz60"]["sky"] and tuple(round(v) for v in row["colour"]["dhz60"]["sky"].values()))


if __name__ == "__main__":
    main()
