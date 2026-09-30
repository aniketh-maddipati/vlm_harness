#!/usr/bin/env python3
"""The parity run: Lumina renders for every reference, ΔE2000 per pair, report.md (Prompt 2 §1–3).
`make parity` calls this; loop.sh calls it once per stage.

    python3 Tools/parity/parity.py [--refs ~/LuminaEvidence/parity/refs.json] [--golden Tools/parity/golden.json]
                                   [--stage tone | --slider Highlights] [--kinds base,single,combo]
                                   [--render-dir ~/LuminaEvidence/parity/render] [--evidence ~/LuminaEvidence/parity/report]
                                   [--report Tools/parity/report] [--rules Lumina/Sets/Look/rules-v1.json]
                                   [--render-bin Tools/parity/lumina-render/.build/release/lumina-render]
                                   [--limit N] [--reuse] [--label name]

Steps: (1) as-shot white balance of each golden ARW from `lumina-render info` (cached); (2) each
reference's Lightroom settings → a look string (Temperature / Tint as a mired / tint *delta* from
Lightroom's as-shot, applied to Apple's as-shot, because the two estimate Kelvin differently);
(3) one `lumina-render batch` for all renders; (4) delta_e.measure per pair; (5) pooled statistics
per slider and per position, region breakdown, heatmaps for the worst five pairs.

Writes two copies of the report: numbers only under --report (committed), numbers + heatmaps under
--evidence (photo content, stays on the Mac). summary.json next to each is what loop.sh reads.

Needs the Mac: lumina-render is Core Image. The measuring and reporting half runs anywhere
(see tests/test_parity.py, which drives it with fake renders).
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import delta_e  # noqa: E402
import lookmath  # noqa: E402

LR_KEYS = {"Exposure": "ev", "Contrast": "con", "Highlights": "hl", "Shadows": "sh", "Whites": "wh", "Blacks": "bl",
           "Vibrance": "vib", "Saturation": "sat", "Clarity": "clr", "Sharpness": "shp", "Sharpening": "shp"}


def expand(p):
    return os.path.abspath(os.path.expanduser(p))


def lr_to_look(settings, lr_as_shot, apple_as_shot):
    """Lightroom develop settings → look dict. Temperature/Tint move Apple's as-shot by the same
    mired / tint delta Lightroom's slider moved its as-shot."""
    look = lookmath.parse_look("")
    for name, value in settings.items():
        if name in LR_KEYS:
            look[LR_KEYS[name]] = float(value)
    if "Temperature" in settings or "Tint" in settings:
        lr_t, lr_tint = float(lr_as_shot.get("Temperature", apple_as_shot[0])), float(lr_as_shot.get("Tint", apple_as_shot[1]))
        t = float(settings.get("Temperature", lr_t))
        tint = float(settings.get("Tint", lr_tint))
        mired = 1e6 / apple_as_shot[0] - (1e6 / lr_t - 1e6 / t)
        kelvin = min(50000.0, max(2000.0, 1e6 / max(mired, 20.0)))
        look["wb"] = (kelvin, min(150.0, max(-150.0, apple_as_shot[1] + (tint - lr_tint))))
    return look


def as_shot_of(render_bin, arw, cache):
    if arw in cache:
        return cache[arw]
    out = subprocess.run([render_bin, "info", arw], capture_output=True, text=True, check=True).stdout
    info = json.loads(out.strip().splitlines()[-1])
    cache[arw] = (float(info["asShot"]["kelvin"]), float(info["asShot"]["tint"]))
    return cache[arw]


def find_raw(stem, golden, extra_dirs):
    root = expand(golden.get("root", "~/LuminaEvidence/parity/golden"))
    for d in [root] + list(extra_dirs):
        for ext in ("ARW", "arw", "DNG", "dng"):
            p = os.path.join(d, f"{stem}.{ext}")
            if os.path.exists(p):
                return p
    return None


def select(refs, stage=None, slider=None, kinds=("base", "single", "combo"), limit=None):
    out = []
    for r in refs:
        if r["kind"] not in kinds or r.get("error"):
            continue
        if slider and r["kind"] == "single" and r["slider"] != slider:
            continue
        if stage and r["kind"] == "single" and lookmath.SLIDER_STAGE.get(r["slider"]) != stage:
            continue
        if (stage or slider) and r["kind"] == "combo":
            continue
        out.append(r)
    if limit:
        stems = sorted({r["stem"] for r in out})[:limit]
        out = [r for r in out if r["stem"] in stems]
    return out


