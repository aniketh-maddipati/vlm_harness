#!/usr/bin/env python3
"""Scores automatic masks against sparse hand labels (Tools/masklab/README.md). Numbers only.

  score.py RUN [RUN…] [--labels DIR] [--tolerance PX] [--still-iou 0.95] [--still-gap 30]
           [--out report.json] [--quiet]

A RUN is one tracker's output: a folder with one subfolder per clip (named by the clip's file
stem), each holding one mask per frame (`000123.png`) and `timing.json` from masklab-track.
A RUN may also be a single clip folder. Labels live in DIR/<clip>/<frame>.png; the frame number is
the file's stem as an integer, so `120.png` and `000120.png` are the same frame. Masks are 8-bit
PNGs, a pixel >= 128 is in the mask. A run mask of another size than its label is resampled to the
label's size (nearest neighbour) before it is compared.

Per clip it reports, on the labelled frames only:
  iou          mean IoU (a labelled frame the run has no mask for counts as an empty mask)
  slope100     IoU change per 100 frames (least squares over the labelled frames): drift
  last10       mean IoU of the labelled frames in the last 10 % of the run's frames
  bf           boundary F-score: boundary pixels matched within --tolerance pixels
  flicker      mean changed area between consecutive run masks, relative to the mask's area,
               inside stretches where the label barely changes (two labelled frames at most
               --still-gap apart whose labels have IoU >= --still-iou)
and on every frame, labels or not:
  flicker_all  the same change over every consecutive pair (real motion counts too)
  fps          frames / wall-clock seconds from timing.json, and the per-frame work's median / p95
"""
import argparse, json, math, os, re, sys

import numpy as np

try:
    from PIL import Image
except ImportError:  # Pillow is in Tools/parity/requirements.txt
    Image = None

FRAME = re.compile(r"^(\d+)\.png$", re.IGNORECASE)


# ——— reading

def load_mask(path):
    """A PNG as a bool array: luma >= 128 is in. RGBA is read through its luma, like any editor's
    white-on-black export."""
    if Image is None:
        sys.exit("score.py: needs Pillow (pip install -r Tools/parity/requirements.txt)")
    with Image.open(path) as im:
        return np.asarray(im.convert("L")) >= 128


def frame_files(folder):
    """frame number → path for every NNN.png in folder."""
    out = {}
    if not os.path.isdir(folder):
        return out
    for name in os.listdir(folder):
        m = FRAME.match(name)
        if m:
            out[int(m.group(1))] = os.path.join(folder, name)
    return out


def resize_nearest(mask, shape):
    if mask.shape == shape:
        return mask
    h, w = shape
    ys = (np.arange(h) * mask.shape[0] / h).astype(int)
    xs = (np.arange(w) * mask.shape[1] / w).astype(int)
    return mask[ys][:, xs]


def load_timing(folder):
    path = os.path.join(folder, "timing.json")
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        return json.load(f)


# ——— measures

def iou(a, b):
    union = np.logical_or(a, b).sum()
    if union == 0:
        return 1.0  # both empty: the run agrees that nothing is there
    return float(np.logical_and(a, b).sum() / union)


def _shift(m, dy, dx):
    """m moved by (dy, dx), zeros where it moved in from outside."""
    out = np.zeros_like(m)
    h, w = m.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = m[ys, xs]
    return out


def boundary(m):
    """Pixels of m with a 4-neighbour outside m (the image edge counts as outside)."""
    if not m.any():
        return m.copy()
    inner = m.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        inner &= _shift(m, dy, dx)
    return m & ~inner


def dilate(m, radius):
    """m grown by a disc of `radius` pixels."""
    if radius <= 0:
        return m.copy()
    out = m.copy()
    r = int(math.floor(radius))
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if (dy or dx) and dy * dy + dx * dx <= radius * radius:
                out |= _shift(m, dy, dx)
    return out


