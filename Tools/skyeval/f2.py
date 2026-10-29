"""F2 highlight-safe auto exposure, scored against Lightroom Exposure in someone's own edits.

Each RAW is metered once (`lumina-render diagnose`: median luma of what is not sky, white or
black in the look-free develop). The meter's one constant, the target midtone L*, is fitted on a
development set (the bridal-shower edits) and then frozen; the held-out set (mehendi) is scored
with it: |predicted ev − the photographer's Exposure| in stops, median and p90. Baselines: ev 0
for every photo, and the development set's median Exposure for every photo.

  python f2.py --dev ~/LuminaEvidence/parity-bridal-edits --held ~/LuminaEvidence/parity-personal --out ~/LuminaEvidence/skyeval/f2
"""
import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "parity"))
import lookmath  # noqa: E402

RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")
RULES = json.load(open(os.path.join(HERE, "..", "..", "Lumina", "Sets", "Look", "rules-v1.json")))


def edits(root):
    cfg = json.load(open(os.path.join(root, "config.json")))
    refs = json.load(open(os.path.join(root, "refs.json")))["refs"]
    out = {}
    for r in refs:
        if r.get("kind") != "edit":
            continue
        stem = r["id"].split("__")[0]
        if stem in out:                       # first edit of a photo only
            continue
        look = lookmath.parse_look(r["look"])
        raw = os.path.join(cfg["raws"], stem + ".ARW")
        if os.path.exists(raw):
            out[stem] = {"raw": raw, "ev": float(look.get("ev", 0.0)), "bucket": r.get("bucket")}
    return out


def meter(raw, cache):
    p = os.path.join(cache, os.path.basename(raw) + ".json")
    if os.path.exists(p):
        return json.load(open(p))
    r = subprocess.run([RENDER, "diagnose", raw], capture_output=True, text=True, timeout=300)
    d = json.loads(r.stdout.strip().splitlines()[-1])
    json.dump(d, open(p, "w"))
    return d


def y_of_lstar(L):
    return ((L + 16) / 116) ** 3 if L > 8 else L * 27 / 24389


def lstar(y):
    y = max(0.0, y)
    return 116 * y ** (1 / 3) - 16 if y > 216 / 24389 else y * 24389 / 27


def ev_for(midtone, target):
    """The same bisection LookSky.meter does, through lookmath's exposure stage."""
    y = y_of_lstar(midtone)
    f = lambda ev: lstar(float(lookmath.exposure(np.array(y), ev, RULES)))  # noqa: E731
    lo, hi = -3.0, 3.0
    if f(lo) >= target:
        return lo
    if f(hi) <= target:
        return hi
    for _ in range(40):
        m = (lo + hi) / 2
        lo, hi = (m, hi) if f(m) < target else (lo, m)
    return round((lo + hi) / 2 * 20) / 20


def table(rows, target, label):
    err = np.array([abs(ev_for(r["midtone"], target) - r["ev"]) for r in rows])
    return {"set": label, "n": len(rows), "median": float(np.median(err)), "p90": float(np.percentile(err, 90)), "mean": float(err.mean())}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dev", required=True)
    ap.add_argument("--held", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = os.path.expanduser(a.out)
    cache = os.path.join(out, "meter")
    os.makedirs(cache, exist_ok=True)
    sets = {}
    for name, root in (("dev", a.dev), ("held", a.held)):
        e = edits(os.path.expanduser(root))
        with ThreadPoolExecutor(4) as ex:
            ms = list(ex.map(lambda s: (s, meter(e[s]["raw"], cache)), sorted(e)))
        rows = []
        for s, m in ms:
            if "meter" in m:
                rows.append({"stem": s, "ev": e[s]["ev"], "midtone": m["meter"]["midtone"], "metered": m["meter"]["metered"], "sky": m.get("sky", 0), "bucket": e[s]["bucket"]})
        sets[name] = rows
        print(name, len(e), "edits,", len(rows), "metered")
    grid = np.arange(30, 70.01, 0.5)
    dev_err = [np.median([abs(ev_for(r["midtone"], t) - r["ev"]) for r in sets["dev"]]) for t in grid]
    target = float(grid[int(np.argmin(dev_err))])
    res = {"target": target, "devCurve": dict(zip(map(float, grid), map(float, dev_err)))}
    res["dev"] = table(sets["dev"], target, "dev (bridal)")
    res["held"] = table(sets["held"], target, "held-out (mehendi)")
    for k in ("dev", "held"):
        evs = np.array([r["ev"] for r in sets[k]])
        res[k]["baselineZero"] = {"median": float(np.median(np.abs(evs))), "p90": float(np.percentile(np.abs(evs), 90))}
    dev_med = float(np.median([r["ev"] for r in sets["dev"]]))
    evs = np.array([r["ev"] for r in sets["held"]])
    res["held"]["baselineDevMedian"] = {"ev": dev_med, "median": float(np.median(np.abs(evs - dev_med))), "p90": float(np.percentile(np.abs(evs - dev_med), 90))}
    res["held"]["corr"] = float(np.corrcoef([ev_for(r["midtone"], target) for r in sets["held"]], evs)[0, 1])
    json.dump({"result": res, "rows": sets}, open(os.path.join(out, "f2.json"), "w"), indent=1)
    print(json.dumps({k: v for k, v in res.items() if k != "devCurve"}, indent=1))


if __name__ == "__main__":
    main()
