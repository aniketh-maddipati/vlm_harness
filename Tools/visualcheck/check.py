#!/usr/bin/env python3
"""Flag image pairs with a visible difference: numbers first, a local vision model's word beside them.

    ~/LuminaEvidence/venv-parity/bin/python Tools/visualcheck/check.py \
        --pairs <dir | list.txt> --out ~/LuminaEvidence/visualcheck/<run> [--no-model]

A pair is (A, B): before/after, canvas/export, Lumina/Lightroom. For each pair:

- numbers (always): ΔE2000 (Tools/parity/delta_e.py, sRGB, 3 × 3 median) median / p95, the worst
  32 px block, sharpness ratio B/A (Laplacian variance), and a seam score (the strongest single
  row or column step in the difference). A heatmap PNG is written next to the report.
- model (optional): both images sent to a vision model served by LM Studio on loopback
  (http://127.0.0.1:1234), asked for {"visible_difference": bool, "reason": "<one line>"}.
  Non-loopback endpoints are refused: photos never leave the Mac.

A pair is flagged when the numbers cross a threshold (THRESHOLDS) or the model says it sees a
difference. The report (index.html + report.json + report.md) lists flagged pairs first, each with
the reason from the numbers and the model's sentence. Images and reports belong in
~/LuminaEvidence, never in the repo.
"""
import argparse
import base64
import io
import ipaddress
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, asdict
from pathlib import Path

import warnings

import numpy as np
from PIL import Image

# numpy 2 on Accelerate reports "invalid value in matmul" for finite inputs; results are checked
# with nan_to_num where it matters.
warnings.filterwarnings("ignore", message=".*encountered in matmul", category=RuntimeWarning)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
import delta_e as DE  # noqa: E402

ENDPOINT = "http://127.0.0.1:1234/v1/chat/completions"
MODEL = "qwen2.5-vl-3b-instruct"
MEASURE_PX = 1024          # numbers on this long side
MODEL_PX = 768             # each image sent to the model at this long side
TONE_PX = 8                # tone ΔE: both images averaged over 8 px blocks first
BLOCK = 32                 # px at MEASURE_PX for the worst-block tone ΔE
SHARP_BLOCK = 128          # px at MEASURE_PX for the block sharpness ratio
SEAM_EDGE = 8              # rows / columns ignored at each border for the seam score
SEAM_MIN_STEP = 1.0 / 255  # a step below one code value (mean over a run) is not a seam
SEAM_RUN = 64              # px per run along a line
SEAM_EDGE_A = 0.03         # |A step| above this is an edge in A: not counted

# Calibrated 2026-11-12 on 8 photos (README "Calibration"): JPEG q90 re-encodes and 0.75×
# resize round trips cross none; the camera-profile before/after pairs cross one.
THRESHOLDS = {
    "median": 0.6,         # tone ΔE: a global shift (exposure, tint, profile)
    "p95": 1.25,
    "block": 1.75,         # tone ΔE of the worst 32 px block: a local change
    "sharp_lo": 0.45,      # B softer all over (Laplacian variance B / A)
    "sharp_hi": 1.30,      # B crisper or noisier all over
    "sharp_block_lo": 0.30,  # B softer in one 128 px block that has detail
    "seam": 6.0,           # robust z of one row/column step in the difference
}

PAIR_SUFFIXES = [("before", "after"), ("a", "b"), ("canvas", "export"), ("lumina", "lightroom"),
                 ("render", "ref"), ("old", "new")]
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"}


# ---- pairs -------------------------------------------------------------------------------------

@dataclass
class Pair:
    name: str
    a: str
    b: str
    label_a: str = "A"
    label_b: str = "B"


def _images(d):
    return sorted(p for p in Path(d).iterdir()
                  if p.suffix.lower() in IMAGE_EXT and not p.name.startswith("._"))