def boundary_f(pred, label, tolerance):
    """Boundary F-score: a boundary pixel of one mask counts when the other's boundary passes within
    `tolerance` pixels. The same measure as DAVIS's F (Perazzi et al. 2016), written from its
    definition; a disc dilation stands in for the distance transform."""
    bp, bl = boundary(pred), boundary(label)
    np_, nl = int(bp.sum()), int(bl.sum())
    if np_ == 0 and nl == 0:
        return 1.0
    if np_ == 0 or nl == 0:
        return 0.0
    precision = float((bp & dilate(bl, tolerance)).sum() / np_)
    recall = float((bl & dilate(bp, tolerance)).sum() / nl)
    if precision + recall == 0:
        return 0.0
    return 2 * precision * recall / (precision + recall)


def change(a, b):
    """Area that changed between two masks, relative to their mean area (0 = identical, 2 = disjoint).
    Relative, so a small object that loses half its pixels counts as much as a large one."""
    mean_area = (a.sum() + b.sum()) / 2
    if mean_area == 0:
        return 0.0
    return float(np.logical_xor(a, b).sum() / mean_area)


def slope(xs, ys):
    """Least-squares slope of ys over xs, or None with fewer than two distinct xs."""
    if len(xs) < 2 or len(set(xs)) < 2:
        return None
    x = np.asarray(xs, float)
    y = np.asarray(ys, float)
    x -= x.mean()
    return float((x * (y - y.mean())).sum() / (x * x).sum())


def percentile(values, q):
    return float(np.percentile(np.asarray(values, float), q)) if values else None


# ——— one clip

def score_clip(run_dir, label_dir, tolerance=3.0, still_iou=0.95, still_gap=30):
    masks = frame_files(run_dir)
    labels = frame_files(label_dir) if label_dir else {}
    timing = load_timing(run_dir)
    out = {"frames": len(masks), "labelled": 0, "missing": 0, "empty": 0}
    cache = {}

    def run_mask(n, shape=None):
        if n not in masks:
            return None
        if n not in cache:
            cache[n] = load_mask(masks[n])
        m = cache[n]
        return resize_nearest(m, shape) if shape is not None else m

    frames = sorted(masks)
    out["empty"] = sum(1 for n in frames if not run_mask(n).any())

    # Flicker over every consecutive pair the run wrote.
    all_changes = [change(run_mask(a), run_mask(b)) for a, b in zip(frames, frames[1:]) if b == a + 1]
    out["flicker_all"] = float(np.mean(all_changes)) if all_changes else None

    # Labelled frames: only those inside the run's span are scored (a run that started later or
    # stopped early is not charged for frames it was never asked about).
    lo, hi = (frames[0], frames[-1]) if frames else (None, None)
    if timing and "start_frame" in timing:
        lo = timing["start_frame"]
        if timing.get("frames"):
            hi = lo + int(timing["frames"]) - 1
    scored = [n for n in sorted(labels) if lo is not None and lo <= n <= hi]
    per_frame = []
    label_cache = {}
    for n in scored:
        lab = label_cache.setdefault(n, load_mask(labels[n]))
        pred = run_mask(n, lab.shape)
        if pred is None:
            out["missing"] += 1
            pred = np.zeros_like(lab)
        per_frame.append({"frame": n, "iou": iou(pred, lab), "bf": boundary_f(pred, lab, tolerance)})
    out["labelled"] = len(per_frame)
    out["per_frame"] = per_frame
    if per_frame:
        ious = [p["iou"] for p in per_frame]
        out["iou"] = float(np.mean(ious))
        s = slope([p["frame"] for p in per_frame], ious)
        out["slope100"] = s * 100 if s is not None else None
        cut = lo + 0.9 * (hi - lo)
        tail = [p["iou"] for p in per_frame if p["frame"] >= cut]
        out["last10"] = float(np.mean(tail)) if tail else None
        out["bf"] = float(np.mean([p["bf"] for p in per_frame]))
    else:
        out.update(iou=None, slope100=None, last10=None, bf=None)

    # Flicker where the label holds still: between neighbouring labelled frames whose labels agree.
    still = []
    for a, b in zip(scored, scored[1:]):
        if b - a > still_gap or iou(label_cache[a], label_cache[b]) < still_iou:
            continue
        for n in range(a, b):
            if n in masks and n + 1 in masks:
                still.append(change(run_mask(n), run_mask(n + 1)))
    out["flicker"] = float(np.mean(still)) if still else None
    out["still_pairs"] = len(still)

    if timing:
        n = int(timing.get("frames") or len(frames))
        total = timing.get("total_ms")
        work = timing.get("per_frame_ms") or []
        out["fps"] = n / (total / 1000) if total else None
        out["work_ms_median"] = percentile(work, 50)
        out["work_ms_p95"] = percentile(work, 95)
        out["device"] = timing.get("device")
        out["tracker"] = timing.get("tracker")
    else:
        out.update(fps=None, work_ms_median=None, work_ms_p95=None)
    return out


