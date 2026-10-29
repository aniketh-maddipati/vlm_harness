"""F1 clip diagnosis (and F2's meter, F6's estimate) over a list of RAWs.

For each RAW: `lumina-render diagnose` (the app's own measurement: sky mask, Apple's decoder with
highlight recovery on vs off, today's white) writes sky / white / clipped maps; rawclip.py reads
the sensor's own clipping on the same grid. Truth verdict: ≥ 2 % of the sky clipped on any sensor
channel → clipped-at-capture, else ≥ 2 % at white in today's render → recoverable, else fine.

  python f1.py --list raws.txt --out ~/LuminaEvidence/skyeval/f1 [--workers 3]

Writes <out>/rows.jsonl (one line per photo) and <out>/<stem>/{sky,white,clipped}.png.
"""
import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rawclip  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")
CLIPPED_AT_LEAST = WHITE_AT_LEAST = 0.02


def verdict(clipped, white):
    if clipped is None:
        return None
    return "clipped-at-capture" if clipped >= CLIPPED_AT_LEAST else "recoverable" if white >= WHITE_AT_LEAST else "fine"


def stops_over_truth(sky, p):
    """F6 reference: in the sky's clipped cells, estimate each clipped channel from an unclipped one
    with the sky's own channel ratios (from its unclipped cells), then the stops that put the 90th
    percentile at 0.9 × white. ('>=', x) when every channel clipped (only a lower bound)."""
    s = sky >= 0.5
    clip = {k: p[k] >= 0.5 for k in "rgb"}
    anyc = clip["r"] | clip["g"] | clip["b"]
    cells = s & anyc
    if cells.sum() < 16:
        return None
    free = s & ~anyc
    if free.sum() < 16:
        return [">=", float(np.log2(1 / 0.9))]
    lv = {k: p["l" + k] for k in "rgb"}
    ratio = {(a, b): float(np.median(lv[a][free] / np.maximum(lv[b][free], 1e-4))) for a in "rgb" for b in "rgb" if a != b}
    est = np.zeros(cells.sum())
    allc = np.ones(cells.sum(), bool)
    for k in "rgb":
        ck = clip[k][cells]
        e = lv[k][cells].copy()
        for ref in "rgb":
            if ref == k:
                continue
            ok = ~clip[ref][cells]
            e = np.where(ck & ok, np.maximum(e, lv[ref][cells] * ratio[(k, ref)]), e)
        est = np.maximum(est, e)
        allc &= ck
    v = float(np.percentile(est, 90))
    bound = allc.mean() > 0.5
    stops = float(np.log2(max(v, 1e-6) / 0.9))
    return [">=" if bound else "=", stops]


def one(args):
    path, out = args
    stem = os.path.splitext(os.path.basename(path))[0]
    d = os.path.join(out, stem)
    try:
        r = subprocess.run([RENDER, "diagnose", path, "--out-dir", d], capture_output=True, text=True, timeout=180)
        row = json.loads(r.stdout.strip().splitlines()[-1])
    except Exception as e:  # noqa: BLE001
        return {"image": path, "error": str(e)}
    row["stem"] = stem
    sky_png = os.path.join(d, "sky.png")
    if not os.path.exists(sky_png):
        row["truth"] = "no-sky"
        return row
    sky = np.asarray(Image.open(sky_png).convert("L"), np.float32) / 255
    white = np.asarray(Image.open(os.path.join(d, "white.png")).convert("L"), np.float32) / 255
    try:
        p = rawclip.planes(path, *sky.shape)
    except Exception as e:  # noqa: BLE001
        row["truthError"] = str(e)
        return row
    wq = np.asarray(Image.fromarray(white).resize(sky.shape[::-1], Image.BOX), np.float32)
    tot = float(sky.sum())
    share = lambda m: float((sky * m).sum() / tot)  # noqa: E731
    ch = {k: share(p[k]) for k in "rgb"}
    anyc = np.maximum(np.maximum(p["r"], p["g"]), p["b"])
    row["truthClipped"] = share(anyc)
    row["truthChannels"] = ch
    row["truthWhite"] = share(wq)
    row["truth"] = verdict(row["truthClipped"], row["truthWhite"])
    row["truthStops"] = stops_over_truth(sky, p)
    # sky brightness in the RAW: the sky's 99th percentile level per channel (headroom)
    s = sky >= 0.5
    row["skyLevelP99"] = {k: float(np.percentile(p["l" + k][s], 99)) for k in "rgb"} if s.sum() >= 16 else None
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()
    out = os.path.expanduser(a.out)
    os.makedirs(out, exist_ok=True)
    paths = [l.strip() for l in open(a.list) if l.strip()]
    rows_path = os.path.join(out, "rows.jsonl")
    done = set()
    if os.path.exists(rows_path):
        done = {json.loads(l)["image"] for l in open(rows_path)}
    todo = [(p, out) for p in paths if p not in done]
    with open(rows_path, "a") as f, ProcessPoolExecutor(a.workers) as ex:
        for i, row in enumerate(ex.map(one, todo)):
            f.write(json.dumps(row) + "\n")
            f.flush()
            print(f"{i + 1}/{len(todo)} {os.path.basename(row['image'])} {row.get('verdict')} / {row.get('truth')}", flush=True)


if __name__ == "__main__":
    main()