def pooled(samples):
    """Statistics over the pooled per-pair subsamples (each pair contributes the same number of
    ΔE values, so an image with more pixels doesn't weigh more)."""
    if not samples:
        return {"n": 0, "pairs": 0}
    v = np.concatenate(samples)
    return {"n": int(v.size), "pairs": len(samples), "median": float(np.median(v)), "p95": float(np.percentile(v, 95)), "mean": float(np.mean(v))}


def aggregate(results, criteria):
    """results: list of {ref, measure} → per-slider / per-position / per-kind statistics."""
    by_slider, by_pos, by_kind = {}, {}, {}
    region_by_slider = {}
    for item in results:
        r, m = item["ref"], item["measure"]
        key = r["slider"] if r["kind"] == "single" else r["kind"]
        by_slider.setdefault(key, []).append(m["sample"])
        by_kind.setdefault(r["kind"], []).append(m["sample"])
        if r["kind"] == "single":
            by_pos.setdefault(key, {}).setdefault(r["value"], []).append(m["sample"])
        for reg in ("shadows", "midtones", "highlights", "skin"):
            if m[reg].get("n"):
                region_by_slider.setdefault(key, {}).setdefault(reg, []).append(m[reg]["median"])
    sliders = {}
    for key, samples in by_slider.items():
        s = pooled(samples)
        if key in lookmath.SLIDER_STAGE:
            crit = criteria["singles"]
            s["pass"] = s["median"] <= crit["median"] and s["p95"] <= crit["p95"]
            s["stage"] = lookmath.SLIDER_STAGE[key]
        elif key == "combo":
            crit = criteria["combos"]
            s["pass"] = s["median"] <= crit["median"] and s["p95"] <= crit["p95"]
        s["positions"] = {str(v): pooled(x) for v, x in sorted(by_pos.get(key, {}).items())}
        s["regions"] = {reg: float(np.median(v)) for reg, v in region_by_slider.get(key, {}).items()}
        sliders[key] = s
    stages = {}
    for stage in lookmath.STAGES:
        keys = [k for k, v in lookmath.SLIDER_STAGE.items() if v == stage and k in sliders]
        if keys:
            st = pooled([s for k in keys for s in by_slider[k]])
            st["sliders"] = keys
            st["pass"] = all(sliders[k]["pass"] for k in keys)
            stages[stage] = st
    worst = sorted(results, key=lambda i: -i["measure"]["all"]["p95"])[:5]
    return {"sliders": sliders, "stages": stages, "kinds": {k: pooled(v) for k, v in by_kind.items()},
            "worst": [{"id": w["ref"]["id"], "median": w["measure"]["all"]["median"], "p95": w["measure"]["all"]["p95"]} for w in worst]}


