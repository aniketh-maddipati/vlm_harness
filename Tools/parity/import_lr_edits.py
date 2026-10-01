#!/usr/bin/env python3
"""Lightroom (CC or Classic) exports of your own edits → parity references (`<stem>__editNN`).

    python3 Tools/parity/import_lr_edits.py --exports <folder of exported JPEGs> --raws <folder of ARWs>
                                            [--out ~/LuminaEvidence/parity-personal/refs]
                                            [--render-bin Tools/parity/lumina-render/.build/release/lumina-render]

Lightroom CC has no catalog to sweep, but every export carries its develop settings in the JPEG's
XMP (`crs:*`, Process Version 2012 / 15.x) and the RAW it came from (`crs:RawFileName`; virtual
copies share `xmpMM:OriginalDocumentID`). This reads that XMP (pure Python, no exiftool), maps
the settings Lumina can express to a look string, and lists the ones it can't. For each export it
writes into --out:

    <stem>__editNN.jpg    a symlink to the export (the reference pixels, 8-bit sRGB)
    <stem>__editNN.json   {"settings": Lightroom names, "look": look string, "bucket", "features", …}

then indexes the folder with import_refs.py (→ <out>/../refs.json). `parity_personal.py` renders
and scores them; `make parity-personal` runs both.

Buckets (each export lands in exactly one):
    as-shot               no tone or colour setting moved from Lightroom's default (crop allowed):
                          the gap between Apple's RAW development and Lightroom's default render
    basic-only            only settings Lumina has (Exposure, WB, Contrast, Highlights, Shadows,
                          Whites, Blacks, Vibrance, Saturation, Clarity, Sharpening, post-crop
                          vignette, luminance NR, crop)
    unsupported-features  anything else that changes pixels (tone curve, HSL, colour grading,
                          calibration, profile other than Adobe Color, masks, retouch, lens blur,
                          AI denoise, texture, dehaze, grain, perspective …); still scored, flagged
"Minor" features (lens profile on, colour NR, sharpening detail) are reported but don't move an
export out of its bucket: they are Lightroom defaults or invisible at the 1024 px comparison.

White balance: Lightroom writes its own as-shot Kelvin for "As Shot" exports; Apple's
CIRAWFilter estimates a different one. For "As Shot" exports the look has no `wb` (Apple's as
shot). For anything else Lightroom's as-shot isn't in the file, so it is estimated from Apple's
as-shot plus the median mired / tint offset between the two over this set's "As Shot" exports,
and the look moves Apple's as-shot by Lightroom's delta (parity.lr_to_look, as the sweep does).

Photos and names stay out of the repo: --out defaults to $LUMINA_PERSONAL_SET/refs
(~/LuminaEvidence/parity-personal/refs).
"""
import argparse
import json
import math
import os
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

NS = {
    "crs": "http://ns.adobe.com/camera-raw-settings/1.0/",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "xmpMM": "http://ns.adobe.com/xap/1.0/mm/",
    "x": "adobe:ns:meta/",
    "aux": "http://ns.adobe.com/exif/1.0/aux/",
}
RDF = "{%s}" % NS["rdf"]
CRS = "{%s}" % NS["crs"]
XMP_SIG = b"http://ns.adobe.com/xap/1.0/\x00"
EXT_SIG = b"http://ns.adobe.com/xmp/extension/\x00"
RAW_EXTS = ("ARW", "arw", "DNG", "dng", "CR3", "cr3", "NEF", "nef", "RAF", "raf")


def personal_root():
    return os.path.expanduser(os.environ.get("LUMINA_PERSONAL_SET", "~/LuminaEvidence/parity-personal"))


# ---- reading XMP out of a JPEG --------------------------------------------------------------------