def load_pairs(spec):
    """A list file ("a b [name]" per line, # comments), a dir with <stem>-before/-after (or any
    PAIR_SUFFIXES), or a dir holding two sub-dirs named like a suffix pair with matching files."""
    spec = Path(spec).expanduser()
    if spec.is_file():
        out = []
        for line in spec.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split("\t") if "\t" in line else line.split()
            a, b = (Path(x).expanduser() for x in parts[:2])
            if not a.is_absolute():
                a, b = spec.parent / a, spec.parent / b
            out.append(Pair(parts[2] if len(parts) > 2 else a.stem, str(a), str(b)))
        return out
    if not spec.is_dir():
        raise SystemExit(f"--pairs: no such file or directory: {spec}")
    for sa, sb in PAIR_SUFFIXES:
        da, db = spec / sa, spec / sb
        if da.is_dir() and db.is_dir():
            bs = {p.stem: p for p in _images(db)}
            return [Pair(p.stem, str(p), str(bs[p.stem]), sa, sb) for p in _images(da) if p.stem in bs]
    files = _images(spec)
    by_stem = {p.stem.lower(): p for p in files}
    out = []
    for p in files:
        for sa, sb in PAIR_SUFFIXES:
            for sep in ("-", "_", "."):
                tail = f"{sep}{sa}"
                if p.stem.lower().endswith(tail):
                    base = p.stem[: -len(tail)]
                    q = by_stem.get(f"{base}{sep}{sb}".lower())
                    if q is not None:
                        out.append(Pair(base, str(p), str(q), sa, sb))
    return out


# ---- images ------------------------------------------------------------------------------------

def read_rgb01(path):
    """(rgb 0..1, space) through delta_e's reader (16-bit TIFFs, ICC → 'prophoto' / 'srgb')."""
    rgb, space = DE.read_rgb01(path)
    return rgb, (space if space in ("prophoto", "srgb") else "srgb")


def display_srgb(rgb, space):
    """What a screen shows: ProPhoto pixels converted to sRGB (clipped); sRGB unchanged."""
    if space != "prophoto":
        return rgb
    lin = DE.decode_prophoto(rgb) @ DE.ROMM_TO_XYZ.T @ DE.BRADFORD_D50_TO_D65.T @ DE.XYZ_TO_SRGB.T
    return DE.encode_srgb(lin)


def resize01(rgb, long_side):
    h, w = rgb.shape[:2]
    s = long_side / max(h, w)
    if s >= 1:
        return rgb
    im = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))
    im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255.0


def match_size(a, b):
    """B is resized to A's size when they differ (noted in the result)."""
    if a.shape == b.shape:
        return a, b, False
    im = Image.fromarray((np.clip(b, 0, 1) * 255 + 0.5).astype(np.uint8))
    im = im.resize((a.shape[1], a.shape[0]), Image.LANCZOS)
    return a, np.asarray(im, dtype=np.float64) / 255.0, True