def report_md(agg, results, criteria, meta, heatmap_dir=None):
    L = []
    L.append(f"# Parity report — {meta['label']}\n")
    L.append(f"{meta['date']} · rules `{meta['rules']}` · {len(results)} pairs · {meta.get('images', '?')} images · px {meta.get('px')} · space {meta.get('space')}\n")
    if meta.get("stage"):
        L.append(f"Stage under test: **{meta['stage']}**\n")
    crit = criteria["singles"]
    L.append(f"Criteria (singles): median ≤ {crit['median']}, p95 ≤ {crit['p95']}; combos: median ≤ {criteria['combos']['median']}, p95 ≤ {criteria['combos']['p95']}.\n")
    L.append("## Per slider\n")
    L.append("| slider | stage | pairs | median | p95 | mean | shadows | midtones | highlights | skin | pass |")
    L.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|")
    for key in lookmath.LR_SLIDERS + ["base", "combo"]:
        s = agg["sliders"].get(key)
        if not s:
            continue
        reg = s.get("regions", {})
        f = lambda x: f"{x:.2f}" if isinstance(x, (int, float)) else "–"
        L.append(f"| {key} | {s.get('stage', '')} | {s['pairs']} | {f(s.get('median'))} | {f(s.get('p95'))} | {f(s.get('mean'))} | "
                 f"{f(reg.get('shadows'))} | {f(reg.get('midtones'))} | {f(reg.get('highlights'))} | {f(reg.get('skin'))} | "
                 f"{'✓' if s.get('pass') else ('✗' if 'pass' in s else '')} |")
    L.append("")
    for key in lookmath.LR_SLIDERS:
        s = agg["sliders"].get(key)
        if not s or not s.get("positions"):
            continue
        L.append(f"### {key} by position\n")
        L.append("| value | pairs | median | p95 | mean |")
        L.append("|---:|---:|---:|---:|---:|")
        for v, p in s["positions"].items():
            L.append(f"| {v} | {p['pairs']} | {p['median']:.2f} | {p['p95']:.2f} | {p['mean']:.2f} |" if p.get("n") else f"| {v} | 0 | – | – | – |")
        L.append("")
    if agg["stages"]:
        L.append("## Per stage\n")
        L.append("| stage | sliders | median | p95 | pass |")
        L.append("|---|---|---:|---:|:---:|")
        for st, s in agg["stages"].items():
            L.append(f"| {st} | {', '.join(s['sliders'])} | {s['median']:.2f} | {s['p95']:.2f} | {'✓' if s['pass'] else '✗'} |")
        L.append("")
    L.append("## Worst five pairs\n")
    for w in agg["worst"]:
        line = f"- `{w['id']}` median {w['median']:.2f}, p95 {w['p95']:.2f}"
        if heatmap_dir:
            line += f" — heatmap `{os.path.join(heatmap_dir, w['id'] + '.de.png')}`"
        L.append(line)
    L.append("")
    L.append("## Error by reference L* decile (mean ΔE, all pairs)\n")
    dec = np.array([[x if x is not None else np.nan for x in it["measure"]["byL"]] for it in results], dtype=float)
    if dec.size:
        means = np.nanmean(dec, axis=0)
        L.append("| " + " | ".join(f"{lo}–{lo + 10}" for lo in range(0, 100, 10)) + " |")
        L.append("|" + "---:|" * 10)
        L.append("| " + " | ".join("–" if np.isnan(m) else f"{m:.2f}" for m in means) + " |")
    L.append("")
    L.append("## Residual and change\n")
    L.append("_(the loop writes one paragraph here per iteration: what the residual looks like and what changed)_\n")
    return "\n".join(L)


