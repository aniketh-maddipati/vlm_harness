#!/usr/bin/env python3
"""How honest is the strip? For each tracker in a score.py report: the share of frames called sure, their mean IoU,
and how many of them are wrong (IoU under --bad, 0.4 by default).

    python3 Tools/masklab/strip_stats.py REPORT.json [--bad 0.4] [--objects a_1,b_2]

The states come from each clip's timing.json (`sure_frames`, from the run's start frame), the IoU from the report's
per-frame rows, so only labelled frames count.
"""
import argparse, json, os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--bad", type=float, default=0.4)
    ap.add_argument("--objects", default="")
    a = ap.parse_args()
    rep = json.load(open(a.report))
    only = set(o for o in a.objects.split(",") if o)
    for run in rep["runs"]:
        sure, called_bad, frames, all_bad = [], 0, 0, 0
        per_obj = {}
        for clip, c in run["clips"].items():
            if only and clip not in only:
                continue
            t = os.path.join(run["path"], clip, "timing.json")
            if not os.path.exists(t):
                continue
            tj = json.load(open(t))
            st, s0 = tj.get("sure_frames") or [], int(tj.get("start_frame", 0))
            for p in c.get("per_frame", []):
                k = p["frame"] - s0
                if not (0 <= k < len(st)):
                    continue
                frames += 1
                bad = p["iou"] < a.bad
                all_bad += bad
                if st[k] == "sure":
                    sure.append(p["iou"])
                    called_bad += bad
                    per_obj.setdefault(clip, [0, 0])[0] += 1
                    per_obj[clip][1] += bad
        n = len(sure)
        print(f"{run['run']}: {frames} frames · sure {n / max(1, frames):.0%} · IoU when sure {sum(sure) / max(1, n):.3f} · "
              f"sure but under {a.bad}: {called_bad} ({called_bad / max(1, n):.1%} of sure) · frames under {a.bad}: {all_bad}, "
              f"of them called sure {called_bad / max(1, all_bad):.0%}")


if __name__ == "__main__":
    main()
