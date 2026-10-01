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

Sweep 2 (`presets --sweep 2`, group "Lumina sweep 2", ~/LuminaEvidence/parity/sweep2) is the base
and ten three-slider combos; sweep 3 (`presets --sweep 3`, group "Lumina sweep 3 WB") is white
balance, Temperature and Tint alone, in ~/LuminaEvidence/parity/sweep3. The ingest takes both
export folders at once (the white balance exports need the as-shot values the others carry):

    python3 Tools/parity/lr_cc_sweep.py presets --sweep 2
    python3 Tools/parity/lr_cc_sweep.py ingest ~/LuminaEvidence/parity/sweep2/exports --refs ~/LuminaEvidence/parity/sweep2/refs
        → also <stem>__combo<NN>.jpg + .json ({"settings": …}) and <stem>__asshot.json (Lightroom's
          as-shot Temperature / Tint, which every As Shot export carries; parity.py turns absolute
          Kelvin into a delta with it).
    python3 Tools/parity/lr_cc_sweep.py presets --sweep 3 [--refs ~/LuminaEvidence/parity/sweep2/refs]
        → <refs>/../../sweep3/presets + Lumina-sweep3-wb-presets.zip, made from the
          <stem>__asshot.json files.
    python3 Tools/parity/lr_cc_sweep.py ingest ~/LuminaEvidence/parity/sweep2/exports ~/LuminaEvidence/parity/sweep3/exports --refs ~/LuminaEvidence/parity/sweep2/refs
        → adds <stem>__Temperature__<K>.jpg and <stem>__Tint__<v>.jpg.

White balance presets are per photo. Lightroom CC ignores a preset that sets only Temperature or
only Tint (measured 2026-09-30: every photo comes out at Custom 5500 / +10, whatever the preset
said), so a Temperature preset must also carry the photo's as-shot Tint, and a Tint preset its
as-shot Temperature, which is what the Classic plug-in does per photo. Photos that share the
as-shot value share a preset; each preset names the photos it is for, and the ingest checks every
export against the as-shot values, so a preset clicked on the wrong photo is named, not ingested.
Combos that move white balance set both numbers and are the same for every photo.
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
LABELS = {key: label for label, key, _ in SWEEP}
GROUP = "Lumina sweep"

# Sweep 3. White balance: absolute Kelvin / Tint, four of the plug-in's ten positions each.
WB_SWEEP = [
    ("Temperature", "Temperature", [3200, 4000, 6500, 10000]),
    ("Tint", "Tint", [-60, -20, 20, 60]),
]
GROUP2 = "Lumina sweep 2"
GROUP3 = "Lumina sweep 3 WB"

# Combos: three sliders each, moderate values (sign random, magnitude lo … hi in steps). Seeded,
# so the table is the same on every run: the ingest matches exports against it. Changing the seed,
# the ranges or the counts after presets were imported into Lightroom orphans those exports.
COMBO_SEED = 20260930
COMBOS = 10
WB_COMBOS = 3       # the last ones: Temperature + Tint + one other slider
COMBO_TONE = [      # (label, key, lo, hi, step); every one appears in three combos
    ("Exposure", "Exposure2012", 0.3, 1.0, 0.05),
    ("Contrast", "Contrast2012", 10, 40, 5),
    ("Highlights", "Highlights2012", 20, 60, 5),
    ("Shadows", "Shadows2012", 20, 60, 5),
    ("Whites", "Whites2012", 10, 40, 5),
    ("Blacks", "Blacks2012", 10, 40, 5),
    ("Vibrance", "Vibrance", 10, 40, 5),
    ("Saturation", "Saturation", 10, 30, 5),
]
COMBO_KELVIN = (3800, 8000, 50)   # uniform in mired between the two
COMBO_TINT = (10, 35, 5)


def lcg(seed):
    """Sweep.lua's generator: the same numbers on every Python."""
    state = [seed]

    def rnd():
        state[0] = (state[0] * 1103515245 + 12345) % 2147483648
        return state[0] / 2147483648
    return rnd


