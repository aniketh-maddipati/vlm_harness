#!/usr/bin/env python3
"""numpy mirror of Lumina/Sets/Look/LookMath.swift, coefficient for coefficient.

Used by fit.py (a stage's transfer function fitted against Lightroom's sweep without rendering
through Core Image per evaluation) and checked against the real graph with

    lumina-render ramp --out ramp.json && python3 Tools/parity/lookmath.py --check ramp.json

which fails when the Metal/Swift chain and this file disagree by more than 1 %. Every function
takes linear values in the working space (sRGB primaries) and the rules dict from rules-v1.json.
Point stages take arrays of shape (..., 3); the blur-based stages take the pixel and its base.
"""
import json
import sys

import numpy as np

STAGES = ["exposure", "whiteBalance", "whitesBlacks", "tone", "contrast", "colour", "clarity", "sharpen", "vignette"]
LR_SLIDERS = ["Exposure", "Temperature", "Tint", "Contrast", "Highlights", "Shadows", "Whites", "Blacks",
              "Vibrance", "Saturation", "Clarity", "Sharpness"]
# which stage a Lightroom slider exercises
SLIDER_STAGE = {"Exposure": "exposure", "Temperature": "whiteBalance", "Tint": "whiteBalance", "Contrast": "contrast",
                "Highlights": "tone", "Shadows": "tone", "Whites": "whitesBlacks", "Blacks": "whitesBlacks",
                "Vibrance": "colour", "Saturation": "colour", "Clarity": "clarity", "Sharpness": "sharpen"}


def k(rules, stage, name, fallback):
    return float(rules["stages"].get(stage, {}).get("coefficients", {}).get(name, fallback))


def gamma(rules):
    return float(rules.get("perceptualGamma", 2.2))


def luma_weights(rules):
    return np.asarray(rules.get("luma", [0.2126, 0.7152, 0.0722]), dtype=np.float64)


def luma(rgb, rules):
    return np.tensordot(rgb, luma_weights(rules), axes=([-1], [0]))


def smoothstep(e0, e1, x):
    x = np.asarray(x, dtype=np.float64)
    if e1 <= e0:
        return (x >= e1).astype(np.float64)
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def perceptual(x, rules):
    return np.power(np.maximum(0.0, x), 1.0 / gamma(rules))


def linear(p, rules):
    return np.power(np.maximum(0.0, p), gamma(rules))


# ---- look strings ---------------------------------------------------------------------------

def parse_look(s):
    """The look string → dict (the twelve sliders + bw). Mirrors Look.parse, without clamping."""
    look = {"ev": 0.0, "wb": None, "con": 0.0, "hl": 0.0, "sh": 0.0, "wh": 0.0, "bl": 0.0, "vib": 0.0, "sat": 0.0,
            "clr": 0.0, "shp": 0.0, "vig": 0.0, "bw": False, "crop": None, "nr": None, "rot": 0}
    s = (s or "").strip()
    if s in ("", "none"):
        return look
    for tok in s.split():
        key, _, raw = tok.partition(":")
        if key == "wb":
            kv, tint = raw.split("/")
            look["wb"] = (float(kv), float(tint))
        elif key == "bw":
            look["bw"] = raw in ("1", "true")
        elif key == "nr":
            # Detail ▸ luminance noise reduction: a develop (RAW stage) parameter, not a look stage.
            look["nr"] = min(100.0, max(0.0, float(raw)))
        elif key == "crop":
            box, _, rot = raw.partition("/")
            x, y, w, h = (float(v) for v in box.split(","))
            look["crop"] = (x, y, w, h, float(rot) if rot else 0.0)
        elif key == "rot":
            # A quarter turn, clockwise: geometry like the crop (applied after it), no colour maths.
            v = float(raw)
            if v != round(v) or int(v) % 90:
                raise ValueError(f"rot wants 0, 90, 180 or 270, got {raw!r}")
            look["rot"] = int(v) % 360
        elif key in look:
            look[key] = float(raw)
        else:
            raise ValueError(f"unknown look key {key!r}")
    return look


