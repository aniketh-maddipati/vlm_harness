#!/usr/bin/env python3
"""Culling accuracy: what lumina-core decides for a shoot vs what the photographer really picked.

    python3 Tools/culling-eval/score.py --exports exports.csv --out report.md runs/*/dump-decisions/decisions.json

`decisions.json` is the probe's dump (Tools/culling-eval/dump-decisions.json): the real page and
native reader open a folder and every photo's row, stack, rank, peak, flags and suggested keep
are written out. `exports.csv` is `exiftool -csv -FileName -RawFileName -DateTimeOriginal` over
the photographer's finished exports: a RAW counts as **picked** when an export names it
(crs:RawFileName) with the same capture time (file numbers repeat across cards, times don't).

A pick is a *final select*, stricter than a culling keep, so precision against it is low by
nature. What a culling aid must get right is the other direction: it should not flag, rank
down or leave out the frames that were picked. So the report leads with recall on picks, the
false-alarm rate of each flag on picks, and whether the frame picked from a burst is the one
ranked first.

Only days with at least one pick are scored: a day never exported from is unlabeled, not
"all rejected". Numbers only: no file names leave this script (the photos are personal).
"""
import argparse
import collections
import csv
import json
import os
import sys

FLAGS = ("soft", "slight", "blown", "shake", "dark")


def key(name, date, time):
    """(DSC01234, 2026-05-19 14:14:38): the stem and the capture second."""
    stem = os.path.splitext(os.path.basename(name))[0].upper()
    return stem, f"{date.replace(':', '-')} {time}"


def load_picks(path):
    picks = set()
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            raw, dt = (r.get("RawFileName") or "").strip(), (r.get("DateTimeOriginal") or "").strip()
            if not raw or len(dt) < 19:
                continue
            picks.add(key(raw, dt[:10], dt[11:19]))
    return picks


def label(photos, picks):
    """Adds `pick` to each photo; returns the photos on days with at least one pick."""
    for p in photos:
        p["pick"] = key(p["path"], p.get("date") or "", p.get("sec") or "") in picks
    days = {p["date"] for p in photos if p["pick"]}
    return [p for p in photos if p["date"] in days]


def rate(n, d):
    return n / d if d else None


def score(photos):
    """Every number the report prints, from labeled photos (see `label`)."""
    n, picks = len(photos), [p for p in photos if p["pick"]]
    out = {"photos": n, "picks": len(picks), "pickRate": rate(len(picks), n), "days": len({p["date"] for p in photos})}
    if not n:
        return out
    sug = [p for p in photos if p["sug"]]
    hit = sum(1 for p in picks if p["sug"])
    not_sug = [p for p in photos if not p["sug"]]
    out["suggested"] = {
        "count": len(sug), "share": rate(len(sug), n),
        "recallOnPicks": rate(hit, len(picks)), "precision": rate(hit, len(sug)),
        "pickRateIfSuggested": rate(hit, len(sug)),
        "pickRateIfNot": rate(sum(1 for p in not_sug if p["pick"]), len(not_sug)),
    }
    out["flags"] = {}
    for f in FLAGS:
        fl = [p for p in photos if p.get(f)]
        rest = [p for p in photos if not p.get(f)]
        out["flags"][f] = {
            "flagged": len(fl), "share": rate(len(fl), n),
            "picksFlagged": sum(1 for p in picks if p.get(f)), "falseAlarmOnPicks": rate(sum(1 for p in picks if p.get(f)), len(picks)),
            "pickRateIfFlagged": rate(sum(1 for p in fl if p["pick"]), len(fl)),
            "pickRateIfNot": rate(sum(1 for p in rest if p["pick"]), len(rest)),
        }
    # Stacks: the frame picked from a burst vs the one lumina-core ranks first / marks as the peak.
    stacks = collections.defaultdict(list)
    for p in photos:
        if p.get("kind") == "burst" and p.get("gid"):
            stacks[(p.get("pool"), p["gid"])].append(p)
    with_pick = [g for g in stacks.values() if any(p["pick"] for p in g)]
    top1 = [any(p["pick"] and p["rank"] == 1 for p in g) for g in with_pick]
    top3 = [any(p["pick"] and p["rank"] <= 3 for p in g) for g in with_pick]
    sugp = [any(p["pick"] and p["sug"] for p in g) for g in with_pick]
    chance1 = [sum(1 for p in g if p["pick"]) / len(g) for g in with_pick]
    chance3 = [min(1.0, 1 - _none_in_top(len(g), sum(1 for p in g if p["pick"]), 3)) for g in with_pick]
    peaks = [g for g in with_pick if any(p["peak"] for p in g)]
    out["stacks"] = {
        "bursts": len(stacks), "burstsWithAPick": len(with_pick),
        "framesInBursts": sum(len(g) for g in stacks.values()),
        "meanSize": rate(sum(len(g) for g in with_pick), len(with_pick)),
        "pickIsRank1": rate(sum(top1), len(top1)), "chanceRank1": rate(sum(chance1), len(chance1)),
        "pickInTop3": rate(sum(top3), len(top3)), "chanceTop3": rate(sum(chance3), len(chance3)),
        "pickIsSuggested": rate(sum(sugp), len(sugp)),
        "withPeak": len(peaks), "pickIsPeak": rate(sum(1 for g in peaks if any(p["pick"] and p["peak"] for p in g)), len(peaks)),
        "picksPerBurst": dict(sorted(collections.Counter(min(3, sum(1 for p in g if p["pick"])) for g in with_pick).items())),
        "picksInBursts": sum(1 for p in picks if p.get("kind") == "burst"),
        "picksSingle": sum(1 for p in picks if p.get("kind") != "burst"),
    }
    rows = collections.defaultdict(list)
    for p in photos:
        rows[(p.get("pool"), p["row"])].append(p)
    per_row = [sum(1 for p in r if p["pick"]) for r in rows.values()]
    out["rows"] = {"rows": len(rows), "withAPick": sum(1 for k in per_row if k), "meanSize": rate(n, len(rows)),
                   "meanPicksWhenAny": rate(sum(per_row), sum(1 for k in per_row if k))}
    return out