def combos():
    """[{label: value}], three sliders each, in combo order (combo01 first)."""
    rnd = lcg(COMBO_SEED)

    def pick(lo, hi, step):
        v = round((lo + rnd() * (hi - lo)) / step) * step
        return round(v if rnd() < 0.5 else -v, 2)

    slots = len(COMBO_TONE) * 3
    assert slots == WB_COMBOS + 3 * (COMBOS - WB_COMBOS)
    while True:   # each tone slider three times over the table, never twice in one combo
        deck = [t for t in COMBO_TONE for _ in range(3)]
        for i in range(slots - 1, 0, -1):
            j = int(rnd() * (i + 1))
            deck[i], deck[j] = deck[j], deck[i]
        plain = [deck[i:i + 3] for i in range(0, slots - WB_COMBOS, 3)]
        if all(len({t[0] for t in c}) == 3 for c in plain):
            break
    out = [{label: pick(lo, hi, step) for label, _, lo, hi, step in c} for c in plain]
    for label, _, lo, hi, step in deck[slots - WB_COMBOS:]:
        klo, khi, kstep = COMBO_KELVIN
        mired = 1e6 / khi + rnd() * (1e6 / klo - 1e6 / khi)
        out.append({label: pick(lo, hi, step), "Temperature": int(round(1e6 / mired / kstep) * kstep), "Tint": pick(*COMBO_TINT)})
    return out


COMBO_KEYS = {label: key for label, key, _, _, _ in COMBO_TONE}
COMBO_KEYS.update(Temperature="Temperature", Tint="Tint")


def combo_settings(combo):
    """The preset for one combo: the base plus its sliders, white balance Custom if it moves it."""
    s = {**BASE, **{COMBO_KEYS[label]: v for label, v in combo.items()}}
    if "Temperature" in combo:
        s["WhiteBalance"] = "Custom"
    return s


def fmt(key, v):
    if isinstance(v, str):
        return v
    if key == "Exposure2012":
        return f"{v:+.2f}"
    if key == "Temperature":
        return str(int(v))
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


def presets2():
    """Sweep 2 in click order: the base, then the combos."""
    out = [("Base", dict(BASE))] + [(f"Combo {n:02d}", combo_settings(c)) for n, c in enumerate(combos(), 1)]
    return [(f"2-{n:02d}", name, settings) for n, (name, settings) in enumerate(out, 1)]


def presets3(as_shot):
    """Sweep 3, white balance, from {stem: (Temperature, Tint)} as shot. One round per position:
    a preset per group of photos that share the other as-shot value, which the preset keeps."""
    out = []
    for label, key, values in WB_SWEEP:
        other, idx = ("Tint", 1) if label == "Temperature" else ("Temperature", 0)
        groups = {}
        for stem in sorted(as_shot):
            groups.setdefault(as_shot[stem][idx], []).append(stem)
        for v in values:
            for keep, stems in sorted(groups.items(), key=lambda g: g[1]):
                out.append((f"{label} {fmt(key, v)} for {' + '.join(stems)}", {**BASE, "WhiteBalance": "Custom", key: v, other: keep}))
    return [(f"3-{n:02d}", name, settings) for n, (name, settings) in enumerate(out, 1)]


def read_as_shot(refs):
    """{stem: (Temperature, Tint)} from the <stem>__asshot.json files an ingest wrote."""
    out = {}
    for n in sorted(os.listdir(refs)) if os.path.isdir(refs) else []:
        if n.endswith("__asshot.json"):
            with open(os.path.join(refs, n)) as f:
                d = json.load(f)
            out[n[: -len("__asshot.json")]] = (d["Temperature"], d["Tint"])
    return out


def describe(name, settings):
    moved = [f"{LABELS.get(k, k)} {fmt(k, v)}" for k, v in settings.items() if BASE.get(k, 0) != v and k != "WhiteBalance"]
    if name.startswith("Combo"):
        return "Lumina parity sweep: " + ", ".join(moved) + " from the neutral base."
    if settings.get("WhiteBalance") == "Custom":
        return "Lumina parity sweep: one white-balance slider from the neutral base, the other at these photos' as-shot value."
    return "Lumina parity sweep: one slider from the neutral base."


def preset_xmp(num, name, settings, group=GROUP):
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
   <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">{group}</rdf:li></rdf:Alt></crs:Group>
   <crs:Description><rdf:Alt><rdf:li xml:lang="x-default">{describe(name, settings)}</rdf:li></rdf:Alt></crs:Description>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