def jpeg_xmp(data):
    """(main packet, extended packet or '') from JPEG bytes: the APP1 XMP segment plus the
    ExtendedXMP chunks (Adobe XMP spec part 3: GUID, full length, offset, then the bytes),
    reassembled by offset. Lightroom moves large structures (masks, retouch) into the extension."""
    if data[:2] != b"\xff\xd8":
        raise ValueError("not a JPEG")
    i, main, ext = 2, "", {}
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            break
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        if marker in (0xDA, 0xD9):  # start of scan: no metadata after it
            break
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        body = data[i + 4:i + 2 + length]
        if marker == 0xE1:
            if body.startswith(XMP_SIG):
                main = body[len(XMP_SIG):].decode("utf-8", errors="replace")
            elif body.startswith(EXT_SIG):
                rest = body[len(EXT_SIG):]
                guid, total, offset = rest[:32].decode("ascii", "replace"), struct.unpack(">I", rest[32:36])[0], struct.unpack(">I", rest[36:40])[0]
                ext.setdefault(guid, {"total": total, "chunks": {}})["chunks"][offset] = rest[40:]
        i += 2 + length
    extended = ""
    for guid, e in ext.items():
        blob = b"".join(e["chunks"][o] for o in sorted(e["chunks"]))
        extended += blob.decode("utf-8", errors="replace")
    return main, extended


def read_xmp_file(path):
    with open(path, "rb") as f:
        return jpeg_xmp(f.read())


def _value(elem):
    """An XMP property element → str, list (rdf:Seq/Bag/Alt) or dict (a structure)."""
    for kind in ("Seq", "Bag", "Alt"):
        container = elem.find(RDF + kind)
        if container is not None:
            return [_value(li) if (len(li) or any(k.startswith(CRS) for k in li.attrib)) else (li.text or "") for li in container.findall(RDF + "li")]
    desc = elem.find(RDF + "Description")
    node = desc if desc is not None else elem
    fields = {}
    for k, v in node.attrib.items():
        if k.startswith(CRS):
            fields[k[len(CRS):]] = v
    for child in node:
        if child.tag.startswith(CRS):
            fields[child.tag[len(CRS):]] = _value(child)
    if fields or len(node):
        return fields
    return (elem.text or "").strip()


def parse_packet(text):
    """crs:* at the top level of every rdf:Description, plus xmpMM:OriginalDocumentID."""
    out = {}
    if not text.strip():
        return out
    start = text.find("<x:xmpmeta")
    end = text.rfind("</x:xmpmeta>")
    if start >= 0 and end > start:
        text = text[start:end + len("</x:xmpmeta>")]
    root = ET.fromstring(text)
    rdf = root if root.tag == RDF + "RDF" else root.find(RDF + "RDF")
    if rdf is None:
        return out
    for desc in rdf.findall(RDF + "Description"):
        for k, v in desc.attrib.items():
            if k.startswith(CRS):
                out[k[len(CRS):]] = v
            elif k == "{%s}OriginalDocumentID" % NS["xmpMM"]:
                out["_OriginalDocumentID"] = v
            elif k == "{%s}Lens" % NS["aux"]:
                out["_Lens"] = v
        for child in desc:
            if child.tag.startswith(CRS):
                out[child.tag[len(CRS):]] = _value(child)
            elif child.tag == "{%s}OriginalDocumentID" % NS["xmpMM"]:
                out["_OriginalDocumentID"] = (child.text or "").strip()
    return out


def parse_crs(main, extended=""):
    crs = parse_packet(main)
    for k, v in parse_packet(extended).items():
        crs.setdefault(k, v)
    return crs


# ---- settings --------------------------------------------------------------------------------------

def num(v, default=None):
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(str(v).strip().replace("+", ""))
    except ValueError:
        return default


def truthy(v):
    return str(v).strip().lower() in ("true", "1")


# crs name → (Lightroom slider name as import_refs / parity.LR_KEYS spell it, Lightroom default, look key)
SUPPORTED = [
    ("Exposure2012", "Exposure", 0.0, "ev"),
    ("Contrast2012", "Contrast", 0.0, "con"),
    ("Highlights2012", "Highlights", 0.0, "hl"),
    ("Shadows2012", "Shadows", 0.0, "sh"),
    ("Whites2012", "Whites", 0.0, "wh"),
    ("Blacks2012", "Blacks", 0.0, "bl"),
    ("Vibrance", "Vibrance", 0.0, "vib"),
    ("Saturation", "Saturation", 0.0, "sat"),
    ("Clarity2012", "Clarity", 0.0, "clr"),
    ("Sharpness", "Sharpness", 40.0, "shp"),
    ("PostCropVignetteAmount", "PostCropVignette", 0.0, "vig"),
    ("LuminanceSmoothing", "LuminanceNR", 0.0, "nr"),
]
SLIDER_KEYS = {name: key for _, name, _, key in SUPPORTED}
SLIDER_KEYS.update({"Temperature": "wb", "Tint": "wb"})
DEFAULT_PROFILE = ("Adobe Standard", "Adobe Color")  # PV 15's default: the Adobe Standard DCP + the Adobe Color look

