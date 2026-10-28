#!/usr/bin/env python3
"""Healer × set table from heal_score.py reports: one row per healer and hole mode.

    python3 Tools/masklab/heal_table.py SCORES_DIR [--out DIR_OF_FPS] [--md]

SCORES_DIR holds <healer>-<mode>-<clip>.json (heal_score.py --report). Per row: clips, the mean over clips of each
clip's mean PSNR, SSIM, flicker and seam, the p10 over clips of PSNR and SSIM and the p90 of flicker and seam (the
worst clips), and fps from <out>/<healer>-<mode>/fps.txt (frames / wall seconds per clip, mean) when --out is given.
"""
import argparse, glob, json, os, re

import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scores")
    ap.add_argument("--out")
    ap.add_argument("--md", action="store_true")
    a = ap.parse_args()
    rows = {}
    for p in glob.glob(os.path.join(a.scores, "*.json")):
        name = os.path.basename(p)[:-5]
        m = re.match(r"^(skim-plate|lama|migan|propainter|flow-lama)-(moving|still|real|cars)-(.+)$", name)
        if not m:
            continue
        r = json.load(open(p))
        rows.setdefault((m.group(1), m.group(2)), []).append(r)
    head = ["healer", "holes", "clips", "PSNR", "p10", "SSIM", "p10", "flicker", "p90", "seam", "p90", "fps"]
    lines = []
    for (h, mode), rs in sorted(rows.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        col = lambda k: np.array([r[k] for r in rs if r.get(k) is not None and np.isfinite(r[k])], float)
        fps = None
        if a.out and os.path.exists(os.path.join(a.out, f"{h}-{mode}", "fps.txt")):
            v = [float(l.split()[2]) for l in open(os.path.join(a.out, f"{h}-{mode}", "fps.txt")) if len(l.split()) == 3]
            fps = float(np.mean(v)) if v else None
        f = lambda x, d=2: "—" if x is None or (isinstance(x, float) and not np.isfinite(x)) else f"{x:.{d}f}"
        ps, ss, fl, se = col("psnr"), col("ssim"), col("flicker"), col("seam")
        q = lambda x, p: float(np.percentile(x, p)) if len(x) else None
        mean = lambda x: float(x.mean()) if len(x) else None
        lines.append([h, mode, str(len(rs)), f(mean(ps)), f(q(ps, 10)), f(mean(ss), 3), f(q(ss, 10), 3),
                      f(mean(fl)), f(q(fl, 90)), f(mean(se)), f(q(se, 90)), f(fps, 1)])
    if a.md:
        print("| " + " | ".join(head) + " |")
        print("|" + "---|" * len(head))
        for l in lines:
            print("| " + " | ".join(l) + " |")
    else:
        w = [max(len(head[i]), *(len(l[i]) for l in lines)) for i in range(len(head))] if lines else [len(x) for x in head]
        print("  ".join(head[i].ljust(w[i]) for i in range(len(head))))
        for l in lines:
            print("  ".join(l[i].ljust(w[i]) for i in range(len(head))))


if __name__ == "__main__":
    main()