"""


def write_presets(out, sweep=1, as_shot=None):
    group, table, zname = {1: lambda: (GROUP, presets(), "Lumina-sweep-presets.zip"),
                           2: lambda: (GROUP2, presets2(), "Lumina-sweep2-presets.zip"),
                           3: lambda: (GROUP3, presets3(as_shot), "Lumina-sweep3-wb-presets.zip")}[sweep]()
    d = os.path.join(out, "presets")
    os.makedirs(d, exist_ok=True)
    for stale in os.listdir(d):   # an earlier table's presets (other photos, other numbering)
        if stale.endswith(".xmp"):
            os.remove(os.path.join(d, stale))
    files = []
    for num, name, settings in table:
        path = os.path.join(d, f"{num} {name}.xmp")
        with open(path, "w", encoding="utf-8") as f:
            f.write(preset_xmp(num, name, settings, group))
        files.append(path)
    z = os.path.join(out, zname)
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in files:
            zf.write(p, os.path.join(group, os.path.basename(p)))
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


def as_shot_of(crs):
    """(Temperature, Tint) an As Shot export carries, or None."""
    if crs.get("WhiteBalance", "As Shot") != "As Shot":
        return None
    t, tint = num(crs.get("Temperature")), num(crs.get("Tint"))
    return (t, tint) if t is not None and tint is not None else None


def same(a, b):
    return set(a) == set(b) and all(abs(a[k] - b[k]) < 1e-6 for k in a)


def classify(crs, as_shot=None, table=None):
    """('base' | 'baseLens' | (slider, value) | ('combo', n)) or (None, why). `as_shot` is the
    photo's (Temperature, Tint) from one of its As Shot exports; `table` is combos()."""
    table = combos() if table is None else table
    lens = num(crs.get("LensProfileEnable")) == 1
    moved = [(k, num(crs.get(k))) for k in SLIDER_KEYS if num(crs.get(k)) not in (None, 0)]
    tone = {LABELS[k]: v for k, v in moved}
    for k in ("Texture", "Clarity2012", "Dehaze"):
        if num(crs.get(k)) not in (None, 0):
            return None, f"{k} is {crs.get(k)} (the sweep keeps it 0)"
    mode = crs.get("WhiteBalance", "As Shot")
    if mode not in ("As Shot", "Custom"):
        return None, f"white balance is {mode} (the sweep keeps it As Shot, or Custom from a preset)"
    if lens and (moved or mode == "Custom"):
        return None, "lens corrections on together with a slider"
    if mode == "Custom":
        return classify_wb(crs, tone, as_shot, table)
    if not moved:
        return ("baseLens" if lens else "base"), None
    if len(moved) > 1:
        for n, c in enumerate(table, 1):
            if "Temperature" not in c and same(c, tone):
                return ("combo", n), None
        return None, "more than one slider moved: " + ", ".join(f"{k}={v:g}" for k, v in moved) + " (not one of the combos)"
    key, v = moved[0]
    return (LABELS[key], v), None


def classify_wb(crs, tone, as_shot, table):
    """An export with white balance Custom: a combo with white balance, or Temperature / Tint
    alone with the other one as shot."""
    t, tint = num(crs.get("Temperature")), num(crs.get("Tint"))
    if t is None or tint is None:
        return None, "white balance Custom without Temperature / Tint in the file"
    here = {**tone, "Temperature": t, "Tint": tint}
    for n, c in enumerate(table, 1):
        if "Temperature" in c and same(c, here):
            return ("combo", n), None
    wb = f"Temperature {t:g}, Tint {tint:+g}"
    if tone:
        return None, f"{wb} with " + ", ".join(f"{k} {v:g}" for k, v in sorted(tone.items())) + ": not one of the combos"
    if as_shot is None:
        return None, f"{wb}, but no As Shot export of this photo says what its as-shot values are: export the Base preset too"
    t0, tint0 = as_shot
    positions = {label: values for label, _, values in WB_SWEEP}
    hits = []
    if tint == tint0 and t in positions["Temperature"]:
        hits.append(("Temperature", t))
    if t == t0 and tint in positions["Tint"]:
        hits.append(("Tint", tint))
    if len(hits) == 1:
        return hits[0], None
    if hits:
        return None, f"{wb} is both a Temperature and a Tint position for this photo (as shot {t0:g} / {tint0:+g})"
    if (t, tint) == (5500, 10):
        return None, (f"{wb} is Lightroom's default Custom white balance: the preset set only Temperature or only Tint, "
                      "and Lightroom ignores that. Use the per-photo presets (presets --sweep 3)")
    if t in positions["Temperature"] or tint in positions["Tint"]:
        return None, (f"{wb}, but this photo is {t0:g} / {tint0:+g} as shot: that is another photo's white-balance preset. "
                      "Click this photo's own preset and re-export")
    return None, f"{wb} is not a sweep position (as shot {t0:g} / {tint0:+g})"