def single(slider, value, as_shot=(5500.0, 0.0)):
    """The look with one Lightroom slider set (Look.single)."""
    look = parse_look("")
    if slider == "Exposure":
        look["ev"] = value
    elif slider == "Temperature":
        look["wb"] = (value, as_shot[1])
    elif slider == "Tint":
        look["wb"] = (as_shot[0], value)
    elif slider in ("Sharpness", "Sharpening"):
        look["shp"] = value
    else:
        look[{"Contrast": "con", "Highlights": "hl", "Shadows": "sh", "Whites": "wh", "Blacks": "bl",
              "Vibrance": "vib", "Saturation": "sat", "Clarity": "clr"}[slider]] = value
    return look


def format_look(look):
    """Canonical text (Look.format)."""
    def signed(v, d):
        r = round(v, d)
        if r == 0:
            return "0" if d == 0 else f"{0:.{d}f}"
        return ("+" if r > 0 else "") + f"{r:.{d}f}"
    out = [f"ev:{signed(look['ev'], 2)}"]
    if look.get("wb") is not None:
        out.append(f"wb:{int(round(look['wb'][0]))}/{signed(look['wb'][1], 0)}")
    for key in ("con", "hl", "sh", "wh", "bl", "vib", "sat", "clr"):
        out.append(f"{key}:{signed(look[key], 0)}")
    out.append(f"shp:{int(round(look['shp']))}")
    out.append(f"vig:{signed(look['vig'], 0)}")
    if look.get("nr") is not None:
        out.append(f"nr:{int(round(look['nr']))}")
    if look.get("bw"):
        out.append("bw:1")
    if look.get("crop"):
        x, y, w, h, r = look["crop"]
        out.append(f"crop:{x:.4f},{y:.4f},{w:.4f},{h:.4f}" + (f"/{r:.2f}" if r else ""))
    if look.get("rot"):
        out.append(f"rot:{int(look['rot'])}")
    return " ".join(out)


# ---- stages -----------------------------------------------------------------------------------

def exposure_gain(ev, rules):
    return 2.0 ** (ev * k(rules, "exposure", "stopsPerUnit", 1.0))


def exposure(x, ev, rules):
    """LookMath.exposure per channel: a scene gain seen through a sigmoid tone curve,
    y' = w·G·t / (1 + (G − 1)·t) with t = x / w; the tangent continues it below 0 and above w."""
    return through_curve(x, exposure_gain(ev, rules), max(0.05, k(rules, "exposure", "white", 1.0)))


def through_curve(x, g, w):
    """A gain `g` (a number, or an array that broadcasts against x) through the tone curve."""
    x = np.asarray(x, dtype=np.float64)
    g = np.asarray(g, dtype=np.float64)
    t = np.clip(x / w, 0.0, 1.0)
    mid = w * g * t / (1 + (g - 1) * t)
    return np.where(x <= 0, x * g, np.where(x >= w, w + (x - w) / g, mid))


def white_balance_gains(target, as_shot, rules):
    """Per-channel gains (3,) taking as_shot=(kelvin, tint) to target. Identity for None."""
    if target is None:
        return np.ones(3)
    dm = 1e6 / max(1000.0, as_shot[0]) - 1e6 / max(1000.0, target[0])
    dt = target[1] - as_shot[1]
    g = np.array([2.0 ** (dm * k(rules, "whiteBalance", "redPerMired", 0.0025) + dt * k(rules, "whiteBalance", "redPerTint", 0.0)),
                  2.0 ** (-dt * k(rules, "whiteBalance", "greenPerTint", 0.004)),
                  2.0 ** (-dm * k(rules, "whiteBalance", "bluePerMired", 0.0025) + dt * k(rules, "whiteBalance", "bluePerTint", 0.0))])
    if k(rules, "whiteBalance", "preserveLuma", 1) >= 0.5:
        g = g / float(np.dot(g, luma_weights(rules)))
    return g


