#!/usr/bin/env python3
"""ΔE2000 between Lightroom's reference TIFFs and Lumina's renders (roadmap Prompt 2 §3).

    python3 Tools/parity/delta_e.py <reference.tif> <render.tif> [--heatmap out.png] [--json]
    python3 Tools/parity/delta_e.py --selftest

Both images are read as 16-bit (or 8-bit) RGB, converted to CIELAB in the space the reference was
exported in (ProPhoto RGB → D50, sRGB → D65; taken from the TIFF's ICC profile name, or --space),
median-filtered 3 × 3 per channel to suppress demosaic noise, and compared per pixel. Reported:
median, p95, mean, and the same by region: shadows (reference L* < 25), midtones (25–75),
highlights (> 75), and skin (a hue/chroma gate on the reference: hue 15°–55°, chroma 8–45,
L* 30–85). A heatmap PNG (0 = black, ΔE ≥ 10 = white, through a warm ramp) is written on request.

Photo content stays out of the repo: heatmaps go to ~/LuminaEvidence, only numbers to
Tools/parity/report (see parity.py).
"""
import argparse
import json
import sys

import numpy as np

# ---- colour ----------------------------------------------------------------------------------

D50 = np.array([0.9642, 1.0, 0.8249])
D65 = np.array([0.95047, 1.0, 1.08883])
# ROMM RGB (ProPhoto) → XYZ D50; sRGB → XYZ D65
ROMM_TO_XYZ = np.array([[0.7976749, 0.1351917, 0.0313534],
                        [0.2880402, 0.7118741, 0.0000857],
                        [0.0000000, 0.0000000, 0.8252100]])
SRGB_TO_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                        [0.2126729, 0.7151522, 0.0721750],
                        [0.0193339, 0.1191920, 0.9503041]])
# Bradford D50 → D65, for bringing ProPhoto pixels into the sRGB-primaried working space (fit.py)
BRADFORD_D50_TO_D65 = np.array([[0.9555766, -0.0230393, 0.0631636],
                                [-0.0282895, 1.0099416, 0.0210077],
                                [0.0122982, -0.0204830, 1.3299098]])
XYZ_TO_SRGB = np.linalg.inv(SRGB_TO_XYZ)


def decode_prophoto(e):
    """ROMM transfer: linear below 16 × 2^-9, gamma 1.8 above."""
    e = np.asarray(e, dtype=np.float64)
    return np.where(e < 16 * (1 / 512), e / 16.0, np.power(np.maximum(e, 0), 1.8))


def encode_prophoto(x):
    x = np.clip(np.asarray(x, dtype=np.float64), 0, 1)
    return np.where(x < 1 / 512, x * 16.0, np.power(x, 1 / 1.8))


def decode_srgb(e):
    e = np.asarray(e, dtype=np.float64)
    return np.where(e <= 0.04045, e / 12.92, np.power((np.maximum(e, 0) + 0.055) / 1.055, 2.4))


def encode_srgb(x):
    x = np.clip(np.asarray(x, dtype=np.float64), 0, 1)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def to_linear(rgb01, space):
    return decode_prophoto(rgb01) if space == "prophoto" else decode_srgb(rgb01)


def to_xyz(rgb01, space):
    lin = to_linear(rgb01, space)
    return lin @ (ROMM_TO_XYZ.T if space == "prophoto" else SRGB_TO_XYZ.T)


def xyz_to_lab(xyz, white):
    t = xyz / white
    d = 6 / 29
    f = np.where(t > d ** 3, np.cbrt(np.maximum(t, 0)), t / (3 * d * d) + 4 / 29)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], axis=-1)


def to_lab(rgb01, space):
    return xyz_to_lab(to_xyz(rgb01, space), D50 if space == "prophoto" else D65)