def wanted_for(sweep, table):
    if sweep == 1:
        return {("base",), ("baseLens",)} | {(l, float(v)) for l, _, vs in SWEEP for v in vs}
    return ({("base",)} | {(l, float(v)) for l, _, vs in WB_SWEEP for v in vs}
            | {("combo", n) for n in range(1, len(table) + 1)})


def number(v):
    return int(v) if float(v).is_integer() else v


def ingest(exports, refs, sweep=None):
    """`sweep`: 1 or 2 says which preset set to expect (for the missing list); None works it out
    from what is there. An export from either set is recognised either way. `exports` is a folder
    or a list of folders, read as one."""
    folders = [exports] if isinstance(exports, str) else list(exports)
    exports = folders[0] if len(folders) == 1 else folders
    os.makedirs(refs, exist_ok=True)
    table = combos()
    wanted = {1: wanted_for(1, table), 2: wanted_for(2, table)}
    found, problems, files = {}, [], []
    for root, names in ((r, ns) for folder in folders for r, _, ns in os.walk(folder)):
        for n in sorted(names):
            if not n.lower().endswith((".jpg", ".jpeg")):
                continue
            path = os.path.join(root, n)
            crs = read_xmp(path)
            if crs is None or "RawFileName" not in crs:
                problems.append({"file": n, "why": "no Camera Raw settings in the file: export with Metadata ▸ All metadata"})
                continue
            files.append((n, path, crs, os.path.splitext(crs["RawFileName"])[0]))

    # Lightroom's as-shot white balance per photo, from the exports that kept it as shot.
    as_shot, profiles = {}, {}
    for n, _, crs, stem in files:
        v = as_shot_of(crs)
        if v is None:
            continue
        if stem in as_shot and as_shot[stem] != v:
            problems.append({"file": n, "raw": crs["RawFileName"], "why": f"as-shot white balance {v[0]:g} / {v[1]:+g} differs from "
                             f"{as_shot[stem][0]:g} / {as_shot[stem][1]:+g} in another export of this photo (kept the first)"})
            continue
        if stem not in as_shot:
            as_shot[stem] = v
            profiles[stem] = {"profile": crs.get("LookName") or crs.get("CameraProfile") or "", "processVersion": crs.get("ProcessVersion", "")}

    for n, path, crs, stem in files:
        kind, why = classify(crs, as_shot.get(stem), table)
        if kind is None:
            problems.append({"file": n, "raw": crs["RawFileName"], "why": why})
            continue
        profile = crs.get("LookName") or crs.get("CameraProfile") or ""
        if profile and profile not in ("Adobe Color", "Adobe Standard"):
            problems.append({"file": n, "raw": crs["RawFileName"], "why": f"profile {profile} (expected Adobe Color)"})
        side = None
        if isinstance(kind, tuple) and kind[0] == "combo":
            dest, key = f"{stem}__combo{kind[1]:02d}.jpg", (stem,) + kind
            side = {"settings": {k: number(v) for k, v in table[kind[1] - 1].items()}}
            if stem in as_shot:
                side["asShot"] = as_shot_record(as_shot[stem], profiles[stem])
        elif isinstance(kind, tuple):
            slider, v = kind
            if (slider, float(v)) not in wanted[1] | wanted[2]:
                problems.append({"file": n, "raw": crs["RawFileName"], "why": f"{slider} {v:g} is not a sweep position"})
                continue
            dest, key = f"{stem}__{slider}__{value_name(v)}.jpg", (stem, slider, float(v))
        else:
            dest, key = f"{stem}__{kind}.jpg", (stem, kind)
        if key in found:
            problems.append({"file": n, "raw": crs["RawFileName"], "why": f"duplicate of {found[key]} (kept the first)"})
            continue
        shutil.copyfile(path, os.path.join(refs, dest))
        if side:
            with open(os.path.join(refs, os.path.splitext(dest)[0] + ".json"), "w") as f:
                json.dump(side, f, indent=1, sort_keys=True)
        found[key] = n
    stems = sorted({k[0] for k in found})
    for s in stems:
        if s in as_shot:   # what import_refs attaches to every ref of the photo as "asShot"
            with open(os.path.join(refs, f"{s}__asshot.json"), "w") as f:
                json.dump(as_shot_record(as_shot[s], profiles[s]), f, indent=1, sort_keys=True)
    if sweep is None:
        sweep = 2 if any(k[1:] in wanted[2] - wanted[1] for k in found) else 1
    missing = {s: [" ".join(str(x) for x in w) for w in sorted(wanted[sweep], key=str)
                   if (s,) + w not in found] for s in stems}
    report = {"exports": exports, "refs": refs, "sweep": sweep, "photos": stems, "refs_written": len(found),
              "expected_per_photo": len(wanted[sweep]), "missing": {s: m for s, m in missing.items() if m}, "problems": problems,
              "asShot": {s: as_shot_record(as_shot[s], profiles[s]) for s in stems if s in as_shot}}
    with open(os.path.join(refs, "sweep-ingest.json"), "w") as f:
        json.dump(report, f, indent=1)
    return report