def whites_blacks(p, whites, blacks, rules):
    """Perceptual, per channel."""
    b_amt = -blacks * k(rules, "whitesBlacks", "blacksPerUnit", 0.002)
    w_amt = whites * k(rules, "whitesBlacks", "whitesPerUnit", 0.003)
    pc = np.clip(p, 0.0, 1.0)
    q = p - b_amt * np.power(1.0 - pc, k(rules, "whitesBlacks", "blacksPower", 2.0))
    q = q + w_amt * np.power(pc, k(rules, "whitesBlacks", "whitesPower", 2.0))
    return np.maximum(0.0, q)


TONE_REFERENCE = 0.18
BRIGHT_Y = 0.5668          # relative luminance of L* 80
TONE_HIGH_PERCENTILE = 95.0
REFERENCE_ANCHOR = {"mean": TONE_REFERENCE, "spread": None, "bright": None, "high": None}


def tone_anchor(img, rules):
    """LookMath.toneAnchor: what the tone stage reads a photo against. mean = 2^(mean(log2(max(luma,
    1e-4)))) in [0.001, 4], spread = the standard deviation of log2 luma, bright = the share of
    pixels above L* 80, high = the 95th percentile of luma (linear interpolation) in [0.001, 4]."""
    y = luma(np.asarray(img, dtype=np.float64), rules)
    l = np.log2(np.maximum(1e-4, y))
    high = float(np.percentile(np.where(np.isfinite(y), y, 0.0), TONE_HIGH_PERCENTILE))
    return {"mean": float(min(4.0, max(1e-3, 2.0 ** l.mean()))), "spread": float(l.std()), "bright": float((y > BRIGHT_Y).mean()),
            "high": min(4.0, max(1e-3, high))}


def tone_normalisers(anchor, rules):
    """(shadows mask scale, highlights mask scale, shadows strength, highlights strength)."""
    t = lambda n, d: k(rules, "tone", n, d)
    mean = min(4.0, max(1e-3, anchor["mean"])); ratio = TONE_REFERENCE / mean
    spread_c = t("spreadCentre", 1.5); d_spread = (anchor["spread"] if anchor.get("spread") is not None else spread_c) - spread_c
    bright_c = t("brightCentre", 0.2); d_bright = (anchor["bright"] if anchor.get("bright") is not None else bright_c) - bright_c
    d_mean = np.log2(mean) - t("meanCentre", float(np.log2(TONE_REFERENCE)))
    clamp = lambda x: float(min(4.0, max(0.25, x)))
    d_high = t("highCentre", 0.0) - float(np.log2(min(4.0, max(1e-3, anchor["high"])))) if anchor.get("high") is not None else 0.0
    return (ratio ** t("shadowsAdapt", 0.0) * 2.0 ** (t("shadowsHighAdapt", 0.0) * d_high), ratio ** t("highlightsAdapt", 0.0) * 2.0 ** (t("highlightsHighAdapt", 0.0) * d_high),
            clamp(np.exp(t("shadowsBright", 0.0) * d_bright + t("shadowsSpread", 0.0) * d_spread)),
            clamp(np.exp(t("highlightsMean", 0.0) * d_mean + t("highlightsSpread", 0.0) * d_spread)))


def tone_gain(base, anchor, highlights, shadows, rules):
    """LookMath.toneGain: a local scene gain from the base's luma, read relative to the photo.
    Shadows decay as exp(−p / shadowsTau); Highlights grow linearly up to highlightsKnee."""
    ns, nh, gs, gh = tone_normalisers(anchor, rules)
    base = np.asarray(base, dtype=np.float64)
    ps, ph = perceptual(base * ns, rules), perceptual(base * nh, rules)
    s = shadows * k(rules, "tone", "shadowsStopsPerUnit", 0.01) * gs * np.exp(-ps / max(0.01, k(rules, "tone", "shadowsTau", 0.2)))
    h = highlights * k(rules, "tone", "highlightsStopsPerUnit", 0.01) * gh * np.minimum(1.0, ph / max(0.01, k(rules, "tone", "highlightsKnee", 0.7)))
    return 2.0 ** (s + h)