IDENTITY_CURVE = [(0.0, 0.0), (255.0, 255.0)]


def curve_points(v):
    if not v:
        return IDENTITY_CURVE
    pts = []
    for item in v if isinstance(v, list) else [v]:
        parts = [p for p in re.split(r"[,\s]+", str(item).strip()) if p]
        for a, b in zip(parts[0::2], parts[1::2]):
            pts.append((float(a), float(b)))
    return pts or IDENTITY_CURVE


def is_identity_curve(v):
    return all(abs(x - y) < 0.5 for x, y in curve_points(v))


def nonzero(crs, *names):
    return [n for n in names if abs(num(crs.get(n), 0.0)) > 1e-9]


def _nonempty(v):
    if isinstance(v, list):
        return len(v) > 0
    if isinstance(v, dict):
        return len(v) > 0
    return bool(str(v or "").strip())


HSL = [f"{kind}Adjustment{c}" for kind in ("Hue", "Saturation", "Luminance") for c in ("Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta")]
GRADING = ["SplitToningShadowSaturation", "SplitToningHighlightSaturation", "ColorGradeMidtoneSat", "ColorGradeGlobalSat",
           "ColorGradeShadowLum", "ColorGradeMidtoneLum", "ColorGradeHighlightLum", "ColorGradeGlobalLum"]
CALIBRATION = ["ShadowTint", "RedHue", "RedSaturation", "GreenHue", "GreenSaturation", "BlueHue", "BlueSaturation"]
PARAMETRIC = ["ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights"]
LOCAL = ["MaskGroupBasedCorrections", "GradientBasedCorrections", "CircularGradientBasedCorrections", "PaintBasedCorrections"]
PERSPECTIVE_DEFAULTS = {"PerspectiveVertical": 0, "PerspectiveHorizontal": 0, "PerspectiveRotate": 0, "PerspectiveAspect": 0,
                        "PerspectiveScale": 100, "PerspectiveX": 0, "PerspectiveY": 0, "LensManualDistortionAmount": 0}


def profile_of(crs):
    look = crs.get("Look")
    look_name = look.get("Name") if isinstance(look, dict) else crs.get("LookName")
    return str(crs.get("CameraProfile") or ""), str(look_name or "")


