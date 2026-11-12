#!/usr/bin/env python3
"""Exposure on the sensor data vs Lightroom: is Lightroom's Exposure a plain gain on the linear decode
seen through the profile (the camera profile stage's own `exposure`, PR #354), and at what scale?
Measures only; prints numbers, never edits rules.

    python3 Tools/parity/exposure_fit.py [--refs ~/LuminaEvidence/parity/sweep/refs.json] [--raws …/sweep/raw]
                                         [--px 1024] [--work ~/LuminaEvidence/parity/exposure-raw/work]

Decodes each sweep RAW once at boostAmount 0 (`lumina-render decode`, cached in --work), then scores,
per Exposure position (ΔE2000 median / p95, pooled over photos, leave-one-photo-out where a number
is fitted):
- today:   the profiled base, then the toned exposure stage (LookMath.exposure on the profile's output);
- gain:    the profile with its exposure + ev · k, k fitted per side (k = 1 is one stop per unit).
Lens shading is off on both sides (Lightroom's lens profile is off in the sweep).
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import better  # noqa: E402
import delta_e  # noqa: E402
import lookmath as lm  # noqa: E402
import profile_math as pm  # noqa: E402


def expand(p):
    return os.path.abspath(os.path.expanduser(p))


def decode(render, arw, work, px):
    stem = os.path.splitext(os.path.basename(arw))[0]
    out, meta = os.path.join(work, f"{stem}.b0.{px}.f32"), os.path.join(work, f"{stem}.b0.{px}.json")
    if not (os.path.exists(out) and os.path.exists(meta)):
        r = subprocess.run([render, "decode", arw, "--boost", "0", "--px", str(px), "--out", out], capture_output=True, text=True, check=True)
        open(meta, "w").write(r.stdout.strip().splitlines()[-1])
    m = json.load(open(meta))
    return np.fromfile(out, np.float32).reshape(m["height"], m["width"], 4)[..., :3].astype(np.float64)


def enc(lin):
    return delta_e.encode_srgb(np.clip(lin, 0, 1))


def score(ref_path, img_lin):
    ref = better.resize_to(delta_e.read_rgb01(ref_path)[0], img_lin.shape)
    return delta_e.measure(ref, enc(img_lin), "srgb", sample=20000)["sample"]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--refs", default="~/LuminaEvidence/parity/sweep/refs.json")
    ap.add_argument("--raws", default="~/LuminaEvidence/parity/sweep/raw")
    ap.add_argument("--rules", default=os.path.join(HERE, "../../Lumina/Sets/Look/rules-v1.json"))
    ap.add_argument("--render", default=os.path.join(HERE, "lumina-render/.build/release/lumina-render"))
    ap.add_argument("--px", type=int, default=1024)
    ap.add_argument("--work", default="~/LuminaEvidence/parity/exposure-raw/work")
    a = ap.parse_args(argv)
    rules = json.load(open(expand(a.rules)))
    stage = rules["stages"].get("profile")
    if not stage:
        raise SystemExit("these rules have no profile stage")
    work = expand(a.work); os.makedirs(work, exist_ok=True)
    refs = [r for r in json.load(open(expand(a.refs)))["refs"] if not r.get("error")]
    by = {}
    for r in refs:
        if r["kind"] == "base":
            by.setdefault(r["stem"], {})[0.0] = r["path"]
        elif r.get("slider") == "Exposure":
            by.setdefault(r["stem"], {})[float(r["value"])] = r["path"]
    stems = sorted(s for s in by if os.path.exists(os.path.join(expand(a.raws), s + ".ARW")))
    lin = {s: decode(expand(a.render), os.path.join(expand(a.raws), s + ".ARW"), work, a.px) for s in stems}
    evs = sorted({v for s in stems for v in by[s]})
    base = {s: pm.profile(lin[s], stage, rules) for s in stems}

    def with_ev(s, ev, k):
        st = json.loads(json.dumps(stage)); st["coefficients"]["exposure"] = float(st["coefficients"]["exposure"]) + ev * k
        return pm.profile(lin[s], st, rules)

    def today(s, ev):
        return lm.exposure(base[s], ev, rules) if ev else base[s]

    def side_err(train, ev_list, k):
        e = np.concatenate([score(by[s][ev], with_ev(s, ev, k)) for s in train for ev in ev_list if ev in by[s]])
        return float(np.median(e)), float(np.percentile(e, 95))

    K = [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4]
    neg, pos = [e for e in evs if e < 0], [e for e in evs if e > 0]
    rows = {"today": {}, "gain k=1": {}, "gain k fitted (held out)": {}}
    chosen = []
    for held in stems:
        train = [s for s in stems if s != held]
        kn = min(K, key=lambda k: side_err(train, neg, k)[1]) if neg else 1.0
        kp = min(K, key=lambda k: side_err(train, pos, k)[1]) if pos else 1.0
        chosen.append((held, kn, kp))
        for ev in evs:
            if ev not in by[held]:
                continue
            rows["today"].setdefault(ev, []).append(score(by[held][ev], today(held, ev)))
            rows["gain k=1"].setdefault(ev, []).append(score(by[held][ev], with_ev(held, ev, 1.0)))
            rows["gain k fitted (held out)"].setdefault(ev, []).append(score(by[held][ev], with_ev(held, ev, kn if ev < 0 else kp)))
    print("k per held-out photo (neg, pos):", [(s, kn, kp) for s, kn, kp in chosen])
    for name, per in rows.items():
        allv = np.concatenate([np.concatenate(per[e]) for e in evs if e != 0])
        print(f"{name:26s} all {np.median(allv):.2f}/{np.percentile(allv, 95):.2f} | " +
              "  ".join(f"{e:+g}: {np.median(np.concatenate(per[e])):.2f}/{np.percentile(np.concatenate(per[e]), 95):.2f}" for e in evs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