def tone_white(rules):
    return max(0.05, k(rules, "tone", "white", 1.0))


def tone_detail(y, base, rules):
    d = k(rules, "tone", "detailGain", 1.0)
    if abs(d - 1.0) <= 1e-9:
        return np.ones_like(np.asarray(y, dtype=np.float64))
    return np.power(np.maximum(1e-6, y) / np.maximum(1e-6, base), d - 1.0)


def contrast_curve(p, contrast, rules):
    m = min(0.95, max(0.05, k(rules, "contrast", "midpoint", 0.46)))
    a = 2.0 ** (contrast * k(rules, "contrast", "slopePerUnit", 0.006))
    p = np.asarray(p, dtype=np.float64)
    below = m * np.power(np.clip(p, 0, None) / m, a)
    above = 1.0 - (1.0 - m) * np.power(np.clip(1.0 - p, 0, None) / (1.0 - m), a)
    out = np.where(p < m, below, above)
    out = np.where(p <= 0.0, 0.0, out)
    out = np.where(p >= 1.0, p, out)
    return out


def contrast(rgb, amount, rules):
    if amount == 0:
        return rgb
    mix = min(1.0, max(0.0, k(rules, "contrast", "lumaMix", 0.5)))
    per = linear(contrast_curve(perceptual(rgb, rules), amount, rules), rules)
    y = luma(rgb, rules)
    ratio = np.where(y > 1e-9, linear(contrast_curve(perceptual(y, rules), amount, rules), rules) / np.maximum(y, 1e-9), 1.0)
    by_luma = rgb * ratio[..., None]
    return per + (by_luma - per) * mix


def cbrt_signed(x):
    return np.sign(x) * np.power(np.abs(x), 1.0 / 3.0)


M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050, 0.4505937099],
               [0.0259040371, 0.7827717662, -0.8086757660]])
M2I = np.array([[1.0, 0.3963377774, 0.2158037573],
                [1.0, -0.1055613458, -0.0638541728],
                [1.0, -0.0894841775, -1.2914855480]])
M1I = np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                [-1.2684380046, 2.6097574011, -0.3413193965],
                [-0.0041960863, -0.7034186147, 1.7076147010]])


def to_oklab(rgb):
    lms = cbrt_signed(rgb @ M1.T)
    return lms @ M2.T


def from_oklab(lab):
    lms = lab @ M2I.T
    return (lms ** 3) @ M1I.T


def chroma_factor(C, hue_deg, vibrance, saturation, bw, rules):
    if bw:
        return np.zeros_like(C)
    sat = max(0.0, 1.0 + saturation * k(rules, "colour", "saturationPerUnit", 0.01))
    cmax = max(1e-6, k(rules, "colour", "vibranceChromaMax", 0.25))
    dh = np.mod(np.abs(hue_deg - k(rules, "colour", "skinHue", 60.0)), 360.0)
    dh = np.where(dh > 180.0, 360.0 - dh, dh)
    skin = np.exp(-np.power(dh / max(1e-6, k(rules, "colour", "skinWidth", 25.0)), 2))
    protect = 1.0 - k(rules, "colour", "skinProtect", 0.7) * skin if vibrance > 0 else np.ones_like(skin)
    up = k(rules, "colour", "vibrancePerUnit", 0.01)
    per_unit = up if vibrance > 0 else k(rules, "colour", "vibranceDownPerUnit", up)
    taper = 1.0 - min(1.0, max(0.0, k(rules, "colour", "vibranceFloor", 0.0)))
    vib = np.maximum(0.0, 1.0 + vibrance * per_unit * (1.0 - taper * np.minimum(1.0, C / cmax)) * protect)
    return sat * vib


def colour(rgb, vibrance, saturation, bw, rules):
    if vibrance == 0 and saturation == 0 and not bw:
        return rgb
    lab = to_oklab(rgb)
    C = np.hypot(lab[..., 1], lab[..., 2])
    h = np.degrees(np.arctan2(lab[..., 2], lab[..., 1]))
    h = np.where(h < 0, h + 360.0, h)
    f = chroma_factor(C, h, vibrance, saturation, bw, rules)
    f = np.where(C > 1e-9, f, 1.0)
    out = from_oklab(np.stack([lab[..., 0], lab[..., 1] * f, lab[..., 2] * f], axis=-1))
    return np.maximum(0.0, out)