def to_working_linear(rgb01, space):
    """Encoded pixels in `space` → linear values with sRGB primaries, D65 (the graph's working
    space, negatives kept). fit.py's input on both sides."""
    xyz = to_xyz(rgb01, space)
    if space == "prophoto":
        xyz = xyz @ BRADFORD_D50_TO_D65.T
    return xyz @ XYZ_TO_SRGB.T


def delta_e2000(lab1, lab2):
    """CIEDE2000 per pixel (Sharma et al. 2005), vectorised."""
    L1, a1, b1 = lab1[..., 0], lab1[..., 1], lab1[..., 2]
    L2, a2, b2 = lab2[..., 0], lab2[..., 1], lab2[..., 2]
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cb ** 7 / (Cb ** 7 + 25.0 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dL = L2 - L1
    dC = C2p - C1p
    dh = h2p - h1p
    dh = np.where(dh > 180, dh - 360, dh)
    dh = np.where(dh < -180, dh + 360, dh)
    dh = np.where(C1p * C2p == 0, 0, dh)
    dH = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh / 2))
    Lb = (L1 + L2) / 2
    Cbp = (C1p + C2p) / 2
    hsum = h1p + h2p
    hb = np.where(np.abs(h1p - h2p) > 180, np.where(hsum < 360, hsum + 360, hsum - 360) / 2, hsum / 2)
    hb = np.where(C1p * C2p == 0, hsum, hb)
    T = (1 - 0.17 * np.cos(np.radians(hb - 30)) + 0.24 * np.cos(np.radians(2 * hb))
         + 0.32 * np.cos(np.radians(3 * hb + 6)) - 0.20 * np.cos(np.radians(4 * hb - 63)))
    SL = 1 + 0.015 * (Lb - 50) ** 2 / np.sqrt(20 + (Lb - 50) ** 2)
    SC = 1 + 0.045 * Cbp
    SH = 1 + 0.015 * Cbp * T
    RT = -2 * np.sqrt(Cbp ** 7 / (Cbp ** 7 + 25.0 ** 7)) * np.sin(np.radians(60 * np.exp(-((hb - 275) / 25) ** 2)))
    return np.sqrt((dL / SL) ** 2 + (dC / SC) ** 2 + (dH / SH) ** 2 + RT * (dC / SC) * (dH / SH))


# ---- images -----------------------------------------------------------------------------------

def read_rgb01(path):
    """(H, W, 3) floats 0…1 and the colour space guessed from the ICC profile ('prophoto',
    'srgb' or None). Alpha dropped. 16-bit preferred; 8-bit accepted."""
    import tifffile
    from PIL import Image
    space = None
    if str(path).lower().endswith((".tif", ".tiff")):
        with tifffile.TiffFile(path) as tf:
            page = tf.pages[0]
            arr = page.asarray()
            icc = page.tags.get("InterColorProfile")
            if icc is not None:
                space = space_from_icc(bytes(icc.value))
    else:
        im = Image.open(path)
        icc = im.info.get("icc_profile")
        if icc:
            space = space_from_icc(icc)
        arr = np.asarray(im.convert("RGB") if im.mode not in ("RGB", "RGBA", "I;16") else im)
    if arr.ndim == 2:
        arr = np.stack([arr] * 3, axis=-1)
    arr = arr[..., :3]
    if arr.dtype == np.uint16:
        rgb = arr.astype(np.float64) / 65535.0
    elif arr.dtype == np.uint8:
        rgb = arr.astype(np.float64) / 255.0
    else:
        rgb = np.clip(arr.astype(np.float64), 0, 1)
    return rgb, space


def space_from_icc(icc):
    """'prophoto' / 'srgb' from an ICC profile's description tag, else None."""
    try:
        text = icc.decode("latin-1", errors="ignore").lower()
    except Exception:
        return None
    if "romm" in text or "prophoto" in text:
        return "prophoto"
    if "srgb" in text:
        return "srgb"
    if "display p3" in text:
        return "p3"
    return None


