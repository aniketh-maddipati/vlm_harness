#!/usr/bin/env python3
"""Stream D — summarize a metrics.json written by `DevelopEvalHarnessTests`.

Reads numbers, prints Markdown. No pixels, no filenames beyond the camera's frame
numbers. Pure standard library so it runs anywhere the harness does.

Usage:
    python3 Scripts/harness/eval/report.py METRICS_JSON [--out SUMMARY_MD]

Sections:
  1. Pixel distance per arm (mean ΔE76, PSNR, signed L* bias), full frame and centre,
     split into untouched frames (the decoder gap) and edited frames.
  2. Oracle ceiling: how far the rendered slider subset can get, and whether the
     residual grows with the controls Lumina does not render (whites / blacks …).
  3. Slider-space distance of each proposal arm from the hand edit, per field, with
     the share of frames where the proposal moved the same way the photographer did.
  4. Diagnostics: preview-vs-export gap for the auto recipe, subject-weighted
     metering effect, model fallbacks.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics as st
from pathlib import Path

PROPOSAL_ARMS = ("oracle", "auto", "autoSubject", "model")
ALL_ARMS = ("neutral", "lrMapped", "oracle", "auto", "autoSubject", "autoWB", "model")
TONE_FIELDS = ("exposure", "contrast", "highlights", "shadows", "vibrance", "saturation")


def mean(values: list[float]) -> float | None:
    return st.fmean(values) if values else None


def median(values: list[float]) -> float | None:
    return st.median(values) if values else None


def fmt(value: float | None, digits: int = 2) -> str:
    return "—" if value is None else f"{value:.{digits}f}"


def pearson(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 3:
        return None
    mx, my = st.fmean(xs), st.fmean(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if sxx == 0 or syy == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / math.sqrt(sxx * syy)


def pixel(frame: dict, arm: str, key: str) -> float | None:
    entry = frame.get("arms", {}).get(arm, {})
    px = entry.get("pixel")
    return None if px is None else px.get(key)


def recipe(frame: dict, arm: str) -> dict | None:
    return frame.get("arms", {}).get(arm, {}).get("recipe")


def sign(value: float) -> int:
    return (value > 0) - (value < 0)


def pixel_table(frames: list[dict], arms: tuple[str, ...]) -> list[str]:
    lines = [
        "| arm | n | ΔE mean | ΔE median | centre ΔE | PSNR dB | L* bias |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for arm in arms:
        de = [v for f in frames if (v := pixel(f, arm, "deltaE")) is not None]
        if not de:
            continue
        cde = [v for f in frames if (v := pixel(f, arm, "centerDeltaE")) is not None]
        ps = [v for f in frames if (v := pixel(f, arm, "psnr")) is not None]
        dl = [v for f in frames if (v := pixel(f, arm, "deltaL")) is not None]
        lines.append(
            f"| {arm} | {len(de)} | {fmt(mean(de))} | {fmt(median(de))} | {fmt(mean(cde))} "
            f"| {fmt(mean(ps), 1)} | {fmt(mean(dl))} |"
        )
    return lines


def slider_table(frames: list[dict]) -> list[str]:
    lines = [
        "| arm | field | n | MAE | same direction | hand-edit mean |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for arm in PROPOSAL_ARMS:
        rows = [(f["lr"], recipe(f, arm)) for f in frames if recipe(f, arm) and "lr" in f]
        if not rows:
            continue
        for field in TONE_FIELDS:
            errs = [abs(r[field] - lr[field]) for lr, r in rows]
            moved = [(lr[field], r[field]) for lr, r in rows if lr[field] != 0]
            agree = [sign(a) == sign(b) for a, b in moved]
            share = f"{100 * sum(agree) / len(agree):.0f}% of {len(agree)}" if agree else "—"
            lines.append(
                f"| {arm} | {field} | {len(errs)} | {fmt(mean(errs))} | {share} "
                f"| {fmt(mean([lr[field] for lr, _ in rows]))} |"
            )
        # White balance: absolute Kelvin on both sides. As-shot on the Lumina side is the
        # decoder's native Kelvin; on the Lightroom side it is the value Lightroom shows.
        temps = []
        for f in frames:
            r = recipe(f, arm)
            if not r or "native" not in f:
                continue
            lumina_k = f["native"]["temperature"] if abs(r["temperature"] - 6500) <= 1 else r["temperature"]
            temps.append(abs(lumina_k - f["lr"]["temperature"]))
        lines.append(f"| {arm} | temperature (K) | {len(temps)} | {fmt(mean(temps), 0)} | — | — |")
    return lines


def build_report(doc: dict) -> str:
    frames = [f for f in doc["frames"] if "arms" in f]
    untouched = [f for f in frames if f.get("untouched")]
    edited = [f for f in frames if not f.get("untouched")]
    out: list[str] = []
    out.append(f"# Develop eval — `{doc.get('evalSet')}`")
    out.append("")
    out.append(
        f"Generated {doc.get('generatedAt')} · {len(frames)} frames "
        f"({len(untouched)} untouched, {len(edited)} edited) · decode {doc.get('decodeLongEdge')} px, "
        f"compare {doc.get('compareLongEdge')} px · decoder `{doc.get('decoder')}` · "
        f"{doc.get('seconds', 0) / 60:.1f} min"
    )
    out.append("")
    out.append("ΔE is mean CIE76 ΔE*ab in sRGB-derived Lab against the photographer's export; lower is closer. "
               "L* bias is Lumina minus the export: positive means Lumina renders brighter.")
    out.append("")

    out.append("## 1. Decoder gap — untouched frames")
    out.append("")
    out.append("The photographer left these frames at Lightroom defaults, so every arm's distance here is "
               "Apple's decode + Lumina's graph versus Adobe's, not taste. `neutral` is the number to read; "
               "`oracle` shows how much of that gap the rendered sliders can absorb.")
    out.append("")
    out.extend(pixel_table(untouched, ("neutral", "lrMapped", "oracle", "auto", "autoSubject")))
    out.append("")

    out.append("## 2. Edited frames — distance to the hand edit")
    out.append("")
    out.extend(pixel_table(edited, ALL_ARMS))
    out.append("")
    calib = mean([v for f in untouched if (v := pixel(f, "neutral", "deltaE")) is not None])
    if calib is not None:
        out.append(f"Subtract the decoder gap ({calib:.2f} ΔE on untouched frames) to read these as taste distance.")
        out.append("")

    out.append("## 3. Oracle ceiling")
    out.append("")
    residual = [(f, v) for f in edited if (v := pixel(f, "oracle", "deltaE")) is not None]
    if residual:
        mapped = [v for f, _ in residual if (v := pixel(f, "lrMapped", "deltaE")) is not None]
        out.append(
            f"Best slider-only fit reaches mean ΔE {fmt(mean([v for _, v in residual]))} "
            f"(the 1:1 mapped hand edit sits at {fmt(mean(mapped))}). "
            "Whatever remains is outside the rendered subset — decoder, whites/blacks, vignette, curve."
        )
        mags = [f["unrenderedMagnitude"] for f, _ in residual]
        r = pearson(mags, [v for _, v in residual])
        heavy = [v for f, v in residual if f["unrenderedMagnitude"] >= 20]
        light = [v for f, v in residual if f["unrenderedMagnitude"] < 20]
        out.append("")
        out.append("| unrendered controls (|whites|+|blacks|+…) | n | oracle ΔE |")
        out.append("|---|---:|---:|")
        out.append(f"| < 20 | {len(light)} | {fmt(mean(light))} |")
        out.append(f"| ≥ 20 | {len(heavy)} | {fmt(mean(heavy))} |")
        out.append("")
        out.append(f"Pearson r between unrendered magnitude and oracle residual: {fmt(r, 2)}.")
        # Slider-scale calibration: if Lumina's shadows/highlights act stronger than
        # Lightroom's, the oracle keeps the hand values but pulls exposure down to
        # compensate, and that pull grows with the size of the shadow lift.
        pairs = [
            (f["lr"]["shadows"] - f["lr"]["highlights"], recipe(f, "oracle")["exposure"] - f["lr"]["exposure"])
            for f, _ in residual if recipe(f, "oracle")
        ]
        if pairs:
            r_exp = pearson([a for a, _ in pairs], [b for _, b in pairs])
            out.append("")
            out.append(
                f"Oracle exposure minus hand exposure: mean {fmt(mean([b for _, b in pairs]))} EV; "
                f"Pearson r against the hand edit's (shadows − highlights) lift: {fmt(r_exp, 2)}. "
                "A strongly negative r means Lumina's shadow/highlight controls brighten more per unit than Lightroom's."
            )
        evals = [f["arms"]["oracle"].get("evaluations", 0) for f, _ in residual]
        decodes = [f["arms"]["oracle"].get("decodes", 0) for f, _ in residual]
        out.append(f"Search cost per frame: {fmt(mean(evals), 0)} look evaluations, {fmt(mean(decodes), 0)} decodes.")
    out.append("")

    out.append("## 4. Slider space — proposal vs hand edit (edited frames)")
    out.append("")
    out.append("MAE in slider units; \"same direction\" counts frames where the photographer moved the "
               "control and the proposal moved it the same way.")
    out.append("")
    out.extend(slider_table(edited))
    out.append("")

    out.append("## 5. Diagnostics")
    out.append("")
    tier: dict[str, list[float]] = {}
    for f in frames:
        gap = f.get("tierGap") or {}
        if "deltaE" in gap:  # first schema: auto only
            gap = {"auto": gap}
        for arm, px in gap.items():
            if isinstance(px, dict) and "deltaE" in px:
                tier.setdefault(arm, []).append(px["deltaE"])
    as_is = [
        px["asIsDeltaE"] for f in frames
        for arm, px in (f.get("tierGap") or {}).items() if arm == "neutral" and "asIsDeltaE" in px
    ]
    if as_is:
        out.append(f"- **Interactive texture orientation:** the texture-backed interactive image compared as-is "
                   f"to the authoritative render: mean ΔE {fmt(mean(as_is))} on `neutral` over {len(as_is)} frames "
                   "(a value far above the mirrored gap below means the interactive stage is upside down in CI space).")
    for arm, gaps in tier.items():
        custom = [
            (f.get("tierGap") or {}).get(arm, {}).get("deltaE")
            for f in frames if f.get("whiteBalance") != "As Shot"
        ]
        custom = [g for g in custom if g is not None]
        note = f"; custom-WB frames only: {fmt(mean(custom))} over {len(custom)}" if arm == "lrMapped" and custom else ""
        out.append(f"- **Preview ≡ export, `{arm}` recipe:** interactive vs authoritative tier "
                   f"mean ΔE {fmt(mean(gaps))}, max {fmt(max(gaps))} over {len(gaps)} frames{note}.")
    drift = [f["wbDrift"]["deltaE"] for f in frames if "wbDrift" in f]
    if drift:
        out.append(f"- **Auto's white balance alone** (native Kelvin, tint 0) moves the authoritative render "
                   f"by mean ΔE {fmt(mean(drift))}, max {fmt(max(drift))} from the as-shot decode "
                   f"over {len(drift)} frames; 0 would mean it is exactly as-shot.")
    methods: dict[str, int] = {}
    shifts = []
    for f in frames:
        subj = f.get("arms", {}).get("autoSubject")
        auto = recipe(f, "auto")
        if subj and auto and subj.get("recipe"):
            methods[subj.get("method", "?")] = methods.get(subj.get("method", "?"), 0) + 1
            shifts.append(subj["recipe"]["exposure"] - auto["exposure"])
    if shifts:
        big = sum(1 for s in shifts if abs(s) >= 0.10)
        out.append(f"- **Subject-weighted metering:** methods {methods}; exposure moved by ≥ 0.10 EV on "
                   f"{big}/{len(shifts)} frames, mean |Δ| {fmt(mean([abs(s) for s in shifts]))} EV, "
                   f"mean signed Δ {fmt(mean(shifts))} EV.")
    straight = [f["autoStraighten"] for f in frames if "autoStraighten" in f]
    if straight:
        out.append(f"- **Auto straighten** proposed a non-zero angle on "
                   f"{sum(1 for s in straight if abs(s) > 0.05)}/{len(straight)} frames "
                   f"(the hand edits rotate none); pixels above were compared with straighten zeroed.")
    if doc.get("liveModel"):
        out.append(f"- **Model arm:** {doc.get('modelFallbacks', 0)} of {len(frames)} frames fell back to "
                   "the deterministic recipe.")
    secs = [f["seconds"] for f in frames if "seconds" in f]
    if secs:
        out.append(f"- **Cost:** {fmt(mean(secs), 1)} s per frame.")
    out.append("")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("metrics", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    doc = json.loads(args.metrics.read_text(encoding="utf-8"))
    report = build_report(doc)
    if args.out:
        args.out.write_text(report, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