def features(crs):
    """(major, minor): lists of what Lumina can't express. Major changes pixels at the 1024 px
    comparison and moves the export to `unsupported-features`; minor is reported only."""
    major, minor = [], []
    if nonzero(crs, "Texture"):
        major.append("texture")
    if nonzero(crs, "Dehaze"):
        major.append("dehaze")
    curves = [crs.get(n) for n in ("ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue")]
    if any(c is not None and not is_identity_curve(c) for c in curves) or nonzero(crs, *PARAMETRIC):
        major.append("toneCurve")
    if nonzero(crs, *HSL):
        major.append("hsl")
    if nonzero(crs, *GRADING):
        major.append("colorGrading")
    if nonzero(crs, *CALIBRATION):
        major.append("calibration")
    camera, look = profile_of(crs)
    if (camera, look) != DEFAULT_PROFILE and not (camera == "" and look == ""):
        major.append("profile")
    if abs(num(crs.get("LookAmount"), 1.0) - 1.0) > 1e-6 and look:
        major.append("profileAmount")
    if truthy(crs.get("ConvertToGrayscale")):
        minor.append("grayscaleMix")  # bw:1 is set; Lightroom's B&W mixer is not modelled
    if any(_nonempty(crs.get(n)) for n in LOCAL):
        major.append("masks")
    if _nonempty(crs.get("RetouchAreas")) or _nonempty(crs.get("RetouchInfo")):
        major.append("retouch")
    lens_blur = crs.get("LensBlur")
    if isinstance(lens_blur, dict) and truthy(lens_blur.get("Active")):
        major.append("lensBlur")
    filters = crs.get("FilterList")
    if isinstance(filters, dict):
        for f in filters.get("Filters") or []:
            if isinstance(f, dict):
                title = str(f.get("Title", ""))
                major.append("aiDenoise" if "Denoise" in title else "filter:" + str(f.get("Name", "?")))
    if nonzero(crs, "GrainAmount"):
        major.append("grain")
    if str(crs.get("PerspectiveUpright", "0")) not in ("0", "Off", "") or any(abs(num(crs.get(k), d) - d) > 1e-9 for k, d in PERSPECTIVE_DEFAULTS.items()):
        major.append("perspective")
    if nonzero(crs, "VignetteAmount"):
        major.append("lensVignetteManual")
    if nonzero(crs, "DefringePurpleAmount", "DefringeGreenAmount"):
        major.append("defringe")
    if nonzero(crs, "HDREditMode"):
        major.append("hdr")
    pv = str(crs.get("ProcessVersion", ""))
    if pv and num(pv, 0) < 10:
        major.append("processVersion")
    # minor
    if truthy(crs.get("LensProfileEnable")):
        minor.append("lensProfile")
    if truthy(crs.get("AutoLateralCA")):
        minor.append("chromaticAberration")
    if abs(num(crs.get("ColorNoiseReduction"), 25.0) - 25.0) > 1e-9:
        minor.append("colorNR")
    if (abs(num(crs.get("SharpenRadius"), 1.0) - 1.0) > 1e-6 or abs(num(crs.get("SharpenDetail"), 25.0) - 25.0) > 1e-6
            or abs(num(crs.get("SharpenEdgeMasking"), 0.0)) > 1e-6):
        minor.append("sharpenDetail")
    if abs(num(crs.get("PostCropVignetteAmount"), 0.0)) > 1e-9 and (
            abs(num(crs.get("PostCropVignetteMidpoint"), 50) - 50) > 1e-6 or abs(num(crs.get("PostCropVignetteFeather"), 50) - 50) > 1e-6
            or abs(num(crs.get("PostCropVignetteRoundness"), 0)) > 1e-6 or abs(num(crs.get("PostCropVignetteStyle"), 1) - 1) > 1e-6
            or abs(num(crs.get("PostCropVignetteHighlightContrast"), 0)) > 1e-6):
        minor.append("vignetteShape")
    if abs(num(crs.get("CropAngle"), 0.0)) > 1e-6:
        minor.append("straighten")  # passed through as crop rotate; its sign is not verified against Lightroom yet
    return major, minor


def settings(crs):
    """The settings Lumina has, under Lightroom's slider names; Temperature/Tint only when the
    white balance isn't As Shot. Values at Lightroom's default are kept (the look writes them)."""
    out = {}
    for crs_name, name, default, _ in SUPPORTED:
        out[name] = num(crs.get(crs_name), default)
    wb = str(crs.get("WhiteBalance", "As Shot"))
    if wb != "As Shot":
        t = num(crs.get("Temperature"))
        if t is None:
            t = num(crs.get("ColorTemperature"))
        if t is not None:
            out["Temperature"] = t
        tint = num(crs.get("Tint"))
        if tint is not None:
            out["Tint"] = tint
    return out


def changed(crs, s=None):
    """Lightroom slider names that moved from their default (crop not included)."""
    s = s if s is not None else settings(crs)
    moved = [name for _, name, default, _ in SUPPORTED if abs(s.get(name, default) - default) > 1e-9]
    if "Temperature" in s or "Tint" in s:
        moved.append("WhiteBalance")
    return moved


def bucket(major, moved):
    if major:
        return "unsupported-features"
    return "basic-only" if moved else "as-shot"


# ---- crop ------------------------------------------------------------------------------------------