def align(ref, ren):
    """The render at the reference's size (bilinear) when they differ by a pixel or two."""
    if ref.shape == ren.shape:
        return ren
    h, w = ref.shape[:2]
    rh, rw = ren.shape[:2]
    if abs(h - rh) > max(4, 0.02 * h) or abs(w - rw) > max(4, 0.02 * w):
        raise ValueError(f"size mismatch: reference {w}×{h}, render {rw}×{rh}")
    from PIL import Image
    out = np.zeros((h, w, 3))
    for c in range(3):
        im = Image.fromarray((np.clip(ren[..., c], 0, 1) * 65535).astype(np.uint16))
        out[..., c] = np.asarray(im.resize((w, h), Image.BILINEAR)).astype(np.float64) / 65535.0
    return out


# Paeth's 19-exchange sorting network for the median of nine (element 4 ends up the median).
_MED9 = [(1, 2), (4, 5), (7, 8), (0, 1), (3, 4), (6, 7), (1, 2), (4, 5), (7, 8), (0, 3), (5, 8), (4, 7),
         (3, 6), (1, 4), (2, 5), (4, 7), (4, 2), (6, 4), (4, 2)]


def median3(rgb):
    """3 × 3 median per channel, edges replicated: the same values as scipy's
    median_filter(size=3, mode="nearest"), computed with a min/max sorting network over the nine
    shifted planes (about 10× faster; tests/test_personal.py checks they agree)."""
    h, w = rgb.shape[:2]
    pad = np.pad(rgb, ((1, 1), (1, 1), (0, 0)), mode="edge")
    p = [pad[dy:dy + h, dx:dx + w] for dy in range(3) for dx in range(3)]
    for a, b in _MED9:
        lo = np.minimum(p[a], p[b])
        p[b] = np.maximum(p[a], p[b])
        p[a] = lo
    return p[4]


# ---- the measurement ---------------------------------------------------------------------------

def regions(lab_ref):
    L, a, b = lab_ref[..., 0], lab_ref[..., 1], lab_ref[..., 2]
    C = np.hypot(a, b)
    h = np.degrees(np.arctan2(b, a)) % 360
    return {
        "shadows": L < 25,
        "midtones": (L >= 25) & (L <= 75),
        "highlights": L > 75,
        "skin": (h >= 15) & (h <= 55) & (C >= 8) & (C <= 45) & (L >= 30) & (L <= 85),
    }


def stats(de, mask=None):
    v = de if mask is None else de[mask]
    if v.size == 0:
        return {"n": 0}
    return {"n": int(v.size), "median": float(np.median(v)), "p95": float(np.percentile(v, 95)), "mean": float(np.mean(v)),
            "max": float(np.max(v))}


def measure(ref_rgb, ren_rgb, space, sample=20000, seed=0):
    """ΔE2000 of a pair already read: dict with overall and per-region stats, a deterministic
    subsample of ΔE values (for pooled slider statistics), and the ΔE map."""
    ren_rgb = align(ref_rgb, ren_rgb)
    lab_ref = to_lab(median3(ref_rgb), space)
    lab_ren = to_lab(median3(ren_rgb), space)
    de = delta_e2000(lab_ref, lab_ren)
    out = {"space": space, "width": int(ref_rgb.shape[1]), "height": int(ref_rgb.shape[0]), "all": stats(de)}
    for name, mask in regions(lab_ref).items():
        out[name] = stats(de, mask)
    # Where the error sits in the tone scale: mean ΔE per L* decile of the reference.
    L = lab_ref[..., 0]
    out["byL"] = [float(np.mean(de[(L >= lo) & (L < lo + 10)])) if np.any((L >= lo) & (L < lo + 10)) else None for lo in range(0, 100, 10)]
    flat = de.ravel()
    rng = np.random.default_rng(seed)
    idx = rng.choice(flat.size, size=min(sample, flat.size), replace=False)
    out["sample"] = flat[idx]
    out["map"] = de
    return out