def clarity(q, base, amount, rules):
    mid = 1.0 - np.power(np.abs(2.0 * np.clip(q, 0.0, 1.0) - 1.0), k(rules, "clarity", "midtonePower", 2.0))
    return np.maximum(0.0, q + amount * k(rules, "clarity", "amountPerUnit", 0.01) * (q - base) * mid)


def sharpen(q, blur, amount, rules):
    hp = q - blur
    t = max(1e-6, k(rules, "sharpen", "threshold", 0.01))
    mask = smoothstep(t, 2.0 * t, np.abs(hp))
    return np.maximum(0.0, q + amount * k(rules, "sharpen", "amountPerUnit", 0.01) * hp * mask)


def vignette_gain(r, vignette, rules):
    m, f = k(rules, "vignette", "midpoint", 0.5), k(rules, "vignette", "feather", 0.5)
    return 2.0 ** (vignette * k(rules, "vignette", "stopsPerUnit", 0.02) * smoothstep(m - f / 2, m + f / 2, r))


# ---- outputTransform (the display mapper) -------------------------------------------------------

GREY = TONE_REFERENCE
WHITE_EV = float(np.log2(1.0 / GREY))      # display white, in stops above mid grey


def mapper(rules):
    """"clamp" (what ships) or "sigmoid" (LookRules.mapper)."""
    return rules["stages"].get("outputTransform", {}).get("mapper") or "clamp"


def display_mapper(rules):
    """LookMath.DisplayMapper's numbers: (kneeEV, maxEV, inset, rotate, hueKeep), kept in range."""
    o = lambda n, d: k(rules, "outputTransform", n, d)
    return (min(WHITE_EV - 0.05, o("kneeEV", 2.0)), max(WHITE_EV + 0.05, o("maxEV", 6.5)), min(0.9, max(0.0, o("inset", 0.2))),
            o("rotate", 0.0), min(1.0, max(0.0, o("hueKeep", 1.0))))


def mapper_matrices(inset, rotate):
    """(inset, outset): every primary `inset` of the way to white, turned `rotate` degrees about the
    grey axis, and the inverse. Rows sum to 1."""
    t = np.radians(rotate); c = np.cos(t); d = (1.0 - c) / 3.0; s = np.sin(t) / np.sqrt(3.0)
    turn = np.array([[c + d, d - s, d + s], [d + s, c + d, d - s], [d - s, d + s, c + d]])
    return (1.0 - inset) * turn + inset / 3.0, turn.T / (1.0 - inset) - inset / (3.0 * (1.0 - inset))


def shoulder(x, knee_ev, max_ev):
    """One channel through the shoulder: the identity up to the knee, then in log2 around mid grey
    L' = knee + H·(1 − (1 − u)^q), q = (max − knee) / H, reaching 1 at max_ev with slope 0."""
    x = np.asarray(x, dtype=np.float64)
    knee, h = GREY * 2.0 ** knee_ev, WHITE_EV - knee_ev
    u = (np.log2(np.clip(x, knee, GREY * 2.0 ** max_ev) / GREY) - knee_ev) / (max_ev - knee_ev)
    return np.where(x > knee, GREY * 2.0 ** (knee_ev + h * (1.0 - np.power(np.maximum(0.0, 1.0 - u), (max_ev - knee_ev) / h))), x)


