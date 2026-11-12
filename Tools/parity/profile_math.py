#!/usr/bin/env python3
"""numpy copy of the `profile` stage (LookMath.profile): the camera profile that makes the
decoder's linear output Lightroom's Adobe Color, in the form of an Adobe DCP (DNG SDK
dng_hue_sat_map / RefBaselineHueSatMap / RefBaselineRGBTone), with Lumina's own numbers.

Per pixel, linear values in the working space (sRGB primaries, D65):
  1. exposure: × 2^exposure (the profile's baseline exposure)
  2. mix: a 3×3 matrix whose rows sum to 1 (a grey stays grey)
  3. hue/sat map: in linear ProPhoto HSV (hue 0…6 sextants, as the DNG SDK), a table of
     hueDivisions × satDivisions × valDivisions entries (hueShift degrees, satScale, valScale),
     trilinear with the hue wrapping, the value axis indexed by v^(1/gamma); a pixel with no
     saturation reads the sat-0 row, whose valScale is 1, so a grey stays grey
  4. tone curve: `curve`, N nodes of y at x = i/(N−1) in perceptual space, monotone, through
     the DNG SDK's RGBTone: the largest and smallest channel go through the curve, the middle
     one keeps its place between them; above 1 the curve goes on at slope 1
The stage holds its tables in rules-v1.json under stages.profile.tables ("hsm", "curve") and
its scalars under coefficients. The Metal kernel (lookProfile) and the Swift scalar chain are
the other two copies; `lumina-render ramp` + `lookmath.py --check` hold them equal.
"""
import numpy as np

np.seterr(all="ignore")  # Accelerate's matmul raises spurious FP warnings on macOS (as parity_personal.py)

# linear sRGB (D65) → linear ProPhoto (D50), Bradford; the inverse. Same constants in LookMath / LookKernels.
SRGB_TO_PROPHOTO = np.array([[0.5293458759317613, 0.330072797941936, 0.14058131638228086],
                             [0.0983743638449671, 0.8734610679819278, 0.0281646251213536],
                             [0.01688317839798025, 0.1176724654297775, 0.8654443236645497]])
PROPHOTO_TO_SRGB = np.array([[2.0340761471876716, -0.7273342302651498, -0.30674186565349915],
                             [-0.2288133847303624, 1.2317301146832054, -0.0029168024220968514],
                             [-0.008569742917820058, -0.15328658603088974, 1.1618563753638784]])

COEFF_DEFAULTS = {"exposure": 0.0, "rg": 0.0, "rb": 0.0, "gr": 0.0, "gb": 0.0, "br": 0.0, "bg": 0.0,
                  "hueDivisions": 30, "satDivisions": 8, "valDivisions": 1, "curveNodes": 33}


def coefficients(stage):
    c = {**COEFF_DEFAULTS, **(stage.get("coefficients") or {})}
    return c


def hsm_shape(c):
    return int(c["hueDivisions"]), int(c["satDivisions"]), int(c["valDivisions"])


def identity_hsm(c):
    """(val, hue, sat, 3): no shift, scales 1."""
    h, s, v = hsm_shape(c)
    t = np.zeros((v, h, s, 3))
    t[..., 1] = 1.0
    t[..., 2] = 1.0
    return t


def identity_curve(c):
    n = int(c["curveNodes"])
    return np.linspace(0.0, 1.0, n)


def tables(stage):
    """The stage's tables as arrays: hsm (val, hue, sat, 3) and curve (N,). Missing = identity."""
    c = coefficients(stage)
    t = stage.get("tables") or {}
    h, s, v = hsm_shape(c)
    hsm = np.asarray(t["hsm"], dtype=np.float64).reshape(v, h, s, 3) if "hsm" in t else identity_hsm(c)
    curve = np.asarray(t["curve"], dtype=np.float64) if "curve" in t else identity_curve(c)
    return hsm, curve


def mix_rows(c):
    return np.array([[1 - c["rg"] - c["rb"], c["rg"], c["rb"]],
                     [c["gr"], 1 - c["gr"] - c["gb"], c["gb"]],
                     [c["br"], c["bg"], 1 - c["br"] - c["bg"]]])


def rgb_to_hsv6(p):
    """DNG SDK's HSV: h in [0, 6), s = (max − min) / max, v = max. p ≥ 0."""
    r, g, b = p[..., 0], p[..., 1], p[..., 2]
    v = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = v - mn
    s = np.where(v > 0, d / np.maximum(v, 1e-12), 0.0)
    safe = np.where(d > 0, d, 1.0)
    h = np.where(d <= 0, 0.0,
                 np.where(v == r, (g - b) / safe,
                          np.where(v == g, 2.0 + (b - r) / safe, 4.0 + (r - g) / safe)))
    h = np.where(h < 0, h + 6.0, h)
    return h, s, v


def hsv6_to_rgb(h, s, v):
    h = np.mod(h, 6.0)
    i = np.floor(h)
    f = h - i
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    i = i.astype(int)
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], axis=-1)


