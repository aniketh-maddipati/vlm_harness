#!/usr/bin/env python3
"""Index Lightroom's sweep TIFFs into refs.json (roadmap Prompt 2 §1).

    python3 Tools/parity/import_refs.py ~/LuminaEvidence/parity/refs [--out ~/LuminaEvidence/parity/refs.json]

Expected names, as lr_sweep.lrdevplugin writes them:
    <stem>__base.tif                       Adobe Color, everything reset
    <stem>__<Slider>__<value>.tif          one slider, e.g. DSC01234__Exposure__-2.5.tif
    <stem>__combo<NN>.tif + .json          three sliders at once; the JSON holds the settings
    <stem>__asshot.json                    Lightroom's as-shot Temperature / Tint and the profile
    <stem>__edit<NN>.jpg|.tif + .json      one of your own Lightroom edits (import_lr_edits.py): the
                                           JSON holds its settings, look string, bucket and features
Anything else is listed under "ignored". Each entry records size, bit depth and the colour space
read from the image's ICC profile (TIFF, or an 8-bit sRGB JPEG for edits), so delta_e.py converts
to the right Lab white.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

NAME = re.compile(r"^(?P<stem>.+?)__(?:(?P<base>base)|(?P<slider>[A-Za-z][A-Za-z0-9]*)__(?P<value>-?\d+(?:\.\d+)?)|combo(?P<combo>\d+))\.(?:tif|tiff|jpg|jpeg)$|^(?P<estem>.+?)__edit(?P<edit>\d+)\.(?:tif|tiff|jpg|jpeg)$", re.I)
SLIDER_ALIASES = {"exposure2012": "Exposure", "contrast2012": "Contrast", "highlights2012": "Highlights", "shadows2012": "Shadows",
                  "whites2012": "Whites", "blacks2012": "Blacks", "clarity2012": "Clarity", "sharpening": "Sharpness"}


def canonical_slider(name):
    return SLIDER_ALIASES.get(name.lower(), name[:1].upper() + name[1:])


def tiff_info(path):
    """(width, height, bits, space) from the first page."""
    import tifffile
    from delta_e import space_from_icc
    with tifffile.TiffFile(path) as tf:
        page = tf.pages[0]
        icc = page.tags.get("InterColorProfile")
        space = space_from_icc(bytes(icc.value)) if icc is not None else None
        return int(page.imagewidth), int(page.imagelength), int(page.bitspersample if isinstance(page.bitspersample, int) else page.bitspersample[0]), space


def image_info(path):
    """(width, height, bits, space): TIFF through tiff_info, anything else (the JPEG exports of
    import_lr_edits.py) through Pillow."""
    if path.lower().endswith((".tif", ".tiff")):
        return tiff_info(path)
    from PIL import Image
    from delta_e import space_from_icc
    with Image.open(path) as im:
        icc = im.info.get("icc_profile")
        bits = 16 if im.mode in ("I;16", "I;16B", "RGB;16") else 8
        return int(im.width), int(im.height), bits, (space_from_icc(icc) if icc else "srgb")


def index(folder, read_info=True):
    refs, ignored, asshot = [], [], {}
    for name in sorted(os.listdir(folder)):
        if name.startswith("."):
            continue                                    # AppleDouble stubs (._name) on an ExFAT disk, .DS_Store
        path = os.path.join(folder, name)
        if name.lower().endswith("__asshot.json"):
            stem = name[: -len("__asshot.json")]
            with open(path) as f:
                asshot[stem] = json.load(f)
            continue
        m = NAME.match(name)
        if not m:
            if not name.lower().endswith(".json") and not name.startswith("."):
                ignored.append(name)
            continue
        entry = {"stem": m.group("stem") or m.group("estem"), "file": name, "path": path}
        if m.group("edit"):
            side = os.path.splitext(path)[0] + ".json"
            d = json.load(open(side)) if os.path.exists(side) else {}
            extra = {k: v for k, v in d.items() if k not in ("stem", "file", "path", "id", "kind")}
            extra["settings"] = {canonical_slider(k): v for k, v in d.get("settings", {}).items()}
            entry.update(kind="edit", edit=int(m.group("edit")), **extra)
        elif m.group("base"):
            entry.update(kind="base", settings={})
        elif m.group("slider"):
            slider = canonical_slider(m.group("slider"))
            entry.update(kind="single", slider=slider, value=float(m.group("value")), settings={slider: float(m.group("value"))})
        else:
            side = os.path.splitext(path)[0] + ".json"
            settings = {}
            if os.path.exists(side):
                with open(side) as f:
                    d = json.load(f)
                settings = {canonical_slider(k): v for k, v in d.get("settings", d).items()}
            entry.update(kind="combo", combo=int(m.group("combo")), settings=settings)
        if read_info:
            try:
                w, h, bits, space = image_info(path)
                entry.update(width=w, height=h, bits=bits, space=space)
            except Exception as e:  # a half-written export
                entry["error"] = str(e)
        entry["id"] = os.path.splitext(name)[0]
        refs.append(entry)
    for r in refs:
        if r["stem"] in asshot:
            r["asShot"] = asshot[r["stem"]]
    stems = sorted({r["stem"] for r in refs})
    by_slider = {}
    for r in refs:
        if r["kind"] == "single":
            by_slider.setdefault(r["slider"], set()).add(r["value"])
    return {
        "version": 1,
        "folder": os.path.abspath(folder),
        "images": stems,
        "counts": {"images": len(stems), "base": sum(r["kind"] == "base" for r in refs), "singles": sum(r["kind"] == "single" for r in refs),
                   "combos": sum(r["kind"] == "combo" for r in refs),
                   **({"edits": sum(r["kind"] == "edit" for r in refs)} if any(r["kind"] == "edit" for r in refs) else {})},
        "sliders": {s: sorted(v) for s, v in sorted(by_slider.items())},
        "spaces": sorted({str(r.get("space")) for r in refs}),
        "refs": refs,
        "ignored": ignored,
    }


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder")
    ap.add_argument("--out", help="default: <folder>/../refs.json")
    ap.add_argument("--no-info", action="store_true", help="skip reading the TIFF headers")
    a = ap.parse_args(argv)
    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.folder)), "refs.json")
    data = index(a.folder, read_info=not a.no_info)
    with open(out, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    c = data["counts"]
    print(f"{out}: {c['images']} images · {c['base']} base · {c['singles']} singles · {c['combos']} combos · spaces {data['spaces']}"
          + (f" · {c['edits']} edits" if c.get("edits") else "") + (f" · ignored {len(data['ignored'])}" if data["ignored"] else ""))
    missing_base = [s for s in data["images"] if not any(r["kind"] in ("base", "edit") and r["stem"] == s for r in data["refs"])]
    if missing_base:
        print("no __base.tif for: " + ", ".join(missing_base))
    for s, vals in data["sliders"].items():
        if len(vals) < 10:
            print(f"{s}: {len(vals)} positions (the sweep asks for 10)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