def output_transform(rgb, rules):
    """LookMath.output: the rules' mapper on colours (..., 3), inside 0…1 (linear, working space)."""
    c = np.asarray(rgb, dtype=np.float64)
    if mapper(rules) != "sigmoid":
        return np.clip(c, 0.0, 1.0)
    knee_ev, max_ev, inset, rotate, hue_keep = display_mapper(rules)
    m, o = mapper_matrices(inset, rotate)
    x = np.minimum(c @ m.T, GREY * 2.0 ** max_ev)
    p = shoulder(x, knee_ev, max_ev)
    xmax, xmin = x.max(axis=-1, keepdims=True), x.min(axis=-1, keepdims=True)
    pmax, pmin = p.max(axis=-1, keepdims=True), p.min(axis=-1, keepdims=True)
    span = xmax - xmin
    kept = pmin + (x - xmin) * ((pmax - pmin) / np.where(span > 1e-6, span, 1.0))
    p = np.where(span > 1e-6, p + (kept - p) * hue_keep, p)
    return np.clip(p @ o.T, 0.0, 1.0)


def apply_luma_ratio(rgb, y_new, y_old):
    ratio = np.where(y_old > 1e-9, y_new / np.maximum(y_old, 1e-9), 1.0)
    return rgb * ratio[..., None]


# ---- the chain ----------------------------------------------------------------------------------

def flat(rgb, look, as_shot, rules, vignette_r=0.0, anchor=None):
    """Every stage on colours (..., 3) where blur(x) == x (LookMath.flat)."""
    c = np.array(rgb, dtype=np.float64)
    anchor = dict(anchor or REFERENCE_ANCHOR)
    order = [s for s in rules.get("order", ["rawDevelop"] + STAGES + ["outputTransform"]) if s in STAGES]
    for stage in order:
        if stage == "exposure":
            if look["ev"] != 0:
                c = exposure(c, look["ev"], rules)
                anchor["mean"] = float(exposure(anchor["mean"], look["ev"], rules))
                if anchor.get("high") is not None:
                    anchor["high"] = float(exposure(anchor["high"], look["ev"], rules))
        elif stage == "whiteBalance":
            if look["wb"] is not None:
                # scene gains through the tone curve, per channel (LookMath.flat)
                c = through_curve(c, white_balance_gains(look["wb"], as_shot, rules), max(0.05, k(rules, "whiteBalance", "white", 1.0)))
        elif stage == "whitesBlacks":
            if look["wh"] != 0 or look["bl"] != 0:
                c = linear(whites_blacks(perceptual(c, rules), look["wh"], look["bl"], rules), rules)
        elif stage == "tone":
            if look["hl"] != 0 or look["sh"] != 0:
                y = luma(c, rules)
                g = tone_gain(y, anchor, look["hl"], look["sh"], rules)
                c = through_curve(c * tone_detail(y, y, rules)[..., None], g[..., None], tone_white(rules))
        elif stage == "contrast":
            c = contrast(c, look["con"], rules)
        elif stage == "colour":
            c = colour(c, look["vib"], look["sat"], look["bw"], rules)
        elif stage == "vignette":
            if look["vig"] != 0:
                c = c * vignette_gain(vignette_r, look["vig"], rules)
    return c


