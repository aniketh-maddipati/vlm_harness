#!/usr/bin/env python3
"""A picture of the pipeline for humans: one ARW through every slider, as a labelled contact
sheet and as animated GIFs of sliders sweeping. For PR comments and design reviews; the images
never enter the repo (they hold photo content).

    python3 Tools/parity/showcase.py /Volumes/CARD/DCIM/101MSDCF/DSC01234.ARW --out ~/LuminaEvidence/showcase
        → <out>/DSC01234-sheet.png            base + 12 sliders × 3 positions, labelled
          <out>/DSC01234-exposure.gif         ev −2 … +2, 21 frames
          <out>/DSC01234-shadows.gif          sh −100 … +100, 21 frames
          <out>/DSC01234-tour.gif             one pass through every slider

Needs the Mac (lumina-render is Core Image): `make render` first, or pass --render-bin.
Pillow only; no ffmpeg. --px sets the render size (default 640 on the long edge, keep the sheet
under a few MB), --sliders limits the sheet, --gif picks which sweeps to make.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lookmath  # noqa: E402

SHEET = [  # (label, look string)
    ("base", ""),
    ("ev −2", "ev:-2"), ("ev +1", "ev:+1"), ("ev +2", "ev:+2"),
    ("wb 3200 K", "wb:3200/0"), ("wb 5500 K", "wb:5500/0"), ("wb 9000 K", "wb:9000/0"),
    ("tint −60", "wb:5500/-60"), ("tint +60", "wb:5500/+60"),
    ("contrast −80", "con:-80"), ("contrast +40", "con:+40"), ("contrast +80", "con:+80"),
    ("highlights −100", "hl:-100"), ("highlights +60", "hl:+60"),
    ("shadows −60", "sh:-60"), ("shadows +100", "sh:+100"),
    ("whites −60", "wh:-60"), ("whites +60", "wh:+60"),
    ("blacks −60", "bl:-60"), ("blacks +60", "bl:+60"),
    ("vibrance −100", "vib:-100"), ("vibrance +80", "vib:+80"),
    ("saturation −100", "sat:-100"), ("saturation +60", "sat:+60"),
    ("clarity −80", "clr:-80"), ("clarity +80", "clr:+80"),
    ("sharpen 150", "shp:150"),
    ("vignette −100", "vig:-100"), ("B&W", "bw:1"),
    ("roadmap example", "ev:+0.70 con:+12 hl:-40 sh:+25 bl:-8 vib:+10 clr:+15 shp:30"),
]
SWEEPS = {
    "exposure": [f"ev:{v:+.2f}" for v in [i / 5 - 2 for i in range(21)]],
    "shadows": [f"sh:{v:+d}" for v in range(-100, 101, 10)],
    "contrast": [f"con:{v:+d}" for v in range(-100, 101, 10)],
    "wb": [f"wb:{k}/0" for k in [2500, 3000, 3500, 4000, 4500, 5000, 5500, 6200, 7000, 8000, 9500, 12000]],
    "vibrance": [f"vib:{v:+d}" for v in range(-100, 101, 10)],
}


def render_all(render_bin, arw, looks, px, out_dir):
    """looks: list of (name, look string) → dict name → JPEG path, via one lumina-render batch."""
    jobs = [{"image": arw, "look": look, "px": px, "space": "srgb", "out": os.path.join(out_dir, f"{name}.jpg")} for name, look in looks]
    plan = os.path.join(out_dir, "jobs.json")
    with open(plan, "w") as f:
        json.dump(jobs, f)
    p = subprocess.run([render_bin, "batch", plan], capture_output=True, text=True)
    ok, times = {}, []
    for line in p.stdout.splitlines():
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if j.get("ok"):
            ok[os.path.splitext(os.path.basename(j["out"]))[0]] = j["out"]
            times.append(j.get("renderMs", 0))
        else:
            print(f"render failed: {j.get('look')!r}: {j.get('error')}", file=sys.stderr)
    if p.returncode != 0 and not ok:
        print(p.stderr[-800:], file=sys.stderr)
    return ok, times


def label(img, text, font):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    w = d.textlength(text, font=font)
    d.rectangle([0, 0, w + 12, 26], fill=(0, 0, 0))
    d.text((6, 4), text, fill=(255, 255, 255), font=font)
    return img


def sheet(images, labels, columns, out):
    """A grid of equally sized tiles with a label in each corner."""
    from PIL import Image, ImageFont
    font = ImageFont.load_default()
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
    except Exception:
        pass
    tiles = [Image.open(p).convert("RGB") for p in images]
    tw, th = tiles[0].size
    rows = (len(tiles) + columns - 1) // columns
    grid = Image.new("RGB", (columns * tw + (columns - 1) * 4, rows * th + (rows - 1) * 4), (24, 24, 24))
    for i, (t, name) in enumerate(zip(tiles, labels)):
        t = label(t.resize((tw, th)), name, font)
        grid.paste(t, ((i % columns) * (tw + 4), (i // columns) * (th + 4)))
    grid.save(out, optimize=True)
    return grid.size


def gif(images, labels, out, ms=120):
    from PIL import Image, ImageFont
    font = ImageFont.load_default()
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
    except Exception:
        pass
    frames = [label(Image.open(p).convert("RGB"), name, font) for p, name in zip(images, labels)]
    bounce = frames + frames[-2:0:-1]
    bounce[0].save(out, save_all=True, append_images=bounce[1:], duration=ms, loop=0, optimize=True)
    return len(bounce)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("arw")
    ap.add_argument("--out", default=os.path.expanduser("~/LuminaEvidence/showcase"))
    ap.add_argument("--render-bin", default=os.path.join(HERE, "lumina-render", ".build", "release", "lumina-render"))
    ap.add_argument("--px", type=int, default=640)
    ap.add_argument("--columns", type=int, default=5)
    ap.add_argument("--gif", default="exposure,shadows,tour", help="comma list from: " + ", ".join(SWEEPS) + ", tour, none")
    ap.add_argument("--sliders", help="comma list of sheet labels to keep (substring match)")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.arw))[0]
    rows = [(l, s) for l, s in SHEET if not a.sliders or any(k.strip().lower() in l.lower() for k in a.sliders.split(","))]
    gifs = [g for g in a.gif.split(",") if g and g != "none"]
    looks = [(f"sheet-{i:02d}", s) for i, (_, s) in enumerate(rows)]
    for g in gifs:
        seq = SWEEPS.get(g) if g != "tour" else [s for _, s in rows]
        looks += [(f"{g}-{i:02d}", s) for i, s in enumerate(seq or [])]
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, s) in enumerate(looks):
            looks[i] = (name, lookmath.format_look(lookmath.parse_look(s)))
        done, times = render_all(a.render_bin, a.arw, looks, a.px, tmp)
        if not done:
            return 1
        imgs = [done[f"sheet-{i:02d}"] for i in range(len(rows)) if f"sheet-{i:02d}" in done]
        labels = [l for i, (l, _) in enumerate(rows) if f"sheet-{i:02d}" in done]
        size = sheet(imgs, labels, a.columns, os.path.join(a.out, f"{stem}-sheet.png"))
        print(f"{stem}-sheet.png: {len(imgs)} tiles, {size[0]}×{size[1]}")
        for g in gifs:
            seq = SWEEPS.get(g) if g != "tour" else [s for _, s in rows]
            names = [f"{g}-{i:02d}" for i in range(len(seq or []))]
            frames = [done[n] for n in names if n in done]
            labs = [(rows[i][0] if g == "tour" else seq[i]) for i, n in enumerate(names) if n in done]
            if frames:
                n = gif(frames, labs, os.path.join(a.out, f"{stem}-{g}.gif"), ms=90 if g != "tour" else 700)
                print(f"{stem}-{g}.gif: {n} frames")
        if times:
            times.sort()
            print(f"render+encode at {a.px} px: median {times[len(times) // 2]} ms, p95 {times[int(len(times) * 0.95)]} ms, {len(times)} renders")
    print(f"→ {a.out}  (drop the PNG/GIFs into the PR comment; they hold photo content, never commit them)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