def crop_upright(crs, orientation=1):
    """Lightroom's crop (fractions of the RAW in its stored orientation: CropLeft/Top/Right/Bottom)
    → Lumina's (x, y, w, h, rotate) as fractions of the upright frame, or None for the whole frame.
    EXIF orientation 1 (normal), 3 (180°), 6 (display rotated 90° CW), 8 (90° CCW)."""
    if not truthy(crs.get("HasCrop", "False")):
        return None
    left, top = num(crs.get("CropLeft"), 0.0), num(crs.get("CropTop"), 0.0)
    right, bottom = num(crs.get("CropRight"), 1.0), num(crs.get("CropBottom"), 1.0)
    angle = num(crs.get("CropAngle"), 0.0)
    if orientation == 3:
        x0, x1, y0, y1 = 1 - right, 1 - left, 1 - bottom, 1 - top
    elif orientation == 6:  # stored (x, y) shows at (1 - y, x)
        x0, x1, y0, y1 = 1 - bottom, 1 - top, left, right
    elif orientation == 8:  # stored (x, y) shows at (y, 1 - x)
        x0, x1, y0, y1 = top, bottom, 1 - right, 1 - left
    else:
        x0, x1, y0, y1 = left, right, top, bottom
    x0, y0 = max(0.0, x0), max(0.0, y0)
    x1, y1 = min(1.0, x1), min(1.0, y1)
    if x0 < 1e-4 and y0 < 1e-4 and x1 > 1 - 1e-4 and y1 > 1 - 1e-4 and abs(angle) < 1e-6:
        return None
    return (round(x0, 6), round(y0, 6), round(x1 - x0, 6), round(y1 - y0, 6), angle)


def render_px(crop, upright_size, compare_px=1024, step=64):
    """Develop size so the cropped frame's long edge is at least compare_px (rounded up to `step`,
    capped at the RAW's own long edge)."""
    w, h = upright_size
    long_edge = max(w, h)
    if not crop:
        need = compare_px
    else:
        cw, ch = crop[2] * w, crop[3] * h
        need = compare_px * long_edge / max(1.0, max(cw, ch))
    px = int(math.ceil(need / step) * step)
    return int(min(long_edge, max(compare_px, px))) if long_edge else px


# ---- white balance ---------------------------------------------------------------------------------

def wb_calibration(pairs):
    """pairs: [(lr_as_shot (K, tint), apple_as_shot (K, tint))] from As Shot exports → the median
    mired and tint offset (Lightroom − Apple) and their spread (MAD)."""
    if not pairs:
        return {"n": 0, "mired": 0.0, "tint": 0.0, "miredMAD": None, "tintMAD": None}
    dm = sorted(1e6 / lr[0] - 1e6 / ap[0] for lr, ap in pairs)
    dt = sorted(lr[1] - ap[1] for lr, ap in pairs)

    def med(v):
        n = len(v)
        return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])
    m, t = med(dm), med(dt)
    return {"n": len(pairs), "mired": m, "tint": t, "miredMAD": med(sorted(abs(x - m) for x in dm)), "tintMAD": med(sorted(abs(x - t) for x in dt))}


def lr_as_shot_estimate(apple, cal):
    """Lightroom's as-shot (K, tint) estimated from Apple's with the set's calibration."""
    mired = 1e6 / apple[0] + cal["mired"]
    return (1e6 / max(mired, 20.0), apple[1] + cal["tint"])


def build_look(s, crop, apple_as_shot, lr_as_shot, grayscale=False):
    import lookmath
    import parity
    look = parity.lr_to_look({k: v for k, v in s.items() if k in parity.LR_KEYS or k in ("Temperature", "Tint")},
                             {"Temperature": lr_as_shot[0], "Tint": lr_as_shot[1]} if lr_as_shot else {}, apple_as_shot)
    look["vig"] = float(s.get("PostCropVignette", 0.0))
    nr = float(s.get("LuminanceNR", 0.0))
    look["nr"] = nr if nr > 0 else None  # Lightroom's 0 is its default: leave Apple's default NR, as a fresh Lumina look does
    look["bw"] = bool(grayscale)
    look["crop"] = crop
    return lookmath.format_look(look)