def measure_files(ref_path, ren_path, space=None, sample=20000):
    ref, ref_space = read_rgb01(ref_path)
    ren, ren_space = read_rgb01(ren_path)
    space = space or ref_space or ren_space or "prophoto"
    r = measure(ref, ren, space, sample=sample)
    r["reference"] = str(ref_path)
    r["render"] = str(ren_path)
    if ref_space and ren_space and ref_space != ren_space:
        r["warning"] = f"reference is {ref_space}, render is {ren_space}"
    return r


def heatmap(de, path, top=10.0):
    """ΔE → PNG: black (0) through red and yellow to white (≥ top)."""
    from PIL import Image
    t = np.clip(de / top, 0, 1)
    r = np.clip(t * 3, 0, 1)
    g = np.clip(t * 3 - 1, 0, 1)
    b = np.clip(t * 3 - 2, 0, 1)
    img = (np.stack([r, g, b], axis=-1) * 255).astype(np.uint8)
    Image.fromarray(img).save(path)


def summary_line(r):
    a = r["all"]
    parts = [f"median {a['median']:.2f}", f"p95 {a['p95']:.2f}", f"mean {a['mean']:.2f}"]
    for k in ("shadows", "midtones", "highlights", "skin"):
        if r[k].get("n"):
            parts.append(f"{k} {r[k]['median']:.2f}/{r[k]['p95']:.2f}")
    return " · ".join(parts)


def to_json(r):
    return {k: v for k, v in r.items() if k not in ("sample", "map")}


# ---- self test ------------------------------------------------------------------------------

def selftest():
    """Known CIEDE2000 pairs (Sharma's test data) and a synthetic image pair."""
    cases = [((50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485), 2.0425),
             ((50.0, 3.1571, -77.2803), (50.0, 0.0, -82.7485), 2.8615),
             ((50.0, 2.5, 0.0), (73.0, 25.0, -18.0), 27.1492),
             ((50.0, 2.5, 0.0), (50.0, 3.1736, 0.5854), 1.0),
             ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
             ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082)]
    ok = True
    for p, q, want in cases:
        got = float(delta_e2000(np.array(p), np.array(q)))
        good = abs(got - want) < 1e-3
        ok &= good
        print(f"{'ok  ' if good else 'FAIL'} ΔE2000{p} vs {q} = {got:.4f} (want {want})")
    # A grey ramp against itself shifted a stop: ΔE grows with lightness difference, zero when equal.
    ramp = np.tile(np.linspace(0, 1, 64)[None, :, None], (16, 1, 3))
    same = measure(ramp, ramp, "prophoto")
    good = same["all"]["max"] < 1e-9
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} identical images: max ΔE {same['all']['max']:.2e}")
    brighter = measure(ramp, np.clip(ramp * 1.1, 0, 1), "srgb")
    good = brighter["all"]["median"] > 0.5 and brighter["shadows"]["n"] > 0 and brighter["highlights"]["n"] > 0
    ok &= good
    print(f"{'ok  ' if good else 'FAIL'} 10 % brighter: {summary_line(brighter)}")
    # sRGB white is L* 100 in D65; ProPhoto white is L* 100 in D50.
    for sp in ("srgb", "prophoto"):
        L = to_lab(np.array([[1.0, 1.0, 1.0]]), sp)[0, 0]
        good = abs(L - 100) < 0.05
        ok &= good
        print(f"{'ok  ' if good else 'FAIL'} {sp} white L* = {L:.3f}")
    return ok


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", nargs="?")
    ap.add_argument("render", nargs="?")
    ap.add_argument("--space", choices=["prophoto", "srgb", "p3"])
    ap.add_argument("--heatmap")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return 0 if selftest() else 1
    if not (a.reference and a.render):
        ap.print_help()
        return 2
    r = measure_files(a.reference, a.render, a.space)
    if a.heatmap:
        heatmap(r["map"], a.heatmap)
    if a.json:
        print(json.dumps(to_json(r), indent=1))
    else:
        print(summary_line(r))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