def as_shot_record(v, extra):
    """<stem>__asshot.json as Sweep.lua writes it (the keys parity.py reads: Temperature, Tint)."""
    return {"Temperature": number(v[0]), "Tint": number(v[1]), **{k: x for k, x in extra.items() if x}}


def unplugged(path):
    """Why `path` can't be used, when one of its folders is a symlink whose target is missing (the
    sweep folders may live on an external drive behind a symlink), else None. Without this a run
    with the drive unplugged reads as "no exports" or dies inside makedirs."""
    p = os.path.abspath(os.path.expanduser(path))
    parts = []
    while p != os.path.dirname(p):
        parts.append(p)
        p = os.path.dirname(p)
    for p in reversed(parts):
        if os.path.islink(p) and not os.path.exists(p):
            return f"{p} is a link to {os.readlink(p)}, which is not there: plug the drive in (nothing was read or written)"
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("presets")
    p.add_argument("--sweep", type=int, choices=(1, 2, 3), default=1, help="1: the single sliders; 2: base + combos; 3: white balance, per photo")
    p.add_argument("--out", help="default: ~/LuminaEvidence/parity/sweep, …/sweep2 for --sweep 2, <refs>/../../sweep3 for --sweep 3")
    p.add_argument("--refs", default=os.path.expanduser("~/LuminaEvidence/parity/sweep2/refs"),
                   help="--sweep 3: the refs folder whose <stem>__asshot.json files say each photo's as-shot white balance")
    i = sub.add_parser("ingest")
    i.add_argument("exports", nargs="+", help="one or more folders of JPEG exports, read as one")
    i.add_argument("--refs", default=os.path.expanduser("~/LuminaEvidence/parity/refs"))
    i.add_argument("--sweep", type=int, choices=(1, 2), help="which preset set to expect (default: worked out from the exports)")
    a = ap.parse_args(argv)
    paths = [a.out, a.refs if a.sweep == 3 else None] if a.cmd == "presets" else list(a.exports) + [a.refs]
    for why in filter(None, (unplugged(p) for p in paths if p)):
        print(why)
        return 2
    if a.cmd == "presets":
        as_shot = None
        if a.sweep == 3:
            refs = os.path.expanduser(a.refs)
            as_shot = read_as_shot(refs)
            if not as_shot:
                print(f"no <stem>__asshot.json under {refs}: export the Base preset and run ingest first")
                return 2
            out = os.path.expanduser(a.out) if a.out else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(refs))), "sweep3")
        else:
            out = os.path.expanduser(a.out or ("~/LuminaEvidence/parity/sweep" if a.sweep == 1 else "~/LuminaEvidence/parity/sweep2"))
        files, z = write_presets(out, a.sweep, as_shot)
        print(f"{len(files)} presets → {os.path.dirname(files[0])}\nimport this in Lightroom: {z}")
    else:
        exports = [os.path.expanduser(e) for e in a.exports]
        for e in exports:
            if not os.path.isdir(e):
                print(f"no folder {e}: export from Lightroom into it first (see the presets step)")
                return 2
        r = ingest(exports, os.path.expanduser(a.refs), a.sweep)
        if r["refs_written"] == 0 and not r["problems"]:
            print(f"no JPEG exports under {', '.join(exports)}")
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