# ---- matching and the run --------------------------------------------------------------------------

def find_raw(name, raws_dir):
    stem = os.path.splitext(os.path.basename(name))[0]
    for ext in RAW_EXTS:
        p = os.path.join(raws_dir, f"{stem}.{ext}")
        if os.path.exists(p):
            return p
    return None


def match(export_name, crs, raws_dir):
    """The RAW an export came from: crs:RawFileName first, then the export's own name without
    Lightroom's '-2' virtual-copy suffix. (path or None, how)."""
    raw_name = crs.get("RawFileName")
    if raw_name:
        p = find_raw(raw_name, raws_dir)
        if p:
            return p, "RawFileName"
    stem = re.sub(r"-\d+$", "", os.path.splitext(os.path.basename(export_name))[0])
    p = find_raw(stem, raws_dir)
    return (p, "filename") if p else (None, None)


def apple_as_shot(render_bin, raws, cache_path):
    """{raw path: {asShot: (K, tint), width, height, orientation}} from `lumina-render asshot`
    (metadata only), cached by (path, size, mtime)."""
    cache = {}
    if os.path.exists(cache_path):
        try:
            cache = json.load(open(cache_path))
        except ValueError:
            cache = {}

    def sig(p):
        st = os.stat(p)
        return f"{st.st_size}:{int(st.st_mtime)}"
    todo = [p for p in raws if cache.get(p, {}).get("sig") != sig(p)]
    if todo:
        out = subprocess.run([render_bin, "asshot"] + todo, capture_output=True, text=True).stdout
        for line in out.splitlines():
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("ok"):
                cache[d["image"]] = {"sig": sig(d["image"]), "asShot": [d["asShot"]["kelvin"], d["asShot"]["tint"]],
                                     "width": d["width"], "height": d["height"], "orientation": d.get("orientation", 1)}
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, "w") as f:
            json.dump(cache, f, indent=1, sort_keys=True)
    return cache


