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

Sweeps 4–13 (one feature each, docs/editing/prompts; the owner's steps: SWEEPS-OWNER.md) go in one
batch, a folder per sweep (the photo lists come from sweep_photos.py):

    python3 Tools/parity/lr_cc_sweep.py presets --sweep batch     (or --sweep N for one)
        → ~/LuminaEvidence/parity/sweeps/Lumina-sweeps-4-13-presets.zip: a shared Base and 206 presets
    python3 Tools/parity/lr_cc_sweep.py ingest-sweeps [~/LuminaEvidence/parity/sweeps]
        → refs/sweepNN/ from exports/sweepNN/, plus refs/sweepNN/refs.json (import_refs' index).
          A preset that moves one key is `<stem>__<Key>__<value>.jpg`; more than one,
          `<stem>__sNNpMM.jpg` + .json (sweep, preset, settings).

A Lightroom CC preset resets neither crop, masks nor healing (3 Death Valley photos' sweep-1
exports carry them), so the ingest refuses any export that has one, except sweep 13's own AI masks.
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
    if key == "SharpenRadius":
        return f"{v:+.1f}"
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


def describe(name, settings, mask=None):
    if mask:
        return f"Lumina parity sweep: a {mask[0]} mask with local exposure {mask[1]:+g} EV on the neutral base."
    if any(k in settings for k in EXT_DEFAULTS):
        moved = [f"{ref_label(k)} {fmt(k, v)}" for k, v in settings.items() if k in EXT_BASE and EXT_BASE[k] != v]
        return "Lumina parity sweep: " + (", ".join(moved) or "nothing") + " from the neutral base."
    moved = [f"{LABELS.get(k, k)} {fmt(k, v)}" for k, v in settings.items() if BASE.get(k, 0) != v and k != "WhiteBalance"]
    if name.startswith("Combo"):
        return "Lumina parity sweep: " + ", ".join(moved) + " from the neutral base."
    if settings.get("WhiteBalance") == "Custom":
        return "Lumina parity sweep: one white-balance slider from the neutral base, the other at these photos' as-shot value."
    return "Lumina parity sweep: one slider from the neutral base."


def preset_xmp(num, name, settings, group=GROUP):
    uid = hashlib.md5(f"lumina-sweep/{num}/{name}".encode()).hexdigest().upper()
    settings = dict(settings)
    mask = settings.pop("Mask", None)
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
   crs:Version="{"18.7" if mask else "15.4"}"
   crs:ProcessVersion="15.4"
{attrs}
   crs:HasSettings="True">
   <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">{title}</rdf:li></rdf:Alt></crs:Name>
   <crs:ShortName><rdf:Alt><rdf:li xml:lang="x-default"/></rdf:Alt></crs:ShortName>
   <crs:SortName><rdf:Alt><rdf:li xml:lang="x-default"/></rdf:Alt></crs:SortName>
   <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">{group}</rdf:li></rdf:Alt></crs:Group>
   <crs:Description><rdf:Alt><rdf:li xml:lang="x-default">{describe(name, settings, mask)}</rdf:li></rdf:Alt></crs:Description>
{mask_xml(mask, uid) if mask else ""}  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
"""


# MARK: sweeps 4–13 (13, the masks, further down)
#
# One feature each, defined in docs/editing/prompts (the number in brackets): 4 Texture / Clarity /
# Dehaze (02, 03), 5 HSL + B&W mix (04), 6 colour grading (05), 7 parametric curve (06),
# 8 sharpening (08, scored at 100 %), 9 noise reduction on an ISO ladder (09), 10 lens (10),
# 11 vignette (12), 12 grain (13), 13 masks (14). Every preset is the sweep-1 base plus EXT_DEFAULTS (Lightroom's
# own reset values for every key these sweeps touch, so a preset clicked on a photo that had
# something else set still lands on the same render) plus its own moves. One "Base" preset serves
# them all. The ingest names an export by the keys that differ from that base after dropping the
# keys that do nothing (`effective`), so a Lightroom that leaves an unused key out of the file, or
# keeps a hue whose saturation is 0, still matches.

HUES = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
WHEELS = [   # colour grading wheel: (name, hue key, saturation key, luminance key), Lightroom's own keys
    ("Shadows", "SplitToningShadowHue", "SplitToningShadowSaturation", "ColorGradeShadowLum"),
    ("Midtones", "ColorGradeMidtoneHue", "ColorGradeMidtoneSat", "ColorGradeMidtoneLum"),
    ("Highlights", "SplitToningHighlightHue", "SplitToningHighlightSaturation", "ColorGradeHighlightLum"),
    ("Global", "ColorGradeGlobalHue", "ColorGradeGlobalSat", "ColorGradeGlobalLum"),
]
EXT_DEFAULTS = {
    "ConvertToGrayscale": "False",
    **{f"{p}{h}": 0 for p in ("HueAdjustment", "SaturationAdjustment", "LuminanceAdjustment", "GrayMixer") for h in HUES},
    **{k: 0 for _, *keys in WHEELS for k in keys},
    "SplitToningBalance": 0, "ColorGradeBlending": 50,
    "ParametricShadowSplit": 25, "ParametricMidtoneSplit": 50, "ParametricHighlightSplit": 75,
    "SharpenRadius": 1.0, "SharpenDetail": 25, "SharpenEdgeMasking": 0,
    "LuminanceNoiseReductionDetail": 50, "LuminanceNoiseReductionContrast": 0,
    "ColorNoiseReductionDetail": 50, "ColorNoiseReductionSmoothness": 50,
    "LensManualDistortionAmount": 0, "VignetteAmount": 0, "DefringePurpleAmount": 0, "DefringeGreenAmount": 0,
    "PerspectiveVertical": 0, "PerspectiveHorizontal": 0, "PerspectiveRotate": 0, "PerspectiveScale": 100,
    "PerspectiveAspect": 0, "PerspectiveUpright": 0,
    "PostCropVignetteStyle": 1, "PostCropVignetteMidpoint": 50, "PostCropVignetteFeather": 50,
    "PostCropVignetteRoundness": 0, "PostCropVignetteHighlightContrast": 0,
    "GrainSize": 25, "GrainFrequency": 50,
}
EXT_BASE = {**BASE, **EXT_DEFAULTS}
UNIVERSE = [k for k in EXT_BASE if k != "WhiteBalance"]
EXT_GROUP = "Lumina sweeps"   # the shared Base preset's group
SWEEP_NAMES = {4: "Presence", 5: "HSL", 6: "Grade", 7: "Curve", 8: "Sharpen", 9: "Noise", 10: "Lens",
               11: "Vignette", 12: "Grain", 13: "Masks"}
FULL_SIZE = {8, 9, 10, 12}   # scored at 100 %: export full size
GRADE_SEED = 20261029
GRADE_COMBOS = 10


def grade_combos():
    """Sweep 6's ten combos: two or three wheels each (hue, saturation, sometimes luminance), and a
    blending / balance on some. Seeded like combos(): the ingest matches exports against it."""
    rnd = lcg(GRADE_SEED)

    def step(lo, hi, s):
        return int(round((lo + rnd() * (hi - lo)) / s) * s)
    out = []
    for _ in range(GRADE_COMBOS):
        wheels = list(WHEELS)
        for i in range(len(wheels) - 1, 0, -1):
            j = int(rnd() * (i + 1))
            wheels[i], wheels[j] = wheels[j], wheels[i]
        c = {}
        for _, hk, sk, lk in wheels[:2 + int(rnd() < 0.5)]:
            c[hk], c[sk] = step(0, 355, 5), step(10, 60, 5)
            if rnd() < 0.4:
                c[lk] = step(10, 40, 5) * (1 if rnd() < 0.5 else -1)
        if rnd() < 0.5:
            c["ColorGradeBlending"] = step(20, 90, 10)
        if rnd() < 0.5:
            c["SplitToningBalance"] = step(10, 50, 10) * (1 if rnd() < 0.5 else -1)
        out.append(c)
    return out


# Sweep 13 (prompt 14): Lightroom's AI masks with one local, local exposure ±1 EV, so the local's
# footprint shows the mask's shape. The structure is copied from a preset the owner saved in
# Lightroom CC 2026-10-30 ("Lumina mask probe": Select Sky, MaskSubType 2, local exposure stored as
# EV / 4). Select Subject's subtype (1) is not from a saved preset yet, and whether Lightroom re-finds
# the mask on another photo from a hand-written preset is unverified: SWEEPS-OWNER.md starts with a
# one-preset import test. The image digest Lightroom caches per photo (LocalInputDigest) is left out
# so it has to compute the mask.
MASK_SUBTYPES = {"subject": 1, "sky": 2}
LOCAL_KEYS = ["LocalExposure", "LocalHue", "LocalSaturation", "LocalContrast", "LocalClarity", "LocalSharpness",
              "LocalBrightness", "LocalToningHue", "LocalToningSaturation", "LocalExposure2012", "LocalContrast2012",
              "LocalHighlights2012", "LocalShadows2012", "LocalWhites2012", "LocalBlacks2012", "LocalClarity2012",
              "LocalDehaze", "LocalLuminanceNoise", "LocalMoire", "LocalDefringe", "LocalTemperature", "LocalTint",
              "LocalTexture", "LocalGrain", "LocalCorrectedDepth"]
LOCAL_RESTING = {"LocalCurveRefineSaturation": 100}


def mask_xml(mask, uid):
    """The MaskGroupBasedCorrections block for (kind, ev): one correction, one AI mask."""
    kind, ev = mask
    sync = hashlib.md5(f"{uid}/correction".encode()).hexdigest().upper()
    msync = hashlib.md5(f"{uid}/mask".encode()).hexdigest().upper()
    local = {**{k: 0 for k in LOCAL_KEYS}, "LocalExposure2012": ev / 4, **LOCAL_RESTING}
    attrs = "\n".join(f'       crs:{k}="{v:g}"' if k != "LocalExposure2012" else f'       crs:{k}="{v:.4f}"' for k, v in local.items())
    return f"""   <crs:MaskGroupBasedCorrections>
    <rdf:Seq>
     <rdf:li>
      <rdf:Description
       crs:What="Correction"
       crs:CorrectionAmount="1"
       crs:CorrectionActive="true"
       crs:CorrectionName="Lumina {kind}"
       crs:CorrectionSyncID="{sync}"
{attrs}>
      <crs:CorrectionMasks>
       <rdf:Seq>
        <rdf:li
         crs:What="Mask/Image"
         crs:MaskActive="true"
         crs:MaskName="{kind.capitalize()} 1"
         crs:MaskBlendMode="0"
         crs:MaskInverted="false"
         crs:MaskSyncID="{msync}"
         crs:MaskValue="1"
         crs:MaskVersion="1"
         crs:MaskSubType="{MASK_SUBTYPES[kind]}"
         crs:ReferencePoint="0.500000 0.500000"/>
       </rdf:Seq>
      </crs:CorrectionMasks>
      </rdf:Description>
     </rdf:li>
    </rdf:Seq>
   </crs:MaskGroupBasedCorrections>
"""


def read_masks(text):
    """[{"attrs": {…}, "masks": [{…}]}] per correction in a MaskGroupBasedCorrections block, or None."""
    m = re.search(r"<crs:MaskGroupBasedCorrections>(.*?)</crs:MaskGroupBasedCorrections>", text, re.S)
    if not m:
        return None
    out = []
    for c in re.finditer(r"<rdf:Description\b([^>]*?)>(.*?)</rdf:Description>", m.group(1), re.S):
        attrs = dict(re.findall(r'crs:(\w+)="([^"]*)"', c.group(1)))
        if attrs.get("What") != "Correction":
            continue
        tags = [dict(re.findall(r'crs:(\w+)="([^"]*)"', t)) for t in re.findall(r"<rdf:(?:li|Description)\b([^>]*)>", c.group(2))]
        out.append({"attrs": attrs, "masks": [t for t in tags if t.get("What", "").startswith("Mask/")]})
    return out


def mask_signature(corrections):
    """(kind, ev) when the export holds exactly what a sweep-13 preset writes, else (None, why)."""
    if len(corrections) != 1:
        return None, f"{len(corrections)} mask corrections (a sweep-13 preset writes one)"
    c = corrections[0]
    a, masks = c["attrs"], c["masks"]
    if a.get("CorrectionActive", "true") != "true" or num(a.get("CorrectionAmount", "1")) != 1:
        return None, "the mask correction is off or its amount isn't 1"
    if len(masks) != 1 or masks[0].get("What") != "Mask/Image":
        return None, "the correction's mask is not one AI mask: " + ", ".join(mk.get("What", "?") for mk in masks)
    mk = masks[0]
    if mk.get("MaskInverted", "false") != "false" or num(mk.get("MaskValue", "1")) != 1 or mk.get("MaskActive", "true") != "true":
        return None, "the mask is inverted, off or below full strength"
    kinds = {str(v): k for k, v in MASK_SUBTYPES.items()}
    kind = kinds.get(mk.get("MaskSubType"))
    if kind is None:
        return None, f"mask subtype {mk.get('MaskSubType')} is not sky or subject"
    moved = {k: num(v) for k, v in a.items() if k.startswith("Local") and k in LOCAL_KEYS and num(v) not in (None, 0)}
    if set(moved) != {"LocalExposure2012"}:
        return None, "the local moves " + (", ".join(f"{k} {v:g}" for k, v in sorted(moved.items())) or "nothing")
    return (kind, round(4 * moved["LocalExposure2012"], 1)), None


def ext_table():
    """[(sweep, group, name, moves)] for sweeps 4–13 in click order. `moves` is what the preset
    sets on top of EXT_BASE."""
    rows = []

    def add(sweep, name, moves, group=None):
        rows.append((sweep, group or f"Lumina sweep {sweep} {SWEEP_NAMES[sweep]}", name, moves))

    def one(sweep, key, values, group=None, label=None):
        for v in values:
            add(sweep, f"{label or LABELS.get(key, key)} {fmt(key, v)}", {key: v}, group)

    for key, label in (("Texture", "Texture"), ("Clarity2012", "Clarity"), ("Dehaze", "Dehaze")):
        one(4, key, [-100, -50, -25, 25, 50, 100], label=label)
    for h in HUES:
        for kind, prefix in (("Hue", "HueAdjustment"), ("Saturation", "SaturationAdjustment"), ("Luminance", "LuminanceAdjustment")):
            one(5, prefix + h, [-50, 50], group=f"Lumina sweep 5 HSL {h}", label=f"{h} {kind}")
    bw = {"ConvertToGrayscale": "True"}
    add(5, "B&W", bw, "Lumina sweep 5 B&W")
    for h in HUES:
        for v in (-50, 50):
            add(5, f"B&W {h} {fmt('', v)}", {**bw, f"GrayMixer{h}": v}, "Lumina sweep 5 B&W")
    for wheel, hk, sk, lk in WHEELS:
        for hue in (30, 120, 210, 300):
            for sat in (25, 50):
                add(6, f"{wheel} hue {hue} sat {sat}", {hk: hue, sk: sat})
        for v in (-50, 50):
            add(6, f"{wheel} lum {fmt('', v)}", {lk: v})
    split = {"SplitToningShadowHue": 210, "SplitToningShadowSaturation": 40, "SplitToningHighlightHue": 40, "SplitToningHighlightSaturation": 40}
    add(6, "Split 210/40", split)
    for v in (25, 75):
        add(6, f"Split 210/40 blending {v}", {**split, "ColorGradeBlending": v})
    for v in (-50, 50):
        add(6, f"Split 210/40 balance {fmt('', v)}", {**split, "SplitToningBalance": v})
    for n, c in enumerate(grade_combos(), 1):
        add(6, f"Grade combo {n:02d}", c)
    for region in ("Shadows", "Darks", "Lights", "Highlights"):
        one(7, "Parametric" + region, [-50, 50], label=region)
    for split_key, region, values in (("ParametricShadowSplit", "Shadows", (15, 40)), ("ParametricMidtoneSplit", "Darks", (35, 65)),
                                      ("ParametricHighlightSplit", "Highlights", (60, 90))):
        for v in values:
            add(7, f"{region} +50, {split_key[10:]} {v}", {"Parametric" + region: 50, split_key: v})
    for amount in (40, 80, 150):
        for radius in (0.5, 1.0, 2.0):
            add(8, f"Sharpness {amount} radius {radius:g}", {"Sharpness": amount, **({"SharpenRadius": radius} if radius != 1.0 else {})})
    for key, label, values in (("SharpenDetail", "detail", (0, 100)), ("SharpenEdgeMasking", "masking", (50, 100))):
        for v in values:
            add(8, f"Sharpness 80 {label} {v}", {"Sharpness": 80, key: v})
    one(9, "LuminanceSmoothing", [25, 50, 75], label="Luminance NR")
    one(9, "ColorNoiseReduction", [0, 50], label="Colour NR")
    for v in (0, 50):
        add(9, f"Luminance NR 50 colour NR {v}", {"LuminanceSmoothing": 50, "ColorNoiseReduction": v})
    add(10, "Remove CA", {"AutoLateralCA": 1})
    one(10, "LensManualDistortionAmount", [-50, 50], label="Distortion")
    add(10, "Lens profile + remove CA", {**LENS, "AutoLateralCA": 1})
    one(10, "DefringePurpleAmount", [10], label="Defringe purple")
    one(10, "DefringeGreenAmount", [10], label="Defringe green")
    one(11, "PostCropVignetteAmount", [-100, -50, 50, 100], label="Vignette")
    for key, label, values in (("PostCropVignetteMidpoint", "midpoint", (0, 100)), ("PostCropVignetteFeather", "feather", (0, 100)),
                               ("PostCropVignetteRoundness", "roundness", (-100, 100)), ("PostCropVignetteHighlightContrast", "highlights", (50,))):
        for v in values:
            add(11, f"Vignette -50 {label} {fmt('', v)}", {"PostCropVignetteAmount": -50, key: v})
    for amount in (25, 50, 100):
        for size in (25, 75):
            for rough in (25, 75):
                add(12, f"Grain {amount} size {size} roughness {rough}", {"GrainAmount": amount, "GrainSize": size, "GrainFrequency": rough})
    for kind in ("sky", "subject"):
        for ev in (-1.0, 1.0):
            add(13, f"{kind.capitalize()} local exposure {ev:+g}", {"Mask": (kind, ev)}, f"Lumina sweep 13 {kind.capitalize()}")
    return rows


def ext_presets(sweeps=None):
    """(file number, preset name, settings, group) in click order for the given sweeps (default
    4–13), led by the shared Base."""
    out = [("00", "Base", dict(EXT_BASE), EXT_GROUP)]
    counts = {}
    for sweep, group, name, moves in ext_table():
        if sweeps and sweep not in sweeps:
            continue
        counts[sweep] = counts.get(sweep, 0) + 1
        out.append((f"{sweep}-{counts[sweep]:02d}", name, {**EXT_BASE, **moves}, group))
    return out


def _value(v):
    if isinstance(v, str):
        b = {"true": 1.0, "false": 0.0}.get(v.strip().lower())
        if b is not None:
            return b
        try:
            return float(v)
        except ValueError:
            return None
    return float(v)


def effective(settings):
    """{key: number} over UNIVERSE, missing keys at their base value, without the keys that do
    nothing in this combination (a hue whose saturation is 0, sharpening radius at Sharpness 0, …)."""
    s = {k: _value(settings.get(k, EXT_BASE[k])) for k in UNIVERSE}
    s = {k: (round(v, 2) if v is not None else None) for k, v in s.items()}

    def drop(*keys):
        for k in keys:
            s.pop(k, None)
    if not s.get("Sharpness"):
        drop("SharpenRadius", "SharpenDetail", "SharpenEdgeMasking")
    if not s.get("LuminanceSmoothing"):
        drop("LuminanceNoiseReductionDetail", "LuminanceNoiseReductionContrast")
    if not s.get("ColorNoiseReduction"):
        drop("ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness")
    if not s.get("GrainAmount"):
        drop("GrainSize", "GrainFrequency")
    if not s.get("PostCropVignetteAmount"):
        drop(*[k for k in s if k.startswith("PostCropVignette") and k != "PostCropVignetteAmount"])
    if not s.get("ConvertToGrayscale"):
        drop(*[k for k in list(s) if k.startswith("GrayMixer")])
    if not any(s.get("Parametric" + r) for r in ("Shadows", "Darks", "Lights", "Highlights")):
        drop("ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit")
    for _, hk, sk, lk in WHEELS:
        if not s.get(sk):
            drop(hk)
    if not any(s.get(k) for _, _, sk, lk in WHEELS for k in (sk, lk)):
        drop("ColorGradeBlending", "SplitToningBalance")
    if not s.get("LensProfileEnable"):
        pass   # the profile's own scales are not in UNIVERSE
    return s


EXT_BASE_EFFECTIVE = effective(EXT_BASE)


def moves_of(settings):
    """{key: value} that differ from the base, after effective()."""
    e = effective(settings)
    return {k: v for k, v in e.items() if v != EXT_BASE_EFFECTIVE.get(k, _value(EXT_BASE[k]))}


def _signature(moves):
    return tuple(sorted(moves.items()))


def ext_positions():
    """[(sweep, group, name, moves, signature)], the table the ingest matches against."""
    out = []
    for sweep, group, name, m in ext_table():
        mv = moves_of({**EXT_BASE, **m})
        out.append((sweep, group, name, mv, (_signature(mv), m.get("Mask"))))
    return out


def ref_label(key):
    return {"Clarity2012": "Clarity"}.get(key, LABELS.get(key, key))


def write_presets(out, sweep=1, as_shot=None):
    if sweep == "batch" or (isinstance(sweep, int) and sweep >= 4):
        table = ext_presets(None if sweep == "batch" else {sweep})
        zname = "Lumina-sweeps-4-13-presets.zip" if sweep == "batch" else f"Lumina-sweep{sweep}-presets.zip"
    else:
        group, table, zname = {1: lambda: (GROUP, presets(), "Lumina-sweep-presets.zip"),
                               2: lambda: (GROUP2, presets2(), "Lumina-sweep2-presets.zip"),
                               3: lambda: (GROUP3, presets3(as_shot), "Lumina-sweep3-wb-presets.zip")}[sweep]()
        table = [(n, name, s, group) for n, name, s in table]
    d = os.path.join(out, "presets")
    os.makedirs(d, exist_ok=True)
    for stale in os.listdir(d):   # an earlier table's presets (other photos, other numbering)
        if stale.endswith(".xmp") and not stale.startswith("._"):   # ._ : the T7's AppleDouble stubs, gone with their file
            try:
                os.remove(os.path.join(d, stale))
            except FileNotFoundError:
                pass
    files = []
    for num_, name, settings, group in table:
        path = os.path.join(d, f"{num_} {name.replace('/', '-')}.xmp")
        with open(path, "w", encoding="utf-8") as f:
            f.write(preset_xmp(num_, name, settings, group))
        files.append((path, group))
    z = os.path.join(out, zname)
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        for p, group in files:
            zf.write(p, os.path.join(group, os.path.basename(p)))
    return [p for p, _ in files], z


# MARK: ingest

XMP_RE = re.compile(rb"<x:xmpmeta.*?</x:xmpmeta>", re.S)


def read_xmp(path):
    """Every crs:* setting in a JPEG's XMP packet (attribute or element form), as strings."""
    with open(path, "rb") as f:
        data = f.read()
    m = XMP_RE.search(data)
    if not m:
        return None
    return read_xmp_text(m.group(0).decode("utf-8", "replace"))


def read_xmp_text(text):
    """read_xmp on an XMP packet already in hand. A correction's own crs:Local* attributes are not
    top-level settings; they are read into MaskCorrections."""
    top = re.sub(r"<crs:(\w*BasedCorrections|RetouchAreas)>.*?</crs:\1>", "", text, flags=re.S)
    out = {k: v for k, v in re.findall(r'crs:(\w+)="([^"]*)"', top)}
    out.update({k: v for k, v in re.findall(r"<crs:(\w+)>([^<]*)</crs:\1>", text)})
    local = re.findall(r"<crs:(\w*BasedCorrections|RetouchAreas)>\s*<rdf:Seq>\s*<rdf:li", text)
    if local:
        out["Local"] = ", ".join(sorted(set(local)))
        masks = read_masks(text)
        if masks:
            out["MaskCorrections"] = masks
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
    if crs.get("MaskCorrections"):
        return classify_mask(crs)
    moved_ext = moves_of(crs)
    if any(k not in SLIDER_KEYS and k != "LensProfileEnable" for k in moved_ext):
        return classify_ext(crs, moved_ext)
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


POSITIONS = None   # ext_positions(), built on first use
BY_SIGNATURE = None


def positions():
    global POSITIONS, BY_SIGNATURE
    if POSITIONS is None:
        POSITIONS = ext_positions()
        BY_SIGNATURE = {p[4]: i for i, p in enumerate(POSITIONS)}
    return POSITIONS


def classify_ext(crs, moved):
    """An export that moves a key of sweeps 4–13: ('pos', index into positions()) or (None, why)."""
    positions()
    said = ", ".join(f"{k} {v:g}" if v is not None else f"{k} {crs.get(k)!r}" for k, v in sorted(moved.items()))
    mode = crs.get("WhiteBalance", "As Shot")
    if mode != "As Shot":
        return None, f"white balance is {mode} with {said} (sweeps 4–13 keep it As Shot)"
    i = BY_SIGNATURE.get((_signature(moved), None))
    if i is None:
        return None, f"{said}: not a position of sweeps 4–13"
    return ("pos", i), None


def classify_mask(crs):
    """An export with a mask correction: a sweep-13 position on the base, or (None, why)."""
    positions()
    sig, why = mask_signature(crs["MaskCorrections"])
    if sig is None:
        return None, f"masked: {why}"
    moved = moves_of(crs)
    if moved or crs.get("WhiteBalance", "As Shot") != "As Shot" or num(crs.get("LensProfileEnable")) == 1:
        return None, f"a {sig[0]} mask on top of other changes (sweep 13 masks the neutral base)"
    i = BY_SIGNATURE.get(((), sig))
    if i is None:
        return None, f"a {sig[0]} mask with local exposure {sig[1]:+g} EV: not a sweep-13 position"
    return ("pos", i), None


def preset_number(i):
    """'4-03' for positions()[i], as ext_presets() numbers the file."""
    sweep = positions()[i][0]
    return f"{sweep}-{sum(1 for p in POSITIONS[:i + 1] if p[0] == sweep):02d}"


def jpeg_size(path):
    """(width, height) from the first SOF marker, or None."""
    with open(path, "rb") as f:
        data = f.read(1 << 20)
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            return None
        marker, length = data[i + 1], int.from_bytes(data[i + 2:i + 4], "big")
        if marker in (0xC0, 0xC1, 0xC2):
            return int.from_bytes(data[i + 7:i + 9], "big"), int.from_bytes(data[i + 5:i + 7], "big")
        if marker in (0xD9, 0xDA):
            return None
        i += 2 + length
    return None


def not_clean(crs, masks_ok=False):
    """Why an export carries an edit no preset resets (crop, local corrections, a point curve), or None.
    `masks_ok`: AI-mask corrections are sweep 13's own (classify_mask judges them)."""
    if crs.get("HasCrop") == "True":
        return "the photo is cropped (presets don't reset crop): remove the crop and re-export"
    local = crs.get("Local")
    if masks_ok and local == "MaskGroupBasedCorrections" and crs.get("MaskCorrections"):
        local = None
    if local:
        return f"the photo has local edits ({crs['Local']}): use an unedited copy and re-export"
    if crs.get("ToneCurveName2012", "Linear") != "Linear":
        return f"point curve {crs['ToneCurveName2012']} (the sweeps keep it Linear): reset the curve and re-export"
    return None


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


def ingest(exports, refs, sweep=None, only=None):
    """`sweep`: 1 or 2 says which preset set to expect (for the missing list); None works it out
    from what is there. An export from either set is recognised either way. `exports` is a folder
    or a list of folders, read as one. `only` (4–13): the folder is that sweep's, so an export of
    another sweep's preset is named, and full size is checked where the sweep is scored at 100 %.
    A photo with exports of sweeps 4–13 is expected to have the base and every preset of the
    groups it was given; the sweep-1 / sweep-2 list only if it has their exports too."""
    folders = [exports] if isinstance(exports, str) else list(exports)
    exports = folders[0] if len(folders) == 1 else folders
    os.makedirs(refs, exist_ok=True)
    table = combos()
    pos = positions()
    ext_moves = [m for *_, m in ext_table()]
    wanted = {1: wanted_for(1, table), 2: wanted_for(2, table)}
    found, problems, files = {}, [], []
    for root, names in ((r, ns) for folder in folders for r, _, ns in os.walk(folder)):
        for n in sorted(names):
            if n.startswith(".") or not n.lower().endswith((".jpg", ".jpeg")):
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

    groups = {}
    for n, path, crs, stem in files:
        def bad(why):
            problems.append({"file": n, "raw": crs["RawFileName"], "why": why})
        why = not_clean(crs, masks_ok=True)
        if why:
            bad(why)
            continue
        kind, why = classify(crs, as_shot.get(stem), table)
        if kind is None:
            bad(why)
            continue
        if only and isinstance(kind, tuple) and kind[0] == "pos" and pos[kind[1]][0] != only:
            bad(f"preset {preset_number(kind[1])} {pos[kind[1]][2]} is sweep {pos[kind[1]][0]}'s, in the sweep {only} folder: move it")
            continue
        if only in FULL_SIZE:
            size = jpeg_size(path)
            if size and max(size) < 4000:
                bad(f"exported at {max(size)} px: sweep {only} is scored at 100 %, export Full size")
                continue
        profile = crs.get("LookName") or crs.get("CameraProfile") or ""
        ok = ("Adobe Color", "Adobe Standard") + (("Adobe Monochrome",) if _value(crs.get("ConvertToGrayscale", "False")) else ())
        if profile and profile not in ok:
            bad(f"profile {profile} (expected Adobe Color)")
        side = None
        if isinstance(kind, tuple) and kind[0] == "pos":
            i = kind[1]
            sweep_n, group, name, mv, _ = pos[i]
            number_ = preset_number(i)
            if len(mv) == 1:
                (k, v), = mv.items()
                dest = f"{stem}__{ref_label(k)}__{value_name(v)}.jpg"
            else:
                dest = f"{stem}__s{sweep_n:02d}p{number_.split('-')[1]}.jpg"
                m = ext_moves[i]
                settings = ({"Mask": m["Mask"][0], "LocalExposure": number(m["Mask"][1])} if "Mask" in m else
                            {ref_label(k): number(_value(v)) for k, v in m.items()})
                side = {"sweep": sweep_n, "preset": f"{number_} {name}", "settings": settings}
            key = (stem, "pos", i)
            groups.setdefault(stem, set()).add(group)
        elif isinstance(kind, tuple) and kind[0] == "combo":
            dest, key = f"{stem}__combo{kind[1]:02d}.jpg", (stem,) + kind
            side = {"settings": {k: number(v) for k, v in table[kind[1] - 1].items()}}
            if stem in as_shot:
                side["asShot"] = as_shot_record(as_shot[stem], profiles[stem])
        elif isinstance(kind, tuple):
            slider, v = kind
            if (slider, float(v)) not in wanted[1] | wanted[2]:
                bad(f"{slider} {v:g} is not a sweep position")
                continue
            dest, key = f"{stem}__{slider}__{value_name(v)}.jpg", (stem, slider, float(v))
        else:
            dest, key = f"{stem}__{kind}.jpg", (stem, kind)
        if key in found:
            if kind != "base":   # a photo in two sweep-5 albums gets Base exported twice: the same render
                bad(f"duplicate of {found[key]} (kept the first)")
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
    old = {k[0] for k in found if k[1] not in ("pos", "base")}
    missing = {}
    for s in stems:
        want = wanted[sweep] if s in old or (s not in groups and not only) else {("base",)}
        m = [" ".join(str(x) for x in w) for w in sorted(want, key=str) if (s,) + w not in found]
        if only and s not in groups:
            m.append(f"every preset of sweep {only}")
        m += [f"{preset_number(i)} {p[2]}" for i, p in enumerate(pos) if p[1] in groups.get(s, ()) and (s, "pos", i) not in found]
        if m:
            missing[s] = m
    report = {"exports": exports, "refs": refs, "sweep": only or sweep, "photos": stems, "refs_written": len(found),
              "expected_per_photo": len(wanted[sweep]), "missing": missing, "problems": problems,
              "groups": {s: sorted(g) for s, g in sorted(groups.items())},
              "asShot": {s: as_shot_record(as_shot[s], profiles[s]) for s in stems if s in as_shot}}
    with open(os.path.join(refs, "sweep-ingest.json"), "w") as f:
        json.dump(report, f, indent=1)
    return report


SWEEP_DIR = re.compile(r"^sweep0*(\d+)$")


def ingest_sweeps(root):
    """Every <root>/exports/sweepNN folder → <root>/refs/sweepNN (refs + sweep-ingest.json) and
    <root>/refs/sweepNN/refs.json (import_refs' index). [(N, report)] in sweep order."""
    import import_refs
    out = []
    ex = os.path.join(root, "exports")
    for name in sorted(os.listdir(ex), key=lambda n: int(SWEEP_DIR.match(n).group(1)) if SWEEP_DIR.match(n) else 1e9):
        m = SWEEP_DIR.match(name)
        if not m or not os.path.isdir(os.path.join(ex, name)):
            continue
        n = int(m.group(1))
        refs = os.path.join(root, "refs", f"sweep{n:02d}")
        r = ingest(os.path.join(ex, name), refs, only=n if n >= 4 else None)
        try:
            data = import_refs.index(refs)
        except ImportError:   # no Pillow: index without the image headers
            data = import_refs.index(refs, read_info=False)
        with open(os.path.join(refs, "refs.json"), "w") as f:
            json.dump(data, f, indent=1, sort_keys=True)
        out.append((n, r))
    return out


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


SWEEPS_ROOT = os.path.expanduser("~/LuminaEvidence/parity/sweeps")


def sweep_arg(v):
    if v == "batch":
        return v
    n = int(v)
    if not 1 <= n <= 13:
        raise argparse.ArgumentTypeError("1 … 13 or batch")
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("presets")
    p.add_argument("--sweep", type=sweep_arg, default=1,
                   help="1: the single sliders; 2: base + combos; 3: white balance, per photo; 4–13: one feature's sweep; "
                        "batch: 4–13 in one zip (what the owner imports)")
    p.add_argument("--out", help="default: ~/LuminaEvidence/parity/sweep, …/sweep2 for --sweep 2, <refs>/../../sweep3 for --sweep 3, "
                                 "…/sweeps for batch, …/sweeps/sweepNN for 4–13")
    p.add_argument("--refs", default=os.path.expanduser("~/LuminaEvidence/parity/sweep2/refs"),
                   help="--sweep 3: the refs folder whose <stem>__asshot.json files say each photo's as-shot white balance")
    i = sub.add_parser("ingest")
    i.add_argument("exports", nargs="+", help="one or more folders of JPEG exports, read as one")
    i.add_argument("--refs", default=os.path.expanduser("~/LuminaEvidence/parity/refs"))
    i.add_argument("--sweep", type=int, choices=(1, 2), help="which preset set to expect (default: worked out from the exports)")
    i.add_argument("--only", type=int, choices=range(4, 14), metavar="4…13", help="the folder holds this sweep's exports only")
    b = sub.add_parser("ingest-sweeps", help="every <root>/exports/sweepNN → <root>/refs/sweepNN + refs.json (after the batch)")
    b.add_argument("root", nargs="?", default=SWEEPS_ROOT)
    a = ap.parse_args(argv)
    paths = ([a.out, a.refs if a.sweep == 3 else None] if a.cmd == "presets" else
             [a.root] if a.cmd == "ingest-sweeps" else list(a.exports) + [a.refs])
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
        elif a.sweep == "batch" or a.sweep >= 4:
            out = os.path.expanduser(a.out or (SWEEPS_ROOT if a.sweep == "batch" else os.path.join(SWEEPS_ROOT, f"sweep{a.sweep:02d}")))
        else:
            out = os.path.expanduser(a.out or ("~/LuminaEvidence/parity/sweep" if a.sweep == 1 else "~/LuminaEvidence/parity/sweep2"))
        files, z = write_presets(out, a.sweep, as_shot)
        print(f"{len(files)} presets → {os.path.dirname(files[0])}\nimport this in Lightroom: {z}")
    elif a.cmd == "ingest-sweeps":
        root = os.path.expanduser(a.root)
        if not os.path.isdir(os.path.join(root, "exports")):
            print(f"no folder {os.path.join(root, 'exports')}: export each sweep into exports/sweepNN first")
            return 2
        done = ingest_sweeps(root)
        if not done:
            print(f"no exports/sweepNN folders under {root}")
            return 2
        bad = 0
        for n, r in done:
            tail = "".join(f", {len(r[k])} {w}" for k, w in (("missing", "photos missing presets"), ("problems", "problems")) if r[k])
            print(f"sweep {n}: {r['refs_written']} refs for {len(r['photos'])} photos → {r['refs']}{tail}")
            for s, m in r["missing"].items():
                print(f"  {s}: missing {', '.join(m)}")
            for p in r["problems"]:
                print(f"  ! {p['file']}: {p['why']}")
            bad += bool(r["missing"] or r["problems"])
        return 1 if bad else 0
    else:
        exports = [os.path.expanduser(e) for e in a.exports]
        for e in exports:
            if not os.path.isdir(e):
                print(f"no folder {e}: export from Lightroom into it first (see the presets step)")
                return 2
        r = ingest(exports, os.path.expanduser(a.refs), a.sweep, a.only)
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
