#!/usr/bin/env python3
"""Index an album of Lightroom CC single-slider exports as a development set.

    python3 Tools/parity/album_index.py --exports <folder> [<folder> …] --raws <folder> [<folder> …]
                                        --out ~/LuminaEvidence/parity/portraits
                                        [--held-out <folder of held-out exports>] [--need base,Shadows__100,…] [--write]

One album, many rounds: the same photos exported once per preset (Base, Base + lens profile, one
slider moved). The settings are read from each JPEG's own XMP (`lr_cc_sweep.read_xmp`), so file
names and folders don't matter. A photo is usable when its camera profile is Adobe Color, it is
not cropped, its RAW is found, it has a Base export, and it is not part of the held-out shoot
(`--held-out`: any photo whose RAW, or whose capture day, appears in that folder's exports is
left out, because the held-out set is measured, never fitted).

`--write` makes `<out>/{base-refs,refs,raw}` (symlinks: `<stem>__base.jpg`, `<stem>__<Slider>__<value>.jpg`,
the RAWs), `<out>/index.json` and `<out>/split.json` (every capture day split in two: `train` to
fit on, `test` never fitted). Everything stays under --out: these are someone's photos.
"""
import argparse
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lr_cc_sweep  # noqa: E402

LOOK = "Adobe Color"
DATE_RE = re.compile(rb'(?:xmp:CreateDate|photoshop:DateCreated)(?:="|>)(\d{4}-\d{2}-\d{2})')
RAW_EXT = (".arw", ".dng", ".cr3", ".nef", ".raf")


def expand(p):
    return os.path.abspath(os.path.expanduser(p))


def jpegs(folder):
    return sorted(n for n in os.listdir(folder) if n.lower().endswith((".jpg", ".jpeg")) and not n.startswith("."))


def capture_day(path):
    with open(path, "rb") as f:
        m = DATE_RE.search(f.read())
    return m.group(1).decode() if m else None


def state_key(crs):
    """('base' | 'baseLens' | '<Slider>__<value>', None) or (None, why)."""
    if crs.get("LookName") != LOOK:
        return None, f"profile is {crs.get('LookName') or crs.get('CameraProfile')}, not {LOOK}"
    if crs.get("HasCrop") == "True":
        return None, "cropped"
    kind, why = lr_cc_sweep.classify(crs, table=[])
    if kind is None:
        return None, why
    if isinstance(kind, str):
        return kind, None
    return f"{kind[0]}__{lr_cc_sweep.value_name(kind[1])}", None


def raw_table(folders):
    """{upper-case file name: path} for every RAW under the folders (first folder wins)."""
    out = {}
    for folder in folders:
        for root, _, names in os.walk(folder):
            for n in names:
                if n.lower().endswith(RAW_EXT) and not n.startswith("."):
                    out.setdefault(n.upper(), os.path.join(root, n))
    return out


def held_out(folder):
    """(RAW names, capture days) of a held-out export folder."""
    names, days = set(), set()
    for n in jpegs(folder):
        p = os.path.join(folder, n)
        crs = lr_cc_sweep.read_xmp(p) or {}
        if crs.get("RawFileName"):
            names.add(crs["RawFileName"].upper())
        day = capture_day(p)
        if day:
            days.add(day)
    return names, days


def index(export_dirs, raws, held=(set(), set()), need=("base",)):
    """→ (good {raw name: {'day', 'raw', 'states': {key: export path}}}, skipped {raw name: why}, odd counter)."""
    photos, skipped, odd = {}, {}, collections.Counter()
    for folder in export_dirs:
        for n in jpegs(folder):
            path = os.path.join(folder, n)
            crs = lr_cc_sweep.read_xmp(path)
            if not crs or not crs.get("RawFileName"):
                odd["no settings in the file"] += 1
                continue
            raw = crs["RawFileName"].upper()
            day = capture_day(path)
            if raw in held[0] or day in held[1]:
                skipped[raw] = "held-out shoot"
                continue
            if raw not in raws:
                skipped[raw] = "no RAW"
                continue
            key, why = state_key(crs)
            if key is None:
                skipped.setdefault(raw, why)
                odd[why.split(",")[0].split(" is ")[0]] += 1
                continue
            p = photos.setdefault(raw, {"day": day, "raw": raws[raw], "states": {}})
            if key in p["states"]:
                odd["duplicate " + key] += 1
            p["states"][key] = path
    good = {}
    for raw, p in sorted(photos.items()):
        missing = [k for k in need if k not in p["states"]]
        if missing:
            skipped[raw] = "missing " + ", ".join(missing)
        else:
            good[raw] = p
            skipped.pop(raw, None)
    return good, skipped, odd


def split(good):
    """Every capture day alternates train / test in name order, so both halves see every light."""
    out = {"train": [], "test": []}
    by_day = collections.defaultdict(list)
    for raw, p in sorted(good.items()):
        by_day[p["day"]].append(raw)
    for day in sorted(by_day, key=str):
        for i, raw in enumerate(by_day[day]):
            out["test" if i % 2 else "train"].append(raw)
    return out


def write(out, good):
    made = 0
    for sub in ("base-refs", "refs", "raw"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    for raw, p in good.items():
        stem = os.path.splitext(raw)[0]
        links = [(os.path.join(out, "raw", os.path.basename(p["raw"])), p["raw"])]
        for key, src in p["states"].items():
            links.append((os.path.join(out, "base-refs" if key == "base" else "refs", f"{stem}__{key}.jpg"), src))
        for dst, src in links:
            if os.path.lexists(dst) and os.path.realpath(dst) != os.path.realpath(src):
                os.remove(dst)
            if not os.path.lexists(dst):
                os.symlink(src, dst)
                made += 1
    with open(os.path.join(out, "index.json"), "w") as f:
        json.dump({"good": good}, f, indent=1)
    with open(os.path.join(out, "split.json"), "w") as f:
        json.dump(split(good), f, indent=1)
    return made


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--exports", nargs="+", required=True)
    ap.add_argument("--raws", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--held-out", help="folder of held-out exports: their RAWs and capture days are left out")
    ap.add_argument("--need", default="base", help="comma-separated states a photo must have (default: base)")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args(argv)
    held = held_out(expand(a.held_out)) if a.held_out else (set(), set())
    good, skipped, odd = index([expand(d) for d in a.exports], raw_table([expand(d) for d in a.raws]), held, tuple(a.need.split(",")))
    states = collections.Counter(k for p in good.values() for k in p["states"])
    print(f"usable {len(good)} · skipped {len(skipped)}: {dict(collections.Counter(skipped.values()))}")
    print("days:", dict(collections.Counter(str(p['day']) for p in good.values())))
    print("states:", dict(sorted(states.items())))
    if odd:
        print("odd files:", dict(odd))
    if a.write:
        print("new links:", write(expand(a.out), good))
    return 0


if __name__ == "__main__":
    sys.exit(main())