def luma(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def laplacian_var(y):
    lap = (-4 * y[1:-1, 1:-1] + y[:-2, 1:-1] + y[2:, 1:-1] + y[1:-1, :-2] + y[1:-1, 2:])
    return float(lap.var())


def block_means(m, n):
    h, w = (m.shape[0] // n) * n, (m.shape[1] // n) * n
    if h == 0 or w == 0:
        return np.array([[float(m.mean())]])
    return m[:h, :w].reshape(h // n, n, w // n, n).mean(axis=(1, 3))


def seam_score(diff, ya):
    """A seam is a step in the difference (B − A) along a straight line where A itself has no
    edge: a tile boundary or a band placed wrong. For every row and column boundary, the step in
    the difference is averaged over 64 px runs of the line, skipping pixels where A has an edge
    (an object that changed colour steps at its own edge, which is not a seam), less the larger
    step 3 lines either side on the same run (a seam is sharp, an object's change ramps); the boundary's
    score is the 4th-largest run in one direction (a seam spans ≥ 256 px), and the result is the
    best boundary's robust z against all boundaries. Borders are skipped (filters, JPEG blocks)."""
    best = 0.0
    where = None
    edge = SEAM_EDGE
    for name, d, y in (("row", diff, ya), ("column", diff.T, ya.T)):
        if d.shape[0] < 4 * edge or d.shape[1] < 4 * SEAM_RUN:
            continue
        step = np.diff(d, axis=0)                      # (H-1, W): boundary between line i and i+1
        flat = np.abs(np.diff(y, axis=0)) < SEAM_EDGE_A
        w = (d.shape[1] // SEAM_RUN) * SEAM_RUN
        st = (step * flat)[:, :w].reshape(step.shape[0], -1, SEAM_RUN).sum(axis=2)
        ct = flat[:, :w].reshape(step.shape[0], -1, SEAM_RUN).sum(axis=2)
        runs = np.where(ct >= SEAM_RUN // 2, st / np.maximum(ct, 1), 0.0)
        # sharp: the step must beat the steps 3 lines away on the same run (a seam is one line;
        # a changed object's difference ramps over several)
        pad = np.pad(np.abs(runs), ((3, 3), (0, 0)))
        near = np.maximum(pad[:-6], pad[6:])
        runs = np.sign(runs) * np.maximum(np.abs(runs) - near, 0)
        srt = np.sort(runs, axis=1)
        k = min(4, srt.shape[1])
        score = np.maximum(srt[:, -k], -srt[:, k - 1])     # k runs all stepping the same way
        score = np.maximum(score, 0)[edge:-edge]
        med = np.median(score)
        mad = max(np.median(np.abs(score - med)) * 1.4826, SEAM_MIN_STEP / 4)
        z = (score - med) / mad
        z[score < SEAM_MIN_STEP] = 0
        i = int(z.argmax())
        if z[i] > best:
            best, where = float(z[i]), (name, i + 1 + edge, d.shape[0])
    return best, where


# ---- numbers -----------------------------------------------------------------------------------

def box(rgb, n):
    h, w = (rgb.shape[0] // n) * n, (rgb.shape[1] // n) * n
    return rgb[:h, :w].reshape(h // n, n, w // n, n, -1).mean(axis=(1, 3))


def local_sharp(ya, yb, n=SHARP_BLOCK):
    """Lowest and highest B/A Laplacian energy over n px blocks that hold detail in A (energy at
    or above the median block's): a blurred patch, or a sharpened / noisier one."""
    def energy(y):
        lap = (-4 * y[1:-1, 1:-1] + y[:-2, 1:-1] + y[2:, 1:-1] + y[1:-1, :-2] + y[1:-1, 2:])
        return block_means(lap ** 2, n)
    ea, eb = energy(ya), energy(yb)
    keep = ea >= max(np.median(ea), 1e-9)
    if not keep.any():
        return 1.0, 1.0, None
    ratio = np.where(keep, eb / np.maximum(ea, 1e-12), np.nan)
    i = np.unravel_index(int(np.nanargmin(ratio)), ratio.shape)
    return float(np.nanmin(ratio)), float(np.nanmax(ratio)), [int(i[1] * n), int(i[0] * n), n]


def measure(a, b, space="srgb"):
    """Numbers for one pair at MEASURE_PX. Flags use tone ΔE (both images averaged over TONE_PX
    blocks first, so noise, JPEG and sharpness changes drop out and colour / tone shifts stay),
    block sharpness, global sharpness and the seam score. Pixel ΔE (3 × 3 median, as
    delta_e.py) is reported beside them and drawn as the heatmap."""
    a = resize01(a, MEASURE_PX)
    b = resize01(b, MEASURE_PX)
    if a.shape != b.shape:
        a, b, _ = match_size(a, b)
    la = DE.to_lab(DE.median3(a), space)
    lb = DE.to_lab(DE.median3(b), space)
    de = np.nan_to_num(DE.delta_e2000(la.reshape(-1, 3), lb.reshape(-1, 3)).reshape(a.shape[:2]))
    ta, tb = DE.to_lab(box(a, TONE_PX), space), DE.to_lab(box(b, TONE_PX), space)
    tde = np.nan_to_num(DE.delta_e2000(ta.reshape(-1, 3), tb.reshape(-1, 3)).reshape(ta.shape[:2]))
    k = BLOCK // TONE_PX
    blocks = block_means(tde, k)
    bi = np.unravel_index(int(blocks.argmax()), blocks.shape)
    ya, yb = luma(a), luma(b)
    sa, sb = laplacian_var(ya), laplacian_var(yb)
    lo, hi, lo_at = local_sharp(ya, yb)
    seam, seam_at = seam_score(yb - ya, ya)
    return de, {
        "median": float(np.median(tde)),
        "p95": float(np.percentile(tde, 95)),
        "block": float(blocks.max()),
        "block_at": [int(bi[1] * BLOCK), int(bi[0] * BLOCK), BLOCK],   # x, y, size at MEASURE_PX
        "pixel_median": float(np.median(de)),
        "pixel_p95": float(np.percentile(de, 95)),
        "sharp": float(sb / sa) if sa > 1e-12 else 1.0,
        "sharp_block_lo": lo, "sharp_block_hi": hi, "sharp_block_at": lo_at,
        "seam": seam,
        "seam_at": seam_at,
        "dL": float(np.median(tb[..., 0] - ta[..., 0])),
        "da": float(np.median(tb[..., 1] - ta[..., 1])),
        "db": float(np.median(tb[..., 2] - ta[..., 2])),
        "size": [int(a.shape[1]), int(a.shape[0])],
    }


def numbers_reasons(n, t=THRESHOLDS):
    """Plain-word reasons for each threshold crossed (empty when none)."""
    out = []
    if n["median"] >= t["median"] or n["p95"] >= t["p95"]:
        words = []
        if abs(n["dL"]) >= 0.5:
            words.append("brighter" if n["dL"] > 0 else "darker")
        if abs(n["da"]) >= 0.5:
            words.append("more magenta" if n["da"] > 0 else "greener")
        if abs(n["db"]) >= 0.5:
            words.append("warmer/yellower" if n["db"] > 0 else "cooler/bluer")
        tone = ", ".join(words) if words else "colour/tone shifted"
        out.append(f"B {tone} overall (ΔE median {n['median']:.2f}, p95 {n['p95']:.2f})")
    elif n["block"] >= t["block"]:
        x, y, s = n["block_at"]
        out.append(f"local change near x {x}, y {y} of {n['size'][0]}×{n['size'][1]} "
                   f"(block ΔE {n['block']:.1f})")
    if n["sharp"] <= t["sharp_lo"]:
        out.append(f"B softer all over (sharpness ×{n['sharp']:.2f})")
    elif n["sharp"] >= t["sharp_hi"]:
        out.append(f"B crisper or noisier all over (sharpness ×{n['sharp']:.2f})")
    elif n["sharp_block_lo"] <= t["sharp_block_lo"] and n["sharp_block_at"]:
        x, y, s = n["sharp_block_at"]
        out.append(f"B softer in a patch near x {x}, y {y} of {n['size'][0]}×{n['size'][1]} "
                   f"(block sharpness ×{n['sharp_block_lo']:.2f})")
    if n["seam"] >= t["seam"] and n["seam_at"]:
        kind, i, size = n["seam_at"]
        out.append(f"step along {kind} {i}/{size} (seam z {n['seam']:.0f})")
    return out


def heat_top(de):
    """Heatmap scale: white at the 99.5th percentile, never below ΔE 2 (so noise stays dark)."""
    return float(max(2.0, np.percentile(de, 99.5)))


def write_heatmap(de, path):
    top = heat_top(de)
    DE.heatmap(de, str(path), top=top)
    return top


# ---- model -------------------------------------------------------------------------------------

PROMPT = (
    "You are checking a photo editor for rendering mistakes. Image A and image B are the same "
    "photograph rendered two ways. Compare them carefully: overall brightness, contrast, colour "
    "cast (greener, more magenta, warmer, cooler), skin tones, shadow and highlight detail, "
    "sharpness, and local defects such as a patch, a seam or a hard line, banding, or a blurred "
    "area. Most pairs you see are identical or differ by an amount nobody would notice; say "
    "visible_difference true only if a careful photographer looking at both would see it. "
    "Reply with JSON only: {\"visible_difference\": true|false, \"reason\": \"one short line "
    "describing how B differs from A, or 'no visible difference'\"}."
)

SCHEMA = {
    "type": "json_schema",
    "json_schema": {
        "name": "visual_check",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "visible_difference": {"type": "boolean"},
                "reason": {"type": "string"},
            },
            "required": ["visible_difference", "reason"],
            "additionalProperties": False,
        },
    },
}


def require_loopback(url):
    host = urllib.parse.urlparse(url).hostname or ""
    if host == "localhost":
        return
    try:
        if ipaddress.ip_address(host).is_loopback:
            return
    except ValueError:
        pass
    raise SystemExit(f"refusing model endpoint {url}: only loopback (127.0.0.1, ::1, localhost); "
                     "photos never leave the Mac")


def jpeg_data_url(rgb01, long_side):
    im = Image.fromarray((np.clip(resize01(rgb01, long_side), 0, 1) * 255 + 0.5).astype(np.uint8))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=92)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def build_request(a, b, model=MODEL, px=MODEL_PX):
    return {
        "model": model,
        "temperature": 0,
        "max_tokens": 120,
        "response_format": SCHEMA,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": "Image A:"},
                {"type": "image_url", "image_url": {"url": jpeg_data_url(a, px)}},
                {"type": "text", "text": "Image B:"},
                {"type": "image_url", "image_url": {"url": jpeg_data_url(b, px)}},
                {"type": "text", "text": PROMPT},
            ],
        }],
    }


def post_json(url, body, timeout=180):
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def parse_reply(resp):
    text = resp["choices"][0]["message"]["content"].strip()
    if text.startswith("```"):
        text = text.strip("`").split("\n", 1)[-1]
    start, end = text.find("{"), text.rfind("}")
    obj = json.loads(text[start:end + 1])
    return bool(obj.get("visible_difference")), str(obj.get("reason", "")).strip()


def ask_model(a, b, url=ENDPOINT, model=MODEL, post=post_json):
    require_loopback(url)
    t0 = time.monotonic()
    resp = post(url, build_request(a, b, model))
    seen, reason = parse_reply(resp)
    return {"visible_difference": seen, "reason": reason, "seconds": time.monotonic() - t0}


# ---- run ---------------------------------------------------------------------------------------

@dataclass
class Result:
    name: str
    a: str
    b: str
    label_a: str
    label_b: str
    numbers: dict
    reasons: list
    model: dict = None
    flagged: bool = False
    by: list = field(default_factory=list)   # "numbers", "model"
    resized: bool = False
    heatmap: str = ""
    error: str = ""


def check_pair(pair, out_dir, use_model=True, url=ENDPOINT, model=MODEL, post=post_json):
    a, sa = read_rgb01(pair.a)
    b, sb = read_rgb01(pair.b)
    if sa != sb:   # compare what a screen shows
        a, b, sa = display_srgb(a, sa), display_srgb(b, sb), "srgb"
    a, b, resized = match_size(a, b)
    de, n = measure(a, b, sa)
    n["space"] = sa
    a, b = display_srgb(a, sa), display_srgb(b, sa)
    reasons = numbers_reasons(n)
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in pair.name)
    heat = Path(out_dir) / "heat" / f"{safe}.png"
    heat.parent.mkdir(parents=True, exist_ok=True)
    n["heat_top"] = write_heatmap(de, heat)
    r = Result(pair.name, pair.a, pair.b, pair.label_a, pair.label_b, n, reasons,
               resized=resized, heatmap=str(heat.relative_to(out_dir)))
    if reasons:
        r.by.append("numbers")
    if use_model:
        try:
            r.model = ask_model(a, b, url, model, post)
            if r.model["visible_difference"]:
                r.by.append("model")
        except Exception as e:  # a model failure never hides the numbers
            r.error = f"model: {type(e).__name__}: {e}"
    r.flagged = bool(r.by)
    return r