def _none_in_top(n, k, top):
    """P(no pick among `top` frames drawn at random from n with k picks)."""
    top = min(top, n)
    p = 1.0
    for i in range(top):
        p *= max(0, n - k - i) / (n - i)
    return p


def pct(v):
    return "–" if v is None else f"{100 * v:.0f} %"


def report(pools, total, unmatched):
    L = ["# Culling accuracy — lumina-core vs the photographer's picks", "",
         "A pick = a RAW with a finished Lightroom export. Scored on days with at least one pick. Numbers only.", ""]
    L += ["| shoot | days | photos | picks | pick rate | suggested keeps | picks among suggested (recall) |", "|---|---:|---:|---:|---:|---:|---:|"]
    for name, s in list(pools.items()) + [("**all**", total)]:
        if not s["photos"]:
            L.append(f"| {name} | 0 | 0 | 0 | – | – | – |")
            continue
        g = s["suggested"]
        L.append(f"| {name} | {s['days']} | {s['photos']} | {s['picks']} | {pct(s['pickRate'])} | {g['count']} ({pct(g['share'])}) | {pct(g['recallOnPicks'])} |")
    if total["photos"]:
        g, st, rw = total["suggested"], total["stacks"], total["rows"]
        L += ["", "## Suggested keeps", "",
              f"- lumina-core suggests keeping {pct(g['share'])} of the photos; {pct(g['recallOnPicks'])} of the picks are among them.",
              f"- A suggested photo was picked {pct(g['pickRateIfSuggested'])} of the time, a not-suggested one {pct(g['pickRateIfNot'])}.",
              "", "## Flags", "",
              "| flag | photos flagged | picks flagged (false alarms) | picked if flagged | picked if not |", "|---|---:|---:|---:|---:|"]
        for f in FLAGS:
            x = total["flags"][f]
            L.append(f"| {f} | {x['flagged']} ({pct(x['share'])}) | {x['picksFlagged']} ({pct(x['falseAlarmOnPicks'])} of picks) | {pct(x['pickRateIfFlagged'])} | {pct(x['pickRateIfNot'])} |")
        L += ["", "## Bursts", "",
              f"- {st['bursts']} bursts ({st['framesInBursts']} frames); {st['burstsWithAPick']} hold a pick (mean size {st['meanSize'] or 0:.1f}).",
              f"- The pick is the frame ranked first in {pct(st['pickIsRank1'])} of them (chance: {pct(st['chanceRank1'])}); in the top 3 in {pct(st['pickInTop3'])} (chance: {pct(st['chanceTop3'])}).",
              f"- The pick is the suggested keep in {pct(st['pickIsSuggested'])}; where a peak is marked ({st['withPeak']} bursts) the pick is the peak in {pct(st['pickIsPeak'])}.",
              f"- Picks per burst (3 = three or more): {st['picksPerBurst']}. {st['picksInBursts']} picks come from bursts, {st['picksSingle']} from single frames.",
              "", "## Rows", "",
              f"- {rw['rows']} rows (mean {rw['meanSize'] or 0:.1f} photos); {rw['withAPick']} hold a pick, {rw['meanPicksWhenAny'] or 0:.1f} picks each on average."]
    L += ["", f"Exports that name a RAW not found in these folders: {unmatched}."]
    return "\n".join(L) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("decisions", nargs="+")
    ap.add_argument("--exports", required=True)
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    picks = load_picks(a.exports)
    pools, everything, seen = {}, [], set()
    for path in a.decisions:
        name = os.path.basename(os.path.dirname(os.path.dirname(os.path.abspath(path))))
        photos = json.load(open(path))["photos"]
        for p in photos:
            p["pool"] = name
        labeled = label(photos, picks)
        seen |= {key(p["path"], p["date"], p["sec"]) for p in photos if p["pick"]}
        pools[name] = score(labeled)
        everything += labeled
    total = score(everything)
    text = report(pools, total, len(picks - seen))
    if a.out:
        with open(a.out, "w") as f:
            f.write(text)
        with open(os.path.splitext(a.out)[0] + ".json", "w") as f:
            json.dump({"pools": pools, "all": total, "unmatchedExports": len(picks - seen)}, f, indent=1)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
