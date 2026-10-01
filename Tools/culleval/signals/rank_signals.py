#!/usr/bin/env python3
"""Which signal tells the picked frame from the ones passed over, inside a row?

    python3 Tools/culleval/signals/rank_signals.py --signals signals.jsonl --out signals-report.md labeled.json

`labeled.json` is what `Tools/culleval/culleval-app.mjs --out` writes: the photos of the probe's
dumps on days with a pick, each with its `pool` and whether it was picked.

Each candidate (signals.swift's Vision / sharpness numbers, lumina-core's own `focus`, and
shooting-order cues from the capture times) is scored the way the choice is made: inside a
group of similar frames, does it put the pick above a frame that was not picked?

- **pair accuracy** (a within-group AUC): over every (pick, non-pick) pair in the same group,
  how often the signal is higher for the pick. 50 % is a coin; the interval is a bootstrap over
  groups. Scored only on pairs where both frames have the signal (a face signal needs faces).
- **top-1**: how often the frame the signal ranks first is a pick, next to chance for the group.
- groups are lumina-core's **rows**, and **runs**: consecutive frames at most `--run-gap`
  seconds apart inside a row (retakes of one picture).
- **combined**: a logistic model on the signals standardised inside each row, trained on all
  days but one and scored on the day held out, so it can't memorise a shoot.

Numbers only; no file names are written.
"""
import argparse
import collections
import json
import math
import random
import sys

# name → (key, direction): +1 when more should mean "pick".
SIGNALS = collections.OrderedDict([
    ("lumina focus (today's rank)", ("focus", 1)),
    ("sharpness, whole frame", ("sharpAll", 1)),
    ("sharpness, centre", ("sharpCentre", 1)),
    ("sharpness, salient subject", ("sharpSalient", 1)),
    ("sharpness, largest face", ("sharpFace", 1)),
    ("face capture quality, main face", ("faceQMain", 1)),
    ("face capture quality, worst face", ("faceQMin", 1)),
    ("face capture quality, mean", ("faceQMean", 1)),
    ("eyes open, least open face", ("eyeOpenMin", 1)),
    ("smiling faces (share)", ("smiles", 1)),
    ("blinking faces (share)", ("blinks", -1)),
    ("aesthetics score", ("aesthetic", 1)),
    ("face size", ("faceArea", 1)),
    ("faces in frame", ("faces", 1)),
    ("clipped highlights", ("clipHi", -1)),
    ("clipped on the face", ("clipFace", -1)),
    ("later in the row", ("posRow", 1)),
    ("later in its run", ("posRun", 1)),
    ("last frame of its run", ("lastOfRun", 1)),
    ("pause after the frame (s)", ("gapAfter", 1)),
])


def seconds(p):
    h, m, s = (int(x) for x in p["sec"].split(":"))
    y, mo, d = (int(x) for x in p["date"].split("-"))
    return ((y * 372 + mo * 31 + d) * 86400) + h * 3600 + m * 60 + s


def add_order(photos, run_gap):
    """Shooting-order cues, and the run (retakes ≤ run_gap s apart inside a row) of each photo."""
    rows = collections.defaultdict(list)
    for p in photos:
        rows[(p["pool"], p["row"])].append(p)
    for key, r in rows.items():
        r.sort(key=lambda p: p["n"])
        run = 0
        for i, p in enumerate(r):
            t = seconds(p)
            if i and t - seconds(r[i - 1]) > run_gap:
                run += 1
            p["run"] = (key, run)
            p["posRow"] = i / max(1, len(r) - 1)
            p["gapAfter"] = min(600, seconds(r[i + 1]) - t) if i + 1 < len(r) else 600
        runs = collections.defaultdict(list)
        for p in r:
            runs[p["run"]].append(p)
        for g in runs.values():
            for i, p in enumerate(g):
                p["posRun"] = i / max(1, len(g) - 1) if len(g) > 1 else None
                p["lastOfRun"] = 1.0 if i == len(g) - 1 else 0.0
                p["runLen"] = len(g)


def groups_of(photos, by):
    g = collections.defaultdict(list)
    for p in photos:
        g[(p["pool"], p["row"]) if by == "row" else p["run"]].append(p)
    # Only groups with a real choice: something picked and something passed over.
    return [x for x in g.values() if any(p["pick"] for p in x) and not all(p["pick"] for p in x)]


def pair_stats(group, key, sign):
    """(wins, pairs) over (pick, non-pick) pairs where both have the signal; ties count half."""
    a = [sign * p[key] for p in group if p["pick"] and p.get(key) is not None]
    b = [sign * p[key] for p in group if not p["pick"] and p.get(key) is not None]
    w = sum((x > y) + 0.5 * (x == y) for x in a for y in b)
    return w, len(a) * len(b)


def evaluate(groups, key, sign, rng, boots=400):
    per = [pair_stats(g, key, sign) for g in groups]
    per = [(w, n) for w, n in per if n]
    pairs = sum(n for _, n in per)
    if not pairs:
        return None
    acc = sum(w for w, _ in per) / pairs
    bs = []
    for _ in range(boots):
        s = [per[rng.randrange(len(per))] for _ in per]
        bs.append(sum(w for w, _ in s) / sum(n for _, n in s))
    bs.sort()
    # top-1: the best-scoring frame is a pick, in groups where every frame has the signal
    hit = chance = n = 0
    for g in groups:
        if any(p.get(key) is None for p in g):
            continue
        best = max(sign * p[key] for p in g)
        top = [p for p in g if sign * p[key] == best]
        hit += sum(p["pick"] for p in top) / len(top)
        chance += sum(p["pick"] for p in g) / len(g)
        n += 1
    return {"acc": acc, "lo": bs[int(0.025 * boots)], "hi": bs[int(0.975 * boots) - 1], "groups": len(per), "pairs": pairs,
            "top1": hit / n if n else None, "chance": chance / n if n else None, "top1Groups": n}


