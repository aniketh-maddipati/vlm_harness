#!/usr/bin/env python3
"""Fit when Skim's strip should say "sure" (docs/masking/TRACKING-EXPERIMENTS.md, E2).

    python3 Tools/masklab/calibrate.py --fit RUN[:LABELS] … --test RUN[:LABELS] … [--out rule.json]

Each RUN is a masklab-skim run (one folder per clip with masks and timing.json holding `cues_frames`),
and LABELS is its labels root (<clip>/<frame>.png). Without `:LABELS`, RUN/../../labels is used, which is
the mask lab's layout (EVID/runs/<date>/skim and EVID/labels).

Every labelled frame becomes a row: its cues (SkimFollow.Cues), cues derived from the clip so far (the
area against the start frame's), and its true IoU. A rule is a set of thresholds:

    sure  ⇔  found  ∧ tracker ≥ T  ∧ agree ≥ A  ∧ rivals ≤ R  ∧ ¼·S ≤ area/start ≤ S  ∧ jump ≤ J  ∧ ¬refound

The fit picks, on the --fit runs only, the rule that calls the most frames sure while the frames it calls
sure average IoU ≥ --target (0.85) and at most --bad-share (0.05) of them are under IoU 0.5. Then it
reports the same numbers on every --test run, set by set, beside today's rule (`sure_frames` as the app
wrote them). Nothing in the app changes here: a rule that holds up becomes SkimFollow.sureness by hand.
"""
import argparse
import itertools
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score  # noqa: E402

GRID = {
    "tracker": [0.0, 0.3, 0.5, 0.6, 0.7, 0.8, 0.9],
    "agree": [0.0, 0.3, 0.5, 0.6, 0.7, 0.8],
    "rivals": [1, 2, 99],
    "start": [1.5, 2.0, 3.0, 99.0],
    "jump": [1.2, 1.35, 1.6, 99.0],
}


def rows(run, labels):
    """One dict per labelled frame of each clip in a skim run: cues, today's state, true IoU."""
    out = []
    for clip, folder in score.clip_dirs(run).items():
        timing = score.load_timing(folder) or {}
        cues = timing.get("cues_frames")
        states = timing.get("sure_frames")
        if not cues or not states:
            continue
        start = int(timing.get("start_frame", 0))
        lab = score.frame_files(os.path.join(labels, clip)) if labels else {}
        masks = score.frame_files(folder)
        a0 = next((c.get("area") for c in cues if c and c.get("area")), None)
        for n, path in sorted(lab.items()):
            k = n - start
            if not (0 <= k < len(cues)) or n not in masks:
                continue
            truth = score.load_mask(path)
            pred = score.resize_nearest(score.load_mask(masks[n]), truth.shape)
            c = cues[k] or {}
            area, last = c.get("area"), c.get("last")
            out.append({
                "clip": clip, "frame": n, "iou": score.iou(pred, truth), "today": states[k],
                "found": area is not None,
                "tracker": c.get("tracker"), "agree": c.get("agree"), "rivals": c.get("rivals", 0),
                "refound": bool(c.get("refound")),
                "start": max(area / a0, a0 / area) if area and a0 else None,
                "jump": max(area / last, last / area) if area and last else None,
            })
    return out


def sure(r, rule):
    """Whether a frame is sure under `rule`. A missing cue passes its test (the first frame has no tracker figure,
    the sky and background none at all), except that a frame with no shape is never sure."""
    if not r["found"] or r["refound"]:
        return False
    ok = lambda v, test: v is None or test(v)
    return (ok(r["tracker"], lambda v: v >= rule["tracker"]) and ok(r["agree"], lambda v: v >= rule["agree"])
            and r["rivals"] <= rule["rivals"] and ok(r["start"], lambda v: v <= rule["start"])
            and ok(r["jump"], lambda v: v <= rule["jump"]))


def measure(rs, called):
    """Sure share, IoU when sure, share of sure frames under 0.5, and IoU when not sure."""
    s = [r["iou"] for r, c in zip(rs, called) if c]
    n = [r["iou"] for r, c in zip(rs, called) if not c]
    return {"frames": len(rs), "sure_share": len(s) / len(rs) if rs else None,
            "iou_sure": float(np.mean(s)) if s else None,
            "bad_share": float(np.mean([v < 0.5 for v in s])) if s else None,
            "iou_not_sure": float(np.mean(n)) if n else None}


def fit(rs, target=0.85, bad=0.05):
    best, best_m = None, None
    for vals in itertools.product(*GRID.values()):
        rule = dict(zip(GRID, vals))
        m = measure(rs, [sure(r, rule) for r in rs])
        if m["iou_sure"] is None or m["iou_sure"] < target or m["bad_share"] > bad:
            continue
        if best_m is None or m["sure_share"] > best_m["sure_share"]:
            best, best_m = rule, m
    return best, best_m


def parse_run(arg):
    run, _, labels = arg.partition(":")
    if not labels:
        labels = os.path.normpath(os.path.join(os.path.dirname(os.path.normpath(run)), "..", "..", "labels"))
    return run, labels


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fit", nargs="+", required=True, help="skim runs to fit on (train splits)")
    ap.add_argument("--test", nargs="*", default=[], help="skim runs to check on (held-out splits)")
    ap.add_argument("--target", type=float, default=0.85, help="mean IoU the sure frames must reach (0.85)")
    ap.add_argument("--bad-share", type=float, default=0.05, help="most sure frames allowed under IoU 0.5 (0.05)")
    ap.add_argument("--out", help="write the rule and every number here (JSON)")
    a = ap.parse_args(argv)

    fit_rows = [r for arg in a.fit for r in rows(*parse_run(arg))]
    if not fit_rows:
        print("calibrate: no labelled frames with cues in the --fit runs", file=sys.stderr)
        return 1
    rule, m = fit(fit_rows, a.target, a.bad_share)
    report = {"target": a.target, "bad_share": a.bad_share, "rule": rule, "fit": m,
              "fit_today": measure(fit_rows, [r["today"] == "sure" for r in fit_rows]), "test": {}}
    print(f"fit: {len(fit_rows)} labelled frames")
    if rule is None:
        print(f"  no rule in the grid reaches IoU {a.target} with ≤ {a.bad_share:.0%} bad frames")
    else:
        print(f"  rule {rule}: sure {m['sure_share']:.0%}, IoU when sure {m['iou_sure']:.3f}, bad {m['bad_share']:.1%}")
    for arg in a.test:
        run, labels = parse_run(arg)
        rs = rows(run, labels)
        if not rs:
            continue
        name = os.path.basename(os.path.dirname(os.path.normpath(run))) + "/" + os.path.basename(os.path.normpath(run))
        new = measure(rs, [sure(r, rule) for r in rs]) if rule else None
        old = measure(rs, [r["today"] == "sure" for r in rs])
        report["test"][name] = {"rule": new, "today": old}
        f = lambda x: "—" if x is None else f"{x:.3f}"
        line = f"test {name}: {len(rs)} frames · today sure {old['sure_share']:.0%} IoU {f(old['iou_sure'])} bad {f(old['bad_share'])}"
        if new:
            line += f" · fitted sure {new['sure_share']:.0%} IoU {f(new['iou_sure'])} bad {f(new['bad_share'])}"
        print(line)
    if a.out:
        with open(a.out, "w") as fh:
            json.dump(report, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