# ——— a run and the report

def clip_dirs(run):
    """clip name → folder. A folder holding masks or timing.json is one clip; otherwise each
    subfolder is."""
    if load_timing(run) is not None or frame_files(run):
        return {os.path.basename(os.path.normpath(run)): run}
    return {d: os.path.join(run, d) for d in sorted(os.listdir(run)) if os.path.isdir(os.path.join(run, d))}


def score_runs(runs, labels=None, tolerance=3.0, still_iou=0.95, still_gap=30):
    report = {"version": 1, "tolerance_px": tolerance, "still_iou": still_iou, "still_gap": still_gap,
              "labels": labels, "runs": []}
    for run in runs:
        entry = {"run": os.path.basename(os.path.normpath(run)), "path": run, "clips": {}}
        for clip, folder in clip_dirs(run).items():
            label_dir = os.path.join(labels, clip) if labels else None
            entry["clips"][clip] = score_clip(folder, label_dir, tolerance, still_iou, still_gap)
        report["runs"].append(entry)
    return report


def fmt(v, spec):
    return "—" if v is None else format(v, spec)


def table(report):
    head = f"{'run':<16} {'clip':<22} {'lab':>4} {'IoU':>6} {'Δ/100f':>7} {'last10':>6} {'BF':>6} {'flick':>6} {'flickAll':>8} {'fps':>6} {'empty':>5}"
    lines = [head, "-" * len(head)]
    for run in report["runs"]:
        for clip, c in run["clips"].items():
            lines.append(
                f"{run['run'][:16]:<16} {clip[:22]:<22} {c['labelled']:>4} {fmt(c['iou'], '.3f'):>6} "
                f"{fmt(c['slope100'], '+.3f'):>7} {fmt(c['last10'], '.3f'):>6} {fmt(c['bf'], '.3f'):>6} "
                f"{fmt(c['flicker'], '.3f'):>6} {fmt(c['flicker_all'], '.3f'):>8} {fmt(c['fps'], '.1f'):>6} "
                f"{c['empty']:>5}")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+", help="tracker output folders (one subfolder per clip)")
    ap.add_argument("--labels", help="labels root: <clip>/<frame>.png")
    ap.add_argument("--tolerance", type=float, default=3.0, help="boundary tolerance in label pixels (3)")
    ap.add_argument("--still-iou", type=float, default=0.95, help="labels this alike count as still (0.95)")
    ap.add_argument("--still-gap", type=int, default=30, help="labelled frames at most this far apart (30)")
    ap.add_argument("--out", help="write the JSON report here")
    ap.add_argument("--quiet", action="store_true", help="no table")
    a = ap.parse_args(argv)
    labels = a.labels if a.labels and os.path.isdir(a.labels) else None
    report = score_runs(a.runs, labels, a.tolerance, a.still_iou, a.still_gap)
    if a.out:
        with open(a.out, "w") as f:
            json.dump(report, f, indent=1)
    if not a.quiet:
        print(table(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