# MARK: the combined model (pure Python: no numpy on the system interpreter)

def standardise(photos, keys):
    """Each signal as a z-score inside its row; missing → 0 (the row's mean)."""
    rows = collections.defaultdict(list)
    for p in photos:
        rows[(p["pool"], p["row"])].append(p)
    for r in rows.values():
        for k, sign in keys:
            v = [p[k] for p in r if p.get(k) is not None]
            m = sum(v) / len(v) if v else 0
            sd = math.sqrt(sum((x - m) ** 2 for x in v) / len(v)) if len(v) > 1 else 0
            for p in r:
                p.setdefault("z", {})[k] = sign * (p[k] - m) / sd if p.get(k) is not None and sd > 0 else 0.0


def fit(train, keys, steps=300, lr=0.5, l2=0.01):
    w = [0.0] * len(keys)
    b = 0.0
    X = [[p["z"][k] for k, _ in keys] for p in train]
    y = [1.0 if p["pick"] else 0.0 for p in train]
    n = len(X)
    for _ in range(steps):
        gw, gb = [0.0] * len(keys), 0.0
        for xi, yi in zip(X, y):
            z = b + sum(wj * xj for wj, xj in zip(w, xi))
            e = 1 / (1 + math.exp(-max(-30, min(30, z)))) - yi
            gb += e
            for j, xj in enumerate(xi):
                gw[j] += e * xj
        w = [wj - lr * (gj / n + l2 * wj) for wj, gj in zip(w, gw)]
        b -= lr * gb / n
    return w, b


def combined(photos, keys, by, rng):
    """Leave one day out: train on the others, write `model` on the held-out day's photos."""
    standardise(photos, keys)
    days = sorted({p["date"] for p in photos})
    weights = []
    for d in days:
        train = [p for p in photos if p["date"] != d]
        w, b = fit(train, keys)
        weights.append(w)
        for p in photos:
            if p["date"] == d:
                p["model"] = b + sum(wj * p["z"][k] for wj, (k, _) in zip(w, keys))
    mean_w = [sum(w[j] for w in weights) / len(weights) for j in range(len(keys))]
    return evaluate(groups_of(photos, by), "model", 1, rng), mean_w


def pct(v):
    return "–" if v is None else f"{100 * v:.0f} %"


def table(photos, by, rng):
    G = groups_of(photos, by)
    rows = []
    for name, (key, sign) in SIGNALS.items():
        r = evaluate(G, key, sign, rng)
        if r:
            rows.append((name, r))
    rows.sort(key=lambda x: -x[1]["acc"])
    L = [f"{len(G)} {by}s with a real choice (mean {sum(len(g) for g in G) / max(1, len(G)):.1f} frames).", "",
         "| signal | pair accuracy | 95 % interval | groups | top-1 is a pick | chance |", "|---|---:|---:|---:|---:|---:|"]
    for name, r in rows:
        L.append(f"| {name} | {pct(r['acc'])} | {pct(r['lo'])} – {pct(r['hi'])} | {r['groups']} | {pct(r['top1'])} | {pct(r['chance'])} |")
    return L, rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("labeled", nargs="+")
    ap.add_argument("--signals", required=True)
    ap.add_argument("--out")
    ap.add_argument("--run-gap", type=float, default=4.0)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args(argv)
    rng = random.Random(a.seed)
    sig = {}
    with open(a.signals) as f:
        for line in f:
            r = json.loads(line)
            sig[r.pop("id")] = r
    photos = []
    for path in a.labeled:
        photos += json.load(open(path))["photos"]
    have = 0
    for p in photos:
        s = sig.get(p["path"])
        if s:
            have += 1
            p.update({k: v for k, v in s.items() if k not in ("lum",)})
    add_order(photos, a.run_gap)
    L = ["# Which signal finds the pick inside a group of similar frames?", "",
         f"{len(photos)} photos, {sum(p['pick'] for p in photos)} picks, signals for {have}. Pair accuracy: how often the signal is higher for "
         "the pick than for a frame passed over in the same group (50 % = a coin).", "", "## Inside a row", ""]
    t, _ = table(photos, "row", rng)
    L += t
    L += ["", f"## Inside a run (retakes at most {a.run_gap:g} s apart)", ""]
    t, _ = table(photos, "run", rng)
    L += t
    keys = [SIGNALS[n] for n in ("sharpness, salient subject", "sharpness, largest face", "face capture quality, main face", "eyes open, least open face",
                                 "smiling faces (share)", "aesthetics score", "face size", "clipped highlights", "later in its run", "pause after the frame (s)")]
    L += ["", "## Combined (trained on the other days, scored on the day held out)", ""]
    for by in ("row", "run"):
        r, w = combined(photos, keys, by, rng)
        if r:
            L.append(f"- inside a {by}: pair accuracy {pct(r['acc'])} ({pct(r['lo'])} – {pct(r['hi'])}), top-1 {pct(r['top1'])} vs chance {pct(r['chance'])}.")
    L += ["", "Mean weights (per standard deviation inside a row): " + ", ".join(f"{k} {x:+.2f}" for (k, _), x in sorted(zip(keys, w), key=lambda t: -abs(t[1])))]
    with_faces = sum(1 for p in photos if p.get("faces"))
    L += ["", f"Photos with a face: {pct(with_faces / max(1, len(photos)))}; picks with a face: {pct(sum(1 for p in photos if p['pick'] and p.get('faces')) / max(1, sum(p['pick'] for p in photos)))}."]
    text = "\n".join(L) + "\n"
    if a.out:
        with open(a.out, "w") as f:
            f.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