def run(exports_dir, raws_dir, out_dir, render_bin, compare_px=1024):
    t0 = time.time()
    names = sorted(n for n in os.listdir(exports_dir) if n.lower().endswith((".jpg", ".jpeg")) and not n.startswith("."))
    frames, skipped = [], []
    for n in names:
        path = os.path.join(exports_dir, n)
        try:
            crs = parse_crs(*read_xmp_file(path))
        except Exception as e:  # a JPEG without XMP, or broken XML
            skipped.append({"export": n, "why": f"xmp: {e}"})
            continue
        if not crs:
            skipped.append({"export": n, "why": "no crs settings"})
            continue
        raw, how = match(n, crs, raws_dir)
        if not raw:
            skipped.append({"export": n, "why": f"no RAW for {crs.get('RawFileName') or n}"})
            continue
        frames.append({"export": n, "exportPath": os.path.abspath(path), "raw": raw, "matchedBy": how, "crs": crs})
    t_xmp = time.time() - t0

    t1 = time.time()
    meta = apple_as_shot(render_bin, sorted({f["raw"] for f in frames}), os.path.join(os.path.dirname(out_dir), "cache", "asshot.json"))
    t_asshot = time.time() - t1

    pairs = []
    for f in frames:
        m = meta.get(f["raw"])
        if m and str(f["crs"].get("WhiteBalance", "As Shot")) == "As Shot":
            t = num(f["crs"].get("Temperature"))
            tint = num(f["crs"].get("Tint"))
            if t and tint is not None:
                pairs.append(((t, tint), tuple(m["asShot"])))
    cal = wb_calibration(pairs)

    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if "__edit" in old:
            os.remove(os.path.join(out_dir, old))
    per_stem, docs, written = {}, {}, []
    for f in frames:
        m = meta.get(f["raw"])
        if not m:
            skipped.append({"export": f["export"], "why": "Core Image can't read the RAW"})
            continue
        crs = f["crs"]
        stem = os.path.splitext(os.path.basename(f["raw"]))[0]
        per_stem[stem] = per_stem.get(stem, 0) + 1
        ident = f"{stem}__edit{per_stem[stem]:02d}"
        s = settings(crs)
        major, minor = features(crs)
        moved = changed(crs, s)
        crop = crop_upright(crs, m.get("orientation", 1))
        apple = tuple(m["asShot"])
        lr_shot = None
        if "Temperature" in s or "Tint" in s:
            lr_shot = lr_as_shot_estimate(apple, cal)
        look = build_look(s, crop, apple, lr_shot, grayscale=truthy(crs.get("ConvertToGrayscale")))
        doc = crs.get("_OriginalDocumentID") or ""
        docs.setdefault(doc or ident, []).append(ident)
        side = {
            "settings": s, "look": look, "bucket": bucket(major, moved), "features": major, "minor": minor, "changed": moved,
            "crop": list(crop) if crop else None, "renderPx": render_px(crop, (m["width"], m["height"]), compare_px),
            "raw": f["raw"], "export": f["export"], "matchedBy": f["matchedBy"], "documentID": doc,
            "whiteBalance": str(crs.get("WhiteBalance", "As Shot")),
            "appleAsShot": list(apple), "lrAsShot": list(lr_shot) if lr_shot else None,
            "lrAsShotSource": "calibrated" if lr_shot else None,
            "profile": list(profile_of(crs)), "processVersion": str(crs.get("ProcessVersion", "")),
            "orientation": m.get("orientation", 1), "upright": [m["width"], m["height"]], "lens": crs.get("_Lens", ""),
        }
        link = os.path.join(out_dir, ident + os.path.splitext(f["export"])[1].lower())
        os.symlink(f["exportPath"], link)
        with open(os.path.join(out_dir, ident + ".json"), "w") as fh:
            json.dump(side, fh, indent=1, sort_keys=True)
        written.append(ident)
    for ident_list in docs.values():
        if len(ident_list) > 1:
            for ident in ident_list:
                p = os.path.join(out_dir, ident + ".json")
                d = json.load(open(p))
                d["virtualCopies"] = len(ident_list)
                json.dump(d, open(p, "w"), indent=1, sort_keys=True)

    import import_refs
    t2 = time.time()
    data = import_refs.index(out_dir)
    data["wbCalibration"] = cal
    data["skipped"] = skipped
    data["timing"] = {"xmpSeconds": t_xmp, "asShotSeconds": t_asshot, "indexSeconds": time.time() - t2}
    refs_json = os.path.join(os.path.dirname(os.path.abspath(out_dir)), "refs.json")
    with open(refs_json, "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
    return data, refs_json


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exports", required=True, help="folder of Lightroom-exported JPEGs (XMP embedded)")
    ap.add_argument("--raws", required=True, help="folder of the RAWs they came from")
    ap.add_argument("--out", default=None, help="default: $LUMINA_PERSONAL_SET/refs")
    ap.add_argument("--render-bin", default=os.path.join(HERE, "lumina-render", ".build", "release", "lumina-render"))
    ap.add_argument("--compare-px", type=int, default=1024)
    a = ap.parse_args(argv)
    out = os.path.expanduser(a.out or os.path.join(personal_root(), "refs"))
    data, refs_json = run(os.path.expanduser(a.exports), os.path.expanduser(a.raws), out, a.render_bin, a.compare_px)
    edits = [r for r in data["refs"] if r["kind"] == "edit"]
    by_bucket = {}
    for r in edits:
        by_bucket[r.get("bucket")] = by_bucket.get(r.get("bucket"), 0) + 1
    cal = data["wbCalibration"]
    print(f"{refs_json}: {len(edits)} edits of {data['counts']['images']} RAWs · " + " · ".join(f"{k} {v}" for k, v in sorted(by_bucket.items()))
          + f" · skipped {len(data['skipped'])}")
    if cal["n"]:
        print(f"white balance: Lightroom − Apple as shot over {cal['n']} As Shot exports: {cal['mired']:+.1f} mired (MAD {cal['miredMAD']:.1f}), tint {cal['tint']:+.1f} (MAD {cal['tintMAD']:.1f})")
    for s in data["skipped"]:
        print(f"  skipped {s['export']}: {s['why']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
