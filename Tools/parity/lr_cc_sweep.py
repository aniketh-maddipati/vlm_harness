#!/usr/bin/env python3
"""The single-slider sweep for Lightroom **CC** (no Classic, so no plug-in): develop presets to
click, and an ingest that turns the exports into refs the harness reads.

    python3 Tools/parity/lr_cc_sweep.py presets [--out ~/LuminaEvidence/parity/sweep]
        → <out>/presets/*.xmp and <out>/Lumina-sweep-presets.zip (Lightroom ▸ File ▸ Import
          Profiles & Presets…), one preset per sweep position, grouped "Lumina sweep".
    python3 Tools/parity/lr_cc_sweep.py ingest <exports> [--refs ~/LuminaEvidence/parity/refs]
        → <refs>/<stem>__base.jpg, <stem>__baseLens.jpg, <stem>__<Slider>__<value>.jpg, and
          sweep-ingest.json (what was found, what is missing, what looks wrong).

Lightroom CC can't name exports per preset, so the ingest never trusts file names: each export's
embedded XMP names the RAW (crs:RawFileName) and carries every develop setting, and the one
slider that differs from the base says which sweep position it is. Exports need Metadata ▸
"All metadata" (otherwise Lightroom strips the Camera Raw settings).

The positions are a subset of lr_sweep.lrdevplugin's (the Classic plug-in): the sliders the
first personal-set eval implicates (Exposure, Blacks, Contrast, Whites) at more positions, the
rest at a few, plus the base with lens profile corrections on (the border ΔL* question).
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile

# (preset label, Lightroom key, values). The Classic plug-in's names, so import_refs / fit.py read them.
SWEEP = [
    ("Exposure", "Exposure2012", [-2, -1, -0.5, 0.5, 1, 2]),
    ("Contrast", "Contrast2012", [-50, -25, 25, 50]),
    ("Blacks", "Blacks2012", [-50, -25, 25, 50]),
    ("Whites", "Whites2012", [-50, -25, 25, 50]),
    ("Highlights", "Highlights2012", [-100, -50, 50]),
    ("Shadows", "Shadows2012", [-50, 50, 100]),
    ("Vibrance", "Vibrance", [-50, 50]),
    ("Saturation", "Saturation", [-50, 50]),
]

# The base: every basic / detail / effects setting at its reset value, white balance as shot,
# capture sharpening 0 and luminance NR 0 (the Classic plug-in's base), lens corrections off. The
# camera profile is left alone (Lightroom's default, Adobe Color); the ingest checks it.
BASE = {
    "WhiteBalance": "As Shot",
    "Exposure2012": 0, "Contrast2012": 0, "Highlights2012": 0, "Shadows2012": 0, "Whites2012": 0, "Blacks2012": 0,
    "Texture": 0, "Clarity2012": 0, "Dehaze": 0, "Vibrance": 0, "Saturation": 0,
    "ParametricShadows": 0, "ParametricDarks": 0, "ParametricLights": 0, "ParametricHighlights": 0,
    "Sharpness": 0, "LuminanceSmoothing": 0, "ColorNoiseReduction": 25,
    "PostCropVignetteAmount": 0, "GrainAmount": 0,
    "LensProfileEnable": 0, "AutoLateralCA": 0,
}
LENS = {"LensProfileEnable": 1, "LensProfileSetup": "LensDefaults"}
SLIDER_KEYS = {key for _, key, _ in SWEEP}
GROUP = "Lumina sweep"


def fmt(key, v):
    if isinstance(v, str):
        return v
    if key == "Exposure2012":
        return f"{v:+.2f}"
    return f"{int(v):+d}" if v else "0"


def value_name(v):
    """The value as import_refs spells it in `<stem>__<Slider>__<value>`."""
    return f"{v:g}"


def presets():
    """(file name, preset name, settings) in click order."""
    out = [("01", "Base", dict(BASE)), ("02", "Base + lens profile", {**BASE, **LENS})]
    n = 3
    for label, key, values in SWEEP:
        for v in values:
            out.append((f"{n:02d}", f"{label} {fmt(key, v)}", {**BASE, key: v}))
            n += 1
    return out


def preset_xmp(num, name, settings):
    uid = hashlib.md5(f"lumina-sweep/{num}/{name}".encode()).hexdigest().upper()
    attrs = "\n".join(f'   crs:{k}="{fmt(k, v)}"' for k, v in settings.items())
    title = f"{num} {name}"
    return f"""<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
   crs:PresetType="Normal"
   crs:Cluster=""
   crs:UUID="{uid}"
   crs:SupportsAmount="False"
   crs:SupportsColor="True"
   crs:SupportsMonochrome="True"
   crs:SupportsHighDynamicRange="True"
   crs:SupportsNormalDynamicRange="True"
   crs:SupportsSceneReferred="True"
   crs:SupportsOutputReferred="True"
   crs:RequiresRGBTables="False"
   crs:CameraModelRestriction=""
   crs:Copyright=""
   crs:ContactInfo=""
   crs:Version="15.4"
   crs:ProcessVersion="15.4"
{attrs}
   crs:HasSettings="True">
   <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">{title}</rdf:li></rdf:Alt></crs:Name>
   <crs:ShortName><rdf:Alt><rdf:li xml:lang="x-default"/></rdf:Alt></crs:ShortName>
   <crs:SortName><rdf:Alt><rdf:li xml:lang="x-default"/></rdf:Alt></crs:SortName>
   <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">{GROUP}</rdf:li></rdf:Alt></crs:Group>
   <crs:Description><rdf:Alt><rdf:li xml:lang="x-default">Lumina parity sweep: one slider from the neutral base.</rdf:li></rdf:Alt></crs:Description>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