def run(a):
    refs_path = expand(a.refs)
    with open(refs_path) as f:
        refs_doc = json.load(f)
    with open(expand(a.golden)) as f:
        golden = json.load(f)
    with open(expand(a.criteria)) as f:
        criteria = json.load(f)
    kinds = tuple(a.kinds.split(","))
    refs = select(refs_doc["refs"], stage=a.stage, slider=a.slider, kinds=kinds, limit=a.limit)
    if not refs or ((a.stage or a.slider) and not any(r["kind"] == "single" for r in refs)):
        print(f"no references selected for {a.stage or a.slider or 'the run'} in {refs_path}", file=sys.stderr)
        return 2
    date = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    label = a.label or (a.stage or a.slider or "all")
    render_dir = expand(a.render_dir)
    evidence = os.path.join(expand(a.evidence), f"{date}-{label}")
    report_dir = os.path.join(expand(a.report), f"{date}-{label}")
    os.makedirs(render_dir, exist_ok=True)
    os.makedirs(evidence, exist_ok=True)
    os.makedirs(report_dir, exist_ok=True)
    space = a.space or (refs[0].get("space") or "prophoto")

    # 1. as-shot per image, 2. looks, 3. jobs
    cache_path = os.path.join(render_dir, "asshot.json")
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    cache = {k: tuple(v) for k, v in cache.items()}
    jobs, pairs, missing = [], [], []
    for r in refs:
        arw = find_raw(r["stem"], golden, a.raws or [])
        if not arw:
            missing.append(r["stem"])
            continue
        apple = as_shot_of(a.render_bin, arw, cache)
        look = lr_to_look(r["settings"], r.get("asShot", {}), apple)
        text = lookmath.format_look(look)
        out = os.path.join(render_dir, label, r["id"] + ".lumina.tif")
        jobs.append({"image": arw, "look": text, "px": a.px, "out": out, "space": space})
        pairs.append((r, out, text))
    with open(cache_path, "w") as f:
        json.dump(cache, f, indent=1, sort_keys=True)
    if missing:
        print(f"no ARW for {len(set(missing))} images (looked in {golden.get('root')} and --raws): {sorted(set(missing))[:8]}", file=sys.stderr)
    if not pairs:
        return 2
    plan = os.path.join(render_dir, f"jobs-{date}-{label}.json")
    todo = [j for j in jobs if not (a.reuse and os.path.exists(j["out"]))]
    with open(plan, "w") as f:
        json.dump(todo, f, indent=1)
    timings = []
    if todo:
        print(f"rendering {len(todo)} looks with {a.render_bin} …")
        p = subprocess.run([a.render_bin, "batch", plan] + (["--rules", expand(a.rules)] if a.rules else []), capture_output=True, text=True)
        for line in p.stdout.splitlines():
            try:
                timings.append(json.loads(line))
            except ValueError:
                pass
        bad = [t for t in timings if not t.get("ok")]
        if p.returncode != 0 or bad:
            print(f"{len(bad)} renders failed; first: {bad[0].get('error') if bad else p.stderr[-400:]}", file=sys.stderr)

    # 4. measure
    results = []
    for r, out, text in pairs:
        if not os.path.exists(out):
            continue
        try:
            m = delta_e.measure_files(r["path"], out, space)
        except Exception as e:
            print(f"{r['id']}: {e}", file=sys.stderr)
            continue
        results.append({"ref": r, "measure": m, "look": text})
    if not results:
        print("nothing measured", file=sys.stderr)
        return 2

    # 5. report
    agg = aggregate(results, criteria)
    render_ms = [t["renderMs"] for t in timings if t.get("ok")]
    develop_ms = [t["developMs"] for t in timings if t.get("ok") and t.get("developMs")]
    meta = {"label": label, "date": date, "rules": a.rules or "Lumina/Sets/Look/rules-v1.json", "images": len({r["stem"] for r, _, _ in pairs}),
            "px": a.px, "space": space, "stage": a.stage, "slider": a.slider,
            "renderMs": {"median": float(np.median(render_ms)) if render_ms else None, "p95": float(np.percentile(render_ms, 95)) if render_ms else None},
            "developMs": {"median": float(np.median(develop_ms)) if develop_ms else None}}
    heat_dir = os.path.join(evidence, "heatmaps")
    os.makedirs(heat_dir, exist_ok=True)
    by_id = {it["ref"]["id"]: it for it in results}
    for w in agg["worst"]:
        delta_e.heatmap(by_id[w["id"]]["measure"]["map"], os.path.join(heat_dir, w["id"] + ".de.png"))
    summary = {"meta": meta, "criteria": criteria, "aggregate": agg,
               "pairs": [{"id": it["ref"]["id"], "kind": it["ref"]["kind"], "slider": it["ref"].get("slider"), "value": it["ref"].get("value"),
                          "look": it["look"], **{k: it["measure"][k] for k in ("all", "shadows", "midtones", "highlights", "skin", "byL")}} for it in results]}
    for d, heat in ((report_dir, None), (evidence, heat_dir)):
        with open(os.path.join(d, "report.md"), "w") as f:
            f.write(report_md(agg, results, criteria, meta, heat))
        with open(os.path.join(d, "summary.json"), "w") as f:
            json.dump(summary, f, indent=1, sort_keys=True, default=float)
    latest = os.path.join(expand(a.report), "latest.json")
    with open(latest, "w") as f:
        json.dump({"report": report_dir, "evidence": evidence, "label": label, "date": date}, f, indent=1)
    print(open(os.path.join(report_dir, "report.md")).read())
    print(f"report → {report_dir}/report.md · evidence + heatmaps → {evidence}")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--refs", default="~/LuminaEvidence/parity/refs.json")
    ap.add_argument("--golden", default=os.path.join(HERE, "golden.json"))
    ap.add_argument("--criteria", default=os.path.join(HERE, "criteria.json"))
    ap.add_argument("--raws", action="append", help="extra folders to find <stem>.ARW in")
    ap.add_argument("--stage", choices=lookmath.STAGES)
    ap.add_argument("--slider", choices=lookmath.LR_SLIDERS)
    ap.add_argument("--kinds", default="base,single,combo")
    ap.add_argument("--render-dir", default="~/LuminaEvidence/parity/render")
    ap.add_argument("--evidence", default="~/LuminaEvidence/parity/report")
    ap.add_argument("--report", default=os.path.join(HERE, "report"))
    ap.add_argument("--rules")
    ap.add_argument("--render-bin", default=os.path.join(HERE, "lumina-render", ".build", "release", "lumina-render"))
    ap.add_argument("--px", type=int, default=2048)
    ap.add_argument("--space", choices=["prophoto", "srgb", "p3"])
    ap.add_argument("--limit", type=int, help="first N images only (a quick look)")
    ap.add_argument("--reuse", action="store_true", help="keep renders that already exist")
    ap.add_argument("--label")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
