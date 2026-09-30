#!/usr/bin/env python3
"""The golden set's metadata (Tools/parity/golden.json). The photos themselves stay in
~/LuminaEvidence/parity/golden (AGENTS.md: personal data stays out of the repo); only body, ISO,
exposure and tags are recorded here.

    python3 Tools/parity/golden.py add ~/LuminaEvidence/parity/golden/DSC01234.ARW --tag backlit --tag iso12800
    python3 Tools/parity/golden.py check            # every listed file exists, every category has a photo
    python3 Tools/parity/golden.py list

Categories the roadmap asks for (Prompt 2 §1): backlit, blown-sky, iso12800, tungsten, mixed,
snow, foliage, under2, over2, highkey, plus the existing golden card's picks (tag "card").
"""
import argparse
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden.json")
CATEGORIES = ["card", "backlit", "blown-sky", "iso12800", "tungsten", "mixed", "snow", "foliage", "under2", "over2", "highkey"]


def exif(path):
    """Model, ISO, exposure time, f-number and exposure bias from an ARW's TIFF/EXIF IFDs. A
    Sony ARW is a TIFF: IFD0 holds Make/Model and the EXIF pointer. No third-party reader."""
    with open(path, "rb") as f:
        head = f.read(1 << 20)
    if head[:2] not in (b"II", b"MM"):
        raise ValueError("not a TIFF-based RAW")
    e = "<" if head[:2] == b"II" else ">"
    tags = {}

    def read_ifd(off, into):
        n = struct.unpack(e + "H", head[off:off + 2])[0]
        for i in range(n):
            p = off + 2 + 12 * i
            tag, typ, cnt = struct.unpack(e + "HHI", head[p:p + 8])
            size = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8}.get(typ, 1) * cnt
            data = head[p + 8:p + 12] if size <= 4 else head[struct.unpack(e + "I", head[p + 8:p + 12])[0]:][:size]
            if typ == 2:
                val = data.split(b"\0")[0].decode("latin-1", errors="ignore").strip()
            elif typ == 3:
                val = struct.unpack(e + "H", data[:2])[0]
            elif typ == 4:
                val = struct.unpack(e + "I", data[:4])[0]
            elif typ in (5, 10):
                a, b = struct.unpack(e + ("II" if typ == 5 else "ii"), data[:8])
                val = a / b if b else 0
            else:
                val = None
            into[tag] = val

    read_ifd(struct.unpack(e + "I", head[4:8])[0], tags)
    if 0x8769 in tags and isinstance(tags[0x8769], int):
        read_ifd(tags[0x8769], tags)
    return {"body": tags.get(0x0110, ""), "iso": tags.get(0x8827), "exposureTime": tags.get(0x829A), "fNumber": tags.get(0x829D),
            "exposureBias": tags.get(0x9204), "dateTime": tags.get(0x9003) or tags.get(0x0132)}


def load():
    if not os.path.exists(GOLDEN):
        return {"version": 1, "root": "~/LuminaEvidence/parity/golden", "images": []}
    with open(GOLDEN) as f:
        return json.load(f)


def save(data):
    data["images"].sort(key=lambda i: i["file"])
    with open(GOLDEN, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")


def fmt_exposure(x):
    t = x.get("exposureTime")
    if not t:
        return ""
    s = f"1/{round(1 / t)}" if t < 1 else f"{t:g}s"
    return f"{s} f/{x['fNumber']:g}" if x.get("fNumber") else s


def cmd_add(a):
    data = load()
    for path in a.files:
        x = exif(path)
        entry = {"file": os.path.basename(path), "body": x["body"], "iso": x["iso"], "exposure": fmt_exposure(x),
                 "exposureBias": x["exposureBias"], "tags": sorted(set(a.tag or []))}
        data["images"] = [i for i in data["images"] if i["file"] != entry["file"]] + [entry]
        print(f"added {entry['file']}: {entry['body']} ISO {entry['iso']} {entry['exposure']} {'+' if (entry['exposureBias'] or 0) >= 0 else ''}{entry['exposureBias']} EV {entry['tags']}")
    save(data)
    return 0


def cmd_check(a):
    data = load()
    root = os.path.expanduser(a.root or data.get("root", ""))
    ok = True
    for i in data["images"]:
        if root and not os.path.exists(os.path.join(root, i["file"])):
            print(f"missing: {os.path.join(root, i['file'])}")
            ok = False
    have = {t for i in data["images"] for t in i.get("tags", [])}
    for c in CATEGORIES:
        if c not in have:
            print(f"no photo tagged {c}")
    print(f"{len(data['images'])} images (the roadmap asks for 50) · categories covered {len(have & set(CATEGORIES))}/{len(CATEGORIES)}")
    if len(data["images"]) < 50:
        ok = False
    return 0 if ok else 1


def cmd_list(a):
    data = load()
    for i in data["images"]:
        print(f"{i['file']}  {i.get('body', '')}  ISO {i.get('iso')}  {i.get('exposure', '')}  {','.join(i.get('tags', []))}")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("add"); p.add_argument("files", nargs="+"); p.add_argument("--tag", action="append")
    p = sub.add_parser("check"); p.add_argument("--root")
    sub.add_parser("list")
    a = ap.parse_args(argv)
    return {"add": cmd_add, "check": cmd_check, "list": cmd_list}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