def apply_image(img, look, as_shot, rules, sigma_scale=None):
    """The chain on a whole image (H, W, 3) in the working space, blurs included (scipy). The
    blur radii are fractions of the long edge, as in the graph; sharpen's is radiusPx at refPx."""
    from scipy.ndimage import gaussian_filter
    c = np.array(img, dtype=np.float64)
    long_edge = max(c.shape[0], c.shape[1])
    anchor = tone_anchor(c, rules)            # of the developed frame, before any stage
    order = [s for s in rules.get("order", ["rawDevelop"] + STAGES + ["outputTransform"]) if s in STAGES]
    for stage in order:
        if stage in ("exposure", "whiteBalance", "whitesBlacks", "contrast", "colour"):
            one = {**look, "hl": 0, "sh": 0, "vig": 0, "clr": 0, "shp": 0}
            sub = {"stages": rules["stages"], "order": ["rawDevelop", stage, "outputTransform"],
                   "perceptualGamma": gamma(rules), "luma": list(luma_weights(rules))}
            c = flat(c, one, as_shot, sub)
            if stage == "exposure" and look["ev"] != 0:
                anchor["mean"] = float(exposure(anchor["mean"], look["ev"], rules))
                anchor["high"] = float(exposure(anchor["high"], look["ev"], rules))
        elif stage == "tone" and (look["hl"] != 0 or look["sh"] != 0):
            y = luma(c, rules)
            base = gaussian_filter(y, k(rules, "tone", "radiusFraction", 0.03) * long_edge, mode="nearest")
            g = tone_gain(base, anchor, look["hl"], look["sh"], rules)
            c = through_curve(c * tone_detail(y, base, rules)[..., None], g[..., None], tone_white(rules))
        elif stage == "clarity" and look["clr"] != 0:
            y = luma(c, rules)
            q = perceptual(y, rules)
            base = gaussian_filter(q, k(rules, "clarity", "radiusFraction", 0.02) * long_edge, mode="nearest")
            c = apply_luma_ratio(c, linear(clarity(q, base, look["clr"], rules), rules), y)
        elif stage == "sharpen" and look["shp"] != 0:
            y = luma(c, rules)
            q = perceptual(y, rules)
            sigma = k(rules, "sharpen", "radiusPx", 1.0) * long_edge / max(1.0, k(rules, "sharpen", "refPx", 2048))
            base = gaussian_filter(q, sigma, mode="nearest") if sigma > 0.05 else q
            c = apply_luma_ratio(c, linear(sharpen(q, base, look["shp"], rules), rules), y)
        elif stage == "vignette" and look["vig"] != 0:
            h, w = c.shape[:2]
            yy, xx = np.mgrid[0:h, 0:w]
            r = np.hypot(xx + 0.5 - w / 2, (h - 1 - yy) + 0.5 - h / 2) / (np.hypot(w, h) / 2)
            c = c * vignette_gain(r, look["vig"], rules)[..., None]
    return c


# ---- the check against lumina-render ramp -----------------------------------------------------

def check(path, tolerance=0.02):
    """Compare a `lumina-render ramp` dump with this mirror. Returns (worst_abs_error, rows)."""
    with open(path) as f:
        dump = json.load(f)
    rules = {"stages": {s: {"coefficients": c} for s, c in dump["rules"].items()}, "perceptualGamma": dump["perceptualGamma"],
             "order": dump["order"]}
    rules["stages"].setdefault("outputTransform", {"coefficients": {}})["mapper"] = dump.get("mapper", "clamp")
    look = parse_look(dump["look"])
    as_shot = (dump["asShot"]["kelvin"], dump["asShot"]["tint"])
    worst, rows = 0.0, []
    for row in dump["patches"]:
        mine = flat(np.array(row["in"]), look, as_shot, rules)
        graph = np.array(row["graph"])
        swift = np.array(row["math"])
        e_graph = float(np.max(np.abs(mine - graph)))
        e_swift = float(np.max(np.abs(mine - swift)))
        worst = max(worst, e_graph, e_swift)
        rows.append((row["in"], list(mine), list(graph), list(swift), e_graph, e_swift))
    # outputTransform alone (the dump's mapper), on colours up to far above white
    for row in dump.get("display", []):
        mine = output_transform(np.array(row["in"]), rules)
        e_graph = float(np.max(np.abs(mine - np.array(row["graph"]))))
        e_swift = float(np.max(np.abs(mine - np.array(row["math"]))))
        worst = max(worst, e_graph, e_swift)
        rows.append((row["in"], list(mine), row["graph"], row["math"], e_graph, e_swift))
    return worst, rows


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--check":
        worst, rows = check(sys.argv[2])
        for inp, mine, graph, swift, eg, es in rows:
            flag = "" if max(eg, es) <= 0.02 else "   <-- differs"
            print(f"in {np.round(inp, 3)}  numpy {np.round(mine, 4)}  graph {np.round(graph, 4)}  swift {np.round(swift, 4)}  err {eg:.4f}/{es:.4f}{flag}")
        print(f"worst |numpy - graph|, |numpy - swift| = {worst:.4f}  ({'ok' if worst <= 0.02 else 'FAIL'})")
        sys.exit(0 if worst <= 0.02 else 1)
    print(__doc__)
