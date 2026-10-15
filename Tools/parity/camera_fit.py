#!/usr/bin/env python3
"""The camera profile: fit, per Sony Creative Style, the step from Lumina's base (Lightroom's Adobe
Color) to the camera's own JPEG, and measure it on photos the fit never saw.

    python3 Tools/parity/camera_fit.py index <folder>... [--out ~/LuminaEvidence/camera-profile]
        → index.tsv: every ARW's body, Creative Style, DRO, orientation (exiftool, no decode).
    python3 Tools/parity/camera_fit.py fit [--per-style 160] [--px 384] [--rules …/rules-v1.json]
        → renders the sample through lumina-render (neutral look; disk cache), pulls each ARW's
          embedded JPEG, fits the camera stage's coefficients per style on the train half and
          reports ΔE2000 on the held-out half: camera JPEG vs Lumina's base and vs Lumina + the
          camera stage, and prints the coefficients for rules-v1.json's `camera` stage.

Every ARW carries the camera's rendering of itself (the embedded JPEG: 1616 × 1080 on the a7 III),
made with the Creative Style the photographer chose, so the targets cost nothing and every shoot
adds more. The stage's form is the base match's (LookMath.baseMatch: a luma midtone curve, a
colour mix whose rows sum to 1, colour fading near white and in the deepest shadows), so a grey
stays grey and the ramp tests hold; only the numbers are per style. Lightroom's answer to the same
question is its Camera Matching profiles, chosen by the same style.

Comparison is on 72 × 48 block means with a 5 % border dropped: the camera's JPEG is sharpened,
denoised and distortion-corrected, Lumina's base is not, and the blocks keep colour and tone while
ignoring those. The camera's DRO (on "Auto" for most shots) lifts shadows per photo; the fit
averages over it.

Split: by shoot when the style has more than one, so a held-out photo never shares a scene with a
training one (a style shot on one day only is split by file, said so in the report). Photos and
renders stay in ~/LuminaEvidence/camera-profile; only numbers go to Tools/parity/report.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402
import lookmath  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
RULES = os.path.join(REPO, "Lumina/Sets/Look/rules-v1.json")
RENDER = os.path.join(HERE, "lumina-render/.build/release/lumina-render")
OUT = os.path.expanduser("~/LuminaEvidence/camera-profile")
BLOCKS = (72, 48)
BORDER = 0.05
# Fitted per style; hiFrom / loBelow stay where the base has them.
FREE = ("lift", "s", "rg", "rb", "gr", "gb", "br", "bg", "hiDesat", "loDesat")
# lookmath's names → the rules' (LookMath.BaseMatch reads `<style>Lift`, `<style>RG`, …)
RULE_NAME = {"lift": "Lift", "s": "S", "rg": "RG", "rb": "RB", "gr": "GR", "gb": "GB", "br": "BR", "bg": "BG",
             "hiDesat": "HiDesat", "hiFrom": "HiFrom", "loDesat": "LoDesat", "loBelow": "LoBelow"}
COLUMNS = ("dir", "file", "model", "style", "dro", "contrast", "saturation", "sharpness", "effect", "orientation", "iso")


def index(folders, out):
    os.makedirs(out, exist_ok=True)
    cmd = ["exiftool", "-q", "-fast", "-T", "-Directory", "-FileName", "-Model", "-CreativeStyle", "-DynamicRangeOptimizer",
           "-Contrast", "-Saturation", "-Sharpness", "-PictureEffect", "-Orientation#", "-ISO", "-r", "-ext", "ARW", *folders]
    rows = [l for l in subprocess.run(cmd, capture_output=True, text=True).stdout.splitlines() if "/._" not in l and l.count("\t") == 10]
    with open(os.path.join(out, "index.tsv"), "w") as f:
        f.write("\n".join(rows) + "\n")
    print(f"{len(rows)} ARWs → {out}/index.tsv")


def read_index(out):
    rows = []
    with open(os.path.join(out, "index.tsv")) as f:
        for line in f:
            v = line.rstrip("\n").split("\t")
            if len(v) == len(COLUMNS) and v[3] not in ("-", ""):
                rows.append(dict(zip(COLUMNS, v)))
    return rows


def key(r):
    return hashlib.sha1((r["dir"] + "/" + r["file"]).encode()).hexdigest()[:16]


def sample(rows, per_style):
    """Up to per_style photos per style, spread across shoots, in a fixed order."""
    by = defaultdict(list)
    for r in rows:
        by[r["style"]].append(r)
    out = {}
    for style, rs in by.items():
        rs.sort(key=key)
        shoots = defaultdict(list)
        for r in rs:
            shoots[r["dir"]].append(r)
        picked, i = [], 0
        while len(picked) < per_style and any(i < len(s) for s in shoots.values()):
            for s in shoots.values():
                if i < len(s) and len(picked) < per_style:
                    picked.append(s[i])
            i += 1
        out[style] = picked
    return out


def split(rs):
    """(train, test, how): by shoot when there are two or more shoots, else by file."""
    dirs = sorted({r["dir"] for r in rs}, key=lambda d: hashlib.sha1(d.encode()).hexdigest())
    if len(dirs) >= 2:
        test_dirs = set(dirs[: max(1, len(dirs) // 3)])
        return [r for r in rs if r["dir"] not in test_dirs], [r for r in rs if r["dir"] in test_dirs], "by shoot"
    return [r for r in rs if int(key(r), 16) % 3], [r for r in rs if not int(key(r), 16) % 3], "by file (one shoot)"


def render_all(rs, px, out):
    os.makedirs(os.path.join(out, "renders"), exist_ok=True)
    os.makedirs(os.path.join(out, "camera"), exist_ok=True)
    jobs = []
    for r in rs:
        dst = os.path.join(out, "renders", f"{key(r)}-{px}.tif")
        if not os.path.exists(dst):
            jobs.append({"image": os.path.join(r["dir"], r["file"]), "look": "", "px": px, "out": dst, "space": "srgb"})
        cam = os.path.join(out, "camera", key(r) + ".jpg")
        if not os.path.exists(cam):
            data = subprocess.run(["exiftool", "-b", "-PreviewImage", os.path.join(r["dir"], r["file"])], capture_output=True).stdout
            with open(cam, "wb") as f:
                f.write(data)
    if jobs:
        path = os.path.join(out, "jobs.json")
        with open(path, "w") as f:
            json.dump(jobs, f)
        print(f"rendering {len(jobs)} RAWs at {px} px …", flush=True)
        subprocess.run([RENDER, "batch", path, "--cache", os.path.join(out, "develop-cache")], stdout=subprocess.DEVNULL, check=False)


ORIENT = {1: None, 3: 180, 6: 270, 8: 90}   # EXIF orientation → PIL rotate angle (counter-clockwise)


def blocks(r, px, out):
    """(base, camera) as linear sRGB block means (BLOCKS), or None."""
    from PIL import Image
    try:
        a = Image.open(os.path.join(out, "renders", f"{key(r)}-{px}.tif"))
        b = Image.open(os.path.join(out, "camera", key(r) + ".jpg")).convert("RGB")
    except Exception:
        return None
    ang = ORIENT.get(int(r["orientation"]) if r["orientation"].isdigit() else 1)
    if ang:
        b = b.rotate(ang, expand=True)
    base = np.asarray(a, dtype=np.float64)
    base = base / (65535.0 if base.max() > 255 else 255.0)
    if base.ndim == 2 or base.shape[-1] < 3:
        return None
    base = base[..., :3]

    h, w = base.shape[:2]
    size = BLOCKS if w >= h else BLOCKS[::-1]
    if (b.width >= b.height) != (w >= h):
        return None
    dy, dx = int(h * BORDER), int(w * BORDER)
    bb = base[dy:h - dy, dx:w - dx]
    ys = np.linspace(0, bb.shape[0], size[1] + 1).astype(int)
    xs = np.linspace(0, bb.shape[1], size[0] + 1).astype(int)
    lin = delta_e.decode_srgb(bb)
    base_blocks = np.array([[lin[ys[i]:ys[i + 1], xs[j]:xs[j + 1]].reshape(-1, 3).mean(0) for j in range(size[0])] for i in range(size[1])])
    cam_lin = delta_e.decode_srgb(np.asarray(b, dtype=np.float64) / 255.0)
    ch, cw = cam_lin.shape[:2]
    cy, cx = int(ch * BORDER), int(cw * BORDER)
    cc = cam_lin[cy:ch - cy, cx:cw - cx]
    ys = np.linspace(0, cc.shape[0], size[1] + 1).astype(int)
    xs = np.linspace(0, cc.shape[1], size[0] + 1).astype(int)
    cam_blocks = np.array([[cc[ys[i]:ys[i + 1], xs[j]:xs[j + 1]].reshape(-1, 3).mean(0) for j in range(size[0])] for i in range(size[1])])
    return base_blocks.reshape(-1, 3), cam_blocks.reshape(-1, 3)


def lab(lin):
    return delta_e.to_lab(delta_e.encode_srgb(lin), "srgb")


def de(a_lin, b_lab):
    return delta_e.delta_e2000(lab(a_lin), b_lab)


def fit_style(train, rules, start):
    from scipy.optimize import least_squares
    base = np.concatenate([t[0] for t in train])
    target = lab(np.concatenate([t[1] for t in train]))
    # one weight per photo, so a photo counts the same whatever its block count
    w = np.concatenate([np.full(len(t[0]), 1.0 / np.sqrt(len(t[0]))) for t in train])
    x0 = np.array([start.get(k, lookmath.BASE_RESET[k]) for k in FREE])
    lo = np.array([-1, -2, -0.6, -0.6, -0.6, -0.6, -0.6, -0.6, 0, 0])
    hi = np.array([1, 2, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 1, 1])

    def resid(x):
        m = {**start, **dict(zip(FREE, x))}
        d = lab(lookmath.base_match(base, m, rules)) - target
        return (d * w[:, None]).ravel()

    # Start just inside the bounds, and stop on small steps only: from the identity the default
    # tolerances end the fit after one step.
    x0 = np.clip(x0, lo + 0.01, hi - 0.01)
    r = least_squares(resid, x0, bounds=(lo, hi), loss="soft_l1", f_scale=3.0, max_nfev=400, ftol=1e-10, xtol=1e-10, x_scale="jac")
    return {**start, **{k: round(float(v), 5) for k, v in zip(FREE, r.x)}}


def score(pairs, m, rules):
    """Per photo (median, p95) ΔE2000 of camera vs base and vs base + camera stage."""
    before, after = [], []
    for base, cam in pairs:
        t = lab(cam)
        d0 = delta_e.delta_e2000(lab(base), t)
        d1 = delta_e.delta_e2000(lab(lookmath.base_match(base, m, rules)), t)
        before.append((np.median(d0), np.percentile(d0, 95)))
        after.append((np.median(d1), np.percentile(d1, 95)))
    return np.array(before), np.array(after)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("index"); i.add_argument("folders", nargs="+"); i.add_argument("--out", default=OUT)
    f = sub.add_parser("fit")
    f.add_argument("--out", default=OUT); f.add_argument("--per-style", type=int, default=160); f.add_argument("--px", type=int, default=384)
    f.add_argument("--rules", default=RULES); f.add_argument("--min-train", type=int, default=12)
    f.add_argument("--report", default=os.path.join(HERE, "report"))
    a = p.parse_args(argv)
    if a.cmd == "index":
        return index(a.folders, a.out)

    with open(a.rules) as fh:
        rules = json.load(fh)
    styles = sample(read_index(a.out), a.per_style)
    render_all([r for rs in styles.values() for r in rs], a.px, a.out)
    fitted, lines = {}, []
    lines.append(f"camera profile fit, {a.px} px renders, {BLOCKS[0]}×{BLOCKS[1]} blocks, ΔE2000 per photo (median of medians / median of p95s)")
    lines.append(f"{'style':<10} {'split':<20} {'train':>5} {'test':>4}   {'test: base':>12}   {'test: +camera':>13}   {'train: +camera':>14}")
    for style, rs in sorted(styles.items(), key=lambda kv: -len(kv[1])):
        train_r, test_r, how = split(rs)
        train = [x for x in (blocks(r, a.px, a.out) for r in train_r) if x]
        test = [x for x in (blocks(r, a.px, a.out) for r in test_r) if x]
        if len(train) < a.min_train or not test:
            lines.append(f"{style:<10} {how:<20} {len(train):>5} {len(test):>4}   too few photos, not fitted")
            continue
        m = fit_style(train, rules, dict(lookmath.BASE_RESET))
        fitted[style] = m
        b0, b1 = score(test, m, rules)
        _, t1 = score(train, m, rules)
        lines.append(f"{style:<10} {how:<20} {len(train):>5} {len(test):>4}   {np.median(b0[:, 0]):5.2f} / {np.median(b0[:, 1]):5.2f}   "
                     f"{np.median(b1[:, 0]):5.2f} / {np.median(b1[:, 1]):5.2f}   {np.median(t1[:, 0]):6.2f} / {np.median(t1[:, 1]):5.2f}")
    rule = {st.lower() + RULE_NAME[k]: m[k] for st, m in fitted.items() for k in FREE}
    lines.append("camera stage coefficients: " + json.dumps(rule))
    print("\n".join(lines))
    os.makedirs(a.report, exist_ok=True)
    with open(os.path.join(a.report, "camera-profile.txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