def order(results):
    return sorted(results, key=lambda r: (not r.flagged, -len(r.by), -r.numbers["p95"]))


def thumb(path, out_dir, name, long_side=640):
    p = Path(out_dir) / "thumbs" / name
    p.parent.mkdir(parents=True, exist_ok=True)
    rgb, space = read_rgb01(path)
    rgb = resize01(display_srgb(rgb, space), long_side)
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(p, "JPEG", quality=88)
    return str(p.relative_to(out_dir))


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def write_report(results, out_dir, meta):
    out_dir = Path(out_dir)
    results = order(results)
    (out_dir / "report.json").write_text(json.dumps(
        {"meta": meta, "thresholds": THRESHOLDS, "results": [asdict(r) for r in results]},
        indent=2, ensure_ascii=False))
    md = [f"# Visual check · {meta['run']}", "",
          f"{sum(r.flagged for r in results)} of {len(results)} pairs flagged · model "
          f"{meta['model'] or 'off'}", "",
          "| pair | flag | ΔE med / p95 | block | sharp | seam | numbers say | model says |",
          "|---|---|---|---|---|---|---|---|"]
    rows = []
    for i, r in enumerate(results):
        n = r.numbers
        ms = (("**diff** " if r.model["visible_difference"] else "same · ") + r.model["reason"]
              if r.model else (r.error or "—"))
        md.append(f"| {r.name} | {'+'.join(r.by) or '—'} | {n['median']:.2f} / {n['p95']:.2f} | "
                  f"{n['block']:.1f} | ×{n['sharp']:.2f} | {n['seam']:.0f} | "
                  f"{'; '.join(r.reasons) or '—'} | {ms.replace('|', '/')} |")
        ta = thumb(r.a, out_dir, f"{i:03d}-a.jpg")
        tb = thumb(r.b, out_dir, f"{i:03d}-b.jpg")
        badge = ("<span class=flag>flagged · " + esc(" + ".join(r.by)) + "</span>"
                 if r.flagged else "<span class=ok>no difference</span>")
        rows.append(f"""<section class="{'f' if r.flagged else 'q'}">
<h2>{esc(r.name)} {badge}</h2>
<p class=num>ΔE median {n['median']:.2f} · p95 {n['p95']:.2f} · worst block {n['block']:.1f} ·
sharpness ×{n['sharp']:.2f} · seam z {n['seam']:.0f} · ΔL* {n['dL']:+.1f} Δa* {n['da']:+.1f} Δb* {n['db']:+.1f}
{'· B resized to A' if r.resized else ''}</p>
<p><b>Numbers:</b> {esc('; '.join(r.reasons) or 'under every threshold')}</p>
<p><b>Model:</b> {esc(ms)}</p>
<div class=row><figure><img src="{ta}"><figcaption>{esc(r.label_a)} · {esc(Path(r.a).name)}</figcaption></figure>
<figure><img src="{tb}"><figcaption>{esc(r.label_b)} · {esc(Path(r.b).name)}</figcaption></figure>
<figure><img src="{r.heatmap}"><figcaption>pixel ΔE2000 · black 0 → white ≥ {n['heat_top']:.1f}</figcaption></figure></div>
</section>""")
    (out_dir / "report.md").write_text("\n".join(md) + "\n")
    html = f"""<!doctype html><meta charset=utf-8><title>Visual check {esc(meta['run'])}</title>
<style>
body{{font:14px -apple-system,system-ui,sans-serif;margin:16px;background:#111;color:#ddd}}
h1{{font-size:18px}} h2{{font-size:15px;margin:0 0 6px}}
section{{border:1px solid #333;border-radius:6px;padding:10px;margin:0 0 14px}}
section.f{{border-color:#c84}} .flag{{color:#fb6}} .ok{{color:#7c7}}
.num{{color:#999;font-variant-numeric:tabular-nums}}
.row{{display:flex;gap:8px;flex-wrap:wrap}} figure{{margin:0;flex:1 1 300px}}
img{{width:100%;display:block}} figcaption{{color:#888;font-size:12px}}
</style>
<h1>Visual check · {esc(meta['run'])}</h1>
<p>{sum(r.flagged for r in results)} of {len(results)} pairs flagged · model {esc(meta['model'] or 'off')} ·
thresholds {esc(json.dumps(THRESHOLDS))}</p>
{''.join(rows)}"""
    (out_dir / "index.html").write_text(html)
    return out_dir / "index.html"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pairs", required=True, help="dir of <stem>-before/-after images, or a list file")
    ap.add_argument("--out", required=True, help="output dir, e.g. ~/LuminaEvidence/visualcheck/<run>")
    ap.add_argument("--no-model", action="store_true", help="numbers only")
    ap.add_argument("--endpoint", default=ENDPOINT)
    ap.add_argument("--model", default=MODEL)
    args = ap.parse_args(argv)
    if not args.no_model:
        require_loopback(args.endpoint)
    out = Path(args.out).expanduser()
    repo = Path(__file__).resolve().parents[2]
    if out.resolve().is_relative_to(repo):
        raise SystemExit("--out is inside the repo: photos and heatmaps belong in ~/LuminaEvidence")
    pairs = load_pairs(args.pairs)
    if not pairs:
        raise SystemExit(f"no pairs found in {args.pairs}")
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for p in pairs:
        r = check_pair(p, out, not args.no_model, args.endpoint, args.model)
        results.append(r)
        m = r.model
        print(f"{'FLAG' if r.flagged else 'ok  '} {r.name}: ΔE {r.numbers['median']:.2f}/"
              f"{r.numbers['p95']:.2f} · {'; '.join(r.reasons) or '—'}"
              + (f" · model: {m['reason']} ({m['seconds']:.1f} s)" if m else "")
              + (f" · {r.error}" if r.error else ""), flush=True)
    page = write_report(results, out, {"run": out.name, "model": None if args.no_model else args.model,
                                       "pairs": str(args.pairs)})
    print(f"{sum(r.flagged for r in results)}/{len(results)} flagged · {page}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