"""


def write_presets(out):
    d = os.path.join(out, "presets")
    os.makedirs(d, exist_ok=True)
    files = []
    for num, name, settings in presets():
        path = os.path.join(d, f"{num} {name}.xmp")
        with open(path, "w", encoding="utf-8") as f:
            f.write(preset_xmp(num, name, settings))
        files.append(path)
    z = os.path.join(out, "Lumina-sweep-presets.zip")
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in files:
            zf.write(p, os.path.join(GROUP, os.path.basename(p)))
    return files, z


# MARK: ingest

XMP_RE = re.compile(rb"<x:xmpmeta.*?</x:xmpmeta>", re.S)


def read_xmp(path):
    """Every crs:* setting in a JPEG's XMP packet (attribute or element form), as strings."""
    with open(path, "rb") as f:
        data = f.read()
    m = XMP_RE.search(data)
    if not m:
        return None
    text = m.group(0).decode("utf-8", "replace")
    out = {k: v for k, v in re.findall(r'crs:(\w+)="([^"]*)"', text)}
    out.update({k: v for k, v in re.findall(r"<crs:(\w+)>([^<]*)</crs:\1>", text)})
    look = re.search(r"<crs:Look>.*?crs:Name=\"([^\"]*)\"", text, re.S)
    if look:
        out["LookName"] = look.group(1)
    return out


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def classify(crs):
    """('base' | 'baseLens' | (slider, value)) or (None, why)."""
    lens = num(crs.get("LensProfileEnable")) == 1
    moved = [(k, num(crs.get(k))) for k in SLIDER_KEYS if num(crs.get(k)) not in (None, 0)]
    for k in ("Texture", "Clarity2012", "Dehaze"):
        if num(crs.get(k)) not in (None, 0):
            return None, f"{k} is {crs.get(k)} (the sweep keeps it 0)"
    if lens and moved:
        return None, "lens corrections on together with a slider"
    if not moved:
        return ("baseLens" if lens else "base"), None
    if len(moved) > 1:
        return None, "more than one slider moved: " + ", ".join(f"{k}={v:g}" for k, v in moved)
    key, v = moved[0]
    label = next(l for l, k, _ in SWEEP if k == key)
    return (label, v), None


def ingest(exports, refs):
    os.makedirs(refs, exist_ok=True)
    wanted = {("base",), ("baseLens",)} | {(l, float(v)) for l, _, vs in SWEEP for v in vs}
    found, problems = {}, []
    for root, _, names in os.walk(exports):
        for n in sorted(names):
            if not n.lower().endswith((".jpg", ".jpeg")):
                continue
            path = os.path.join(root, n)
            crs = read_xmp(path)
            if crs is None or "RawFileName" not in crs:
                problems.append({"file": n, "why": "no Camera Raw settings in the file: export with Metadata ▸ All metadata"})
                continue
            stem = os.path.splitext(crs["RawFileName"])[0]
            kind, why = classify(crs)
            if kind is None:
                problems.append({"file": n, "raw": crs["RawFileName"], "why": why})
                continue
            profile = crs.get("LookName") or crs.get("CameraProfile") or ""
            if profile and profile not in ("Adobe Color", "Adobe Standard"):
                problems.append({"file": n, "raw": crs["RawFileName"], "why": f"profile {profile} (expected Adobe Color)"})
            if isinstance(kind, tuple):
                slider, v = kind
                if (slider, float(v)) not in wanted:
                    problems.append({"file": n, "raw": crs["RawFileName"], "why": f"{slider} {v:g} is not a sweep position"})
                    continue
                dest, key = f"{stem}__{slider}__{value_name(v)}.jpg", (stem, slider, float(v))
            else:
                dest, key = f"{stem}__{kind}.jpg", (stem, kind)
            if key in found:
                problems.append({"file": n, "raw": crs["RawFileName"], "why": f"duplicate of {found[key]} (kept the first)"})
                continue
            shutil.copyfile(path, os.path.join(refs, dest))
            found[key] = n
    stems = sorted({k[0] for k in found})
    missing = {s: [" ".join(str(x) for x in w) for w in sorted(wanted, key=str)
                   if (s,) + w not in found] for s in stems}
    report = {"exports": exports, "refs": refs, "photos": stems, "refs_written": len(found),
              "expected_per_photo": len(wanted), "missing": {s: m for s, m in missing.items() if m}, "problems": problems}
    with open(os.path.join(refs, "sweep-ingest.json"), "w") as f:
        json.dump(report, f, indent=1)
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("presets")
    p.add_argument("--out", default=os.path.expanduser("~/LuminaEvidence/parity/sweep"))
    i = sub.add_parser("ingest")
    i.add_argument("exports")
    i.add_argument("--refs", default=os.path.expanduser("~/LuminaEvidence/parity/refs"))
    a = ap.parse_args(argv)
    if a.cmd == "presets":
        files, z = write_presets(a.out)
        print(f"{len(files)} presets → {os.path.dirname(files[0])}\nimport this in Lightroom: {z}")
    else:
        exports = os.path.expanduser(a.exports)
        if not os.path.isdir(exports):
            print(f"no folder {exports}: export from Lightroom into it first (see the presets step)")
            return 2
        r = ingest(exports, os.path.expanduser(a.refs))
        if r["refs_written"] == 0 and not r["problems"]:
            print(f"no JPEG exports under {exports}")
            return 2
        print(f"{r['refs_written']} refs for {len(r['photos'])} photos ({r['expected_per_photo']} expected each) → {r['refs']}")
        for s, m in r["missing"].items():
            print(f"  {s}: missing {', '.join(m)}")
        for p in r["problems"]:
            print(f"  ! {p['file']}: {p['why']}")
        return 0 if not r["problems"] and not r["missing"] else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