def sample_hsm(hsm, h, s, v_enc):
    """Trilinear read of the table at (h in 0…6, s in 0…1, v_enc in 0…1): hue wraps, sat and
    value clamp (dng_hue_sat_map / RefBaselineHueSatMap). Returns (hueShift deg, satScale, valScale)."""
    nv, nh, ns, _ = hsm.shape
    hf = np.mod(h, 6.0) * (nh / 6.0)
    h0 = np.floor(hf).astype(int)
    hw = hf - h0
    h0 = np.mod(h0, nh)
    h1 = np.mod(h0 + 1, nh)
    sf = np.clip(s, 0.0, 1.0) * (ns - 1)
    s0 = np.minimum(np.floor(sf).astype(int), ns - 2) if ns > 1 else np.zeros_like(h0)
    sw = sf - s0 if ns > 1 else np.zeros_like(hf)
    s1 = np.minimum(s0 + 1, ns - 1)
    if nv > 1:
        vf = np.clip(v_enc, 0.0, 1.0) * (nv - 1)
        v0 = np.minimum(np.floor(vf).astype(int), nv - 2)
        vw = vf - v0
        v1 = v0 + 1
    else:
        v0 = v1 = np.zeros_like(h0)
        vw = np.zeros_like(hf)

    def at(vi, hi, si):
        return hsm[vi, hi, si]
    hw3, sw3, vw3 = hw[..., None], sw[..., None], vw[..., None]
    c00 = at(v0, h0, s0) * (1 - hw3) + at(v0, h1, s0) * hw3
    c01 = at(v0, h0, s1) * (1 - hw3) + at(v0, h1, s1) * hw3
    c0 = c00 * (1 - sw3) + c01 * sw3
    if nv > 1:
        c10 = at(v1, h0, s0) * (1 - hw3) + at(v1, h1, s0) * hw3
        c11 = at(v1, h0, s1) * (1 - hw3) + at(v1, h1, s1) * hw3
        c1 = c10 * (1 - sw3) + c11 * sw3
        return c0 * (1 - vw3) + c1 * vw3
    return c0


def curve_eval(curve, p):
    """The curve at perceptual p: linear between nodes, slope 1 above 1, identity below 0."""
    n = curve.shape[0]
    x = np.clip(p, 0.0, 1.0) * (n - 1)
    i = np.minimum(np.floor(x).astype(int), n - 2)
    f = x - i
    y = curve[i] * (1 - f) + curve[i + 1] * f
    return y + np.maximum(0.0, p - 1.0) + np.minimum(0.0, p)


def rgb_tone(curve, p):
    """RefBaselineRGBTone on perceptual channels: max and min through the curve, the middle
    channel interpolated between them by its place in the input."""
    mx = p.max(axis=-1)
    mn = p.min(axis=-1)
    tmx = curve_eval(curve, mx)
    tmn = curve_eval(curve, mn)
    span = mx - mn
    w = np.where(span[..., None] > 1e-9, (p - mn[..., None]) / np.maximum(span, 1e-9)[..., None], 0.0)
    out = tmn[..., None] + (tmx - tmn)[..., None] * w
    # all equal: the curve itself
    return np.where(span[..., None] > 1e-9, out, tmx[..., None])


def profile(rgb, stage, rules):
    c = coefficients(stage)
    hsm, curve = tables(stage)
    gamma = float(rules.get("perceptualGamma", 2.2))
    x = np.asarray(rgb, dtype=np.float64) * (2.0 ** float(c["exposure"]))
    x = x @ mix_rows(c).T
    # hue/sat map in linear ProPhoto
    pp = np.maximum(x @ SRGB_TO_PROPHOTO.T, 0.0)
    h, s, v = rgb_to_hsv6(pp)
    v_enc = np.power(np.clip(v, 0.0, 1.0), 1.0 / gamma)
    d = sample_hsm(hsm, h, s, v_enc)
    h2 = h + d[..., 0] * (6.0 / 360.0)
    s2 = np.minimum(s * d[..., 1], 1.0)
    v2 = v * d[..., 2]
    pp2 = hsv6_to_rgb(h2, s2, v2)
    x = pp2 @ PROPHOTO_TO_SRGB.T
    # tone curve (RGBTone) in perceptual space
    sign = np.sign(x)
    p = np.power(np.abs(x), 1.0 / gamma) * sign
    q = rgb_tone(curve, p)
    return np.power(np.abs(q), gamma) * np.sign(q)


def is_identity(stage):
    c = coefficients(stage)
    hsm, curve = tables(stage)
    return (c["exposure"] == 0 and all(c[k] == 0 for k in ("rg", "rb", "gr", "gb", "br", "bg"))
            and np.allclose(hsm, identity_hsm(c)) and np.allclose(curve, identity_curve(c)))


def validate(stage):
    """Monotone curve from 0 to 1, valScale 1 on the sat-0 row, finite tables."""
    c = coefficients(stage)
    hsm, curve = tables(stage)
    assert np.all(np.isfinite(hsm)) and np.all(np.isfinite(curve)), "profile tables must be finite"
    assert np.all(np.diff(curve) >= -1e-9), "profile curve must be monotone"
    assert abs(curve[0]) < 1e-6 and abs(curve[-1] - 1) < 1e-6, "profile curve must run 0 → 1"
    assert np.allclose(hsm[:, :, 0, 2], 1.0), "profile hsm: valScale must be 1 where sat is 0"
    assert np.all(hsm[..., 1] >= 0) and np.all(hsm[..., 2] > 0), "profile hsm: scales must be positive"
