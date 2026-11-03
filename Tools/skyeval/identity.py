"""All features off → bit-identical renders. Renders the held-out set's looks (no sky tokens) with
a lumina-render built from main and with this checkout's, LUMINA_SKY unset and set, and compares
the TIFF pixel bytes.

  python identity.py --main /path/to/main/lumina-render --root ~/LuminaEvidence/parity-personal --out ~/LuminaEvidence/skyeval/identity [--limit 40]
"""
import argparse
import hashlib
import json
import os
import subprocess

import numpy as np
import tifffile

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER = os.path.join(HERE, "..", "parity", "lumina-render", ".build", "release", "lumina-render")


def run(binary, jobs, env):
    subprocess.run([binary, "batch", jobs, "--no-cache"], env={**os.environ, **env}, stdout=subprocess.DEVNULL, check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--main", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=40)
    a = ap.parse_args()
    root, out = os.path.expanduser(a.root), os.path.expanduser(a.out)
    cfg = json.load(open(os.path.join(root, "config.json")))
    refs = [r for r in json.load(open(os.path.join(root, "refs.json")))["refs"] if r.get("kind") == "edit"][: a.limit]
    variants = {"main": (a.main, {}), "this-off": (RENDER, {}), "this-on": (RENDER, {"LUMINA_SKY": "1"})}
    for name, (binary, env) in variants.items():
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        jobs = [{"image": os.path.join(cfg["raws"], r["id"].split("__")[0] + ".ARW"), "look": r["look"], "px": 1024, "space": "srgb",
                 "out": os.path.join(d, r["id"] + ".tif")} for r in refs]
        json.dump(jobs, open(os.path.join(d, "jobs.json"), "w"))
        run(binary, os.path.join(d, "jobs.json"), env)
    res = []
    for r in refs:
        px = {}
        for name in variants:
            p = os.path.join(out, name, r["id"] + ".tif")
            px[name] = tifffile.imread(p) if os.path.exists(p) else None
        row = {"id": r["id"]}
        for name in ("this-off", "this-on"):
            if px["main"] is None or px[name] is None:
                row[name] = "missing"
            else:
                same = px["main"].shape == px[name].shape and np.array_equal(px["main"], px[name])
                row[name] = "identical" if same else f"max|Δ| {int(np.abs(px['main'].astype(np.int64) - px[name].astype(np.int64)).max())} / 65535"
        res.append(row)
    summary = {k: sum(1 for r in res if r[k] == "identical") for k in ("this-off", "this-on")}
    summary["n"] = len(res)
    json.dump({"summary": summary, "rows": res}, open(os.path.join(out, "identity.json"), "w"), indent=1)
    print(json.dumps(summary))
    for r in res:
        if r["this-off"] != "identical" or r["this-on"] != "identical":
            print(r)


if __name__ == "__main__":
    main()
