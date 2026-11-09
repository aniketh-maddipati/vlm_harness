#!/usr/bin/env python3
"""Score Skim's ⇧E against the adaCG annotator. Numbers only; see README.md.

    ~/LuminaEvidence/venv-parity/bin/python -I Tools/exposeval/run.py \
        --pkl /Volumes/T7/Lumina/datasets/hdrvs-adacg/trainDemo8b.pkl.UNTRUSTED-do-not-unpickle \
        --tiffs /Volumes/T7/Lumina/datasets/hdrvs-adacg/adaCG \
        --out ~/LuminaEvidence/exposeval --report Tools/exposeval/report/<date>.md

Run with -I (isolated: nothing on the path from the current folder) and from outside the data folder.
Needs numpy and Pillow (thumbnails); tifffile only for --tiffs.
"""

import argparse
import datetime
import io
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import adacg  # noqa: E402
import rule  # noqa: E402
import score  # noqa: E402
import target  # noqa: E402

LOCATIONS = ("utah", "alaska", "seattle", "nyc", "toronto", "london")


def location_of(labels):
    for l in labels:
        if l in LOCATIONS:
            return l
    return "none"


def session_of(labels):
    return "+".join(sorted(labels)) or "none"


def decode_thumb(buf):
    from PIL import Image
    im = Image.open(io.BytesIO(bytes(np.asarray(buf, dtype=np.uint8))))
    return np.asarray(im.convert("RGB"), dtype=np.uint8)


def frame_from_tiff(path, size=(320, 180)):
    """A full still as Skim's canvas would hold it: 8-bit, drawn at 320 × 180."""
    import tifffile
    from PIL import Image
    a = tifffile.imread(path)
    if a.dtype == np.uint16:
        a = np.round(a.astype(np.float64) / 65535.0 * 255.0).astype(np.uint8)
    a = a[..., :3]
    return np.asarray(Image.fromarray(a).resize(size, Image.BOX), dtype=np.uint8)


def hist_median(h):
    """Median linear Y from the label's histogram (256 bins over [0, 1]; scaling keeps proportions)."""
    h = np.asarray(h, dtype=np.float64)
    c = np.cumsum(h) / h.sum()
    i = int(np.searchsorted(c, 0.5))
    lo = c[i - 1] if i else 0.0
    frac = (0.5 - lo) / max(c[i] - lo, 1e-12)
    return (i + frac) / len(h)


def log_mean(frame, table):
    """Variant statistic: the log-average luminance (Reinhard's key), same sampling as sceneSl."""
    px = frame.reshape(-1, frame.shape[2])[::8]
    lin = table[px[:, 0]] * 0.2126 + table[px[:, 1]] * 0.7152 + table[px[:, 2]] * 0.0722
    return float(np.exp(np.mean(np.log(lin + 1e-4))))


PCTS = (10, 25, 50, 75, 90)


def sampled_lin(frame, table):
    px = frame.reshape(-1, frame.shape[2])[::8]
    return table[px[:, 0]] * 0.2126 + table[px[:, 1]] * 0.7152 + table[px[:, 2]] * 0.0722


def fit_thumb_map(pairs):
    """thumb ≈ s · full^g on encoded levels (pairs of (thumb, full) uint8 frames, same size) → (s, g)."""
    X = np.concatenate([f.astype(np.float64).ravel() / 255.0 for _, f in pairs])
    Y = np.concatenate([t.astype(np.float64).ravel() / 255.0 for t, _ in pairs])
    m = (X > 0.02) & (Y > 0.02) & (X < 0.98)
    g, ls = np.polyfit(np.log(X[m]), np.log(Y[m]), 1)
    return float(math.exp(ls)), float(g)


def corrected_table(s, g):
    """Thumbnail level → the full still's level (inverse of fit_thumb_map), then sRGB's curve undone."""
    v = np.arange(256, dtype=np.float64) / 255.0
    full = np.clip((v / s) ** (1.0 / g), 0.0, 1.0)
    return rule.srgb_to_linear(full)


def thumb_pairs(E, tiffs):
    from PIL import Image
    out = []
    for f in sorted(os.listdir(tiffs)):
        if f.lower().endswith((".tif", ".tiff")) and f in E and not f.startswith("._"):
            th = decode_thumb(E[f]["thumb"])
            full = frame_from_tiff(os.path.join(tiffs, f), size=(th.shape[1], th.shape[0]))
            out.append((f, th, full))
    return out


def build(db, thumb_map=None):
    E = adacg.entries(db)
    t_srgb = rule.level_table("rec709")
    t_g24 = rule.level_table("rec709", gamma=2.4)
    t_cor = corrected_table(*thumb_map) if thumb_map else t_srgb
    stills = []
    for name, e in E.items():
        fr = decode_thumb(e["thumb"])
        lin = sampled_lin(fr, t_srgb)
        stills.append({
            "name": name, "shot": adacg.shot_of(name), "labels": list(e["labels"]),
            "pivots": adacg.pivots(e),
            "sl": rule.scene_sl(fr, t_srgb),
            "sl_g24": rule.scene_sl(fr, t_g24),
            "sl_cor": rule.scene_sl(fr, t_cor),
            "pct": {p: float(np.percentile(lin, p)) for p in PCTS},
            "logmean": log_mean(fr, t_srgb),
            "hist_med": hist_median(e["hist"]),
            "thumb_px": [int(fr.shape[1]), int(fr.shape[0])],
        })
    shots = {}
    for s in stills:
        shots.setdefault(s["shot"], []).append(s)
    rows = []
    for k in sorted(shots):
        ss = shots[k]
        labs = ss[0]["labels"]
        rows.append({
            "shot": k, "n": len(ss),
            "location": location_of(labs), "session": session_of(labs),
            "clip": rule.clip_value([s["sl"] for s in ss]),
            "clip_g24": rule.clip_value([s["sl_g24"] for s in ss]),
            "clip_cor": rule.clip_value([s["sl_cor"] for s in ss]),
            "clip_pct": {p: rule.clip_value([max(s["pct"][p], 1e-4) for s in ss]) for p in PCTS},
            "labels": labs,
            "clip_logmean": float(np.exp(np.mean([math.log(s["logmean"]) for s in ss]))),
            "clip_hist": float(np.exp(np.mean([math.log(max(s["hist_med"], 1e-4)) for s in ss]))),
            "mid": {w: target.shot_log_mid([s["pivots"] for s in ss], w) for w in ("mid", "dark", "light")},
            "mid_spread": (abs(math.log2(target.to_linear(target.mid_code(ss[0]["pivots"])))
                               - math.log2(target.to_linear(target.mid_code(ss[1]["pivots"]))))
                           if len(ss) == 2 else None),
            "sl_spread": (abs(math.log2(ss[0]["sl"] / ss[1]["sl"])) if len(ss) == 2 and ss[0]["sl"] > 0 and ss[1]["sl"] > 0 else None),
        })
    return stills, rows


def relative_block(rows, group_key, which="mid", value=lambda r: r["clip"]):
    """Within each shoot (group): the annotator's relative target and ⇧E's map, per shot."""
    out = {"group": [], "shot": [], "target": [], "shipped": [], "unclamped": []}
    for g in sorted({r[group_key] for r in rows}):
        rs = [r for r in rows if r[group_key] == g and value(r)]
        if len(rs) < 2:
            continue
        tgt = target.relative_ev({r["shot"]: r["mid"][which] for r in rs})
        vals = {r["shot"]: value(r) for r in rs}
        shipped = rule.ev_auto_map(vals)
        free = rule.ev_auto_map(vals, clamp=None, round_to=None)
        for r in rs:
            out["group"].append(g)
            out["shot"].append(r["shot"])
            out["target"].append(tgt[r["shot"]])
            out["shipped"].append(shipped[r["shot"]])
            out["unclamped"].append(free[r["shot"]])
    return {k: (np.asarray(v) if k not in ("group",) else v) for k, v in out.items()}


def relative_scores(rows, gk, value=lambda r: r["clip"]):
    B = relative_block(rows, gk, value=value)
    t = B["target"]
    cvk, ks = score.cv_strength(B["group"], B["unclamped"], t)
    return B, {
        "n_groups": len(set(B["group"])),
        "target_abs_over_1": float(np.mean(np.abs(t) > 1.0)),
        "target_std": float(t.std()),
        "none": score.metrics(np.zeros_like(t), t),
        "shipped": score.metrics(B["shipped"], t),
        "unclamped": score.metrics(B["unclamped"], t),
        "strength_cv": score.metrics(cvk, t),
        "strength_cv_clamped": score.metrics(np.clip(cvk, -1, 1), t),
        "strength_k": ks,
        "strength_k_all": score.fit_slope(B["unclamped"], t),
    }


def run(pkl, tiffs=None):
    db = adacg.load(pkl)
    E = adacg.entries(db)
    res = {}
    thumb_map = None
    if tiffs and os.path.isdir(tiffs):
        pairs = thumb_pairs(E, tiffs)
        if pairs:
            thumb_map = fit_thumb_map([(t, f) for _, t, f in pairs])
            t_srgb = rule.level_table("rec709")
            chk = []
            for f, th, _ in pairs:
                full = rule.scene_sl(frame_from_tiff(os.path.join(tiffs, f)), t_srgb)
                chk.append((math.log2(rule.scene_sl(th, t_srgb) / full),
                            math.log2(rule.scene_sl(th, corrected_table(*thumb_map)) / full)))
            chk = np.array(chk)
            res["thumb_vs_full"] = {"n": len(chk), "scale": thumb_map[0], "power": thumb_map[1],
                                    "median_stops": float(np.median(chk[:, 0])), "max_abs_stops": float(np.max(np.abs(chk[:, 0]))),
                                    "corrected_median_stops": float(np.median(chk[:, 1])), "corrected_max_abs_stops": float(np.max(np.abs(chk[:, 1])))}
    stills, rows = build(db, thumb_map)
    res.update({"stills": len(stills), "shots": len(rows),
                "shots_by_location": {g: sum(r["location"] == g for r in rows) for g in sorted({r["location"] for r in rows})},
                "sessions": len({r["session"] for r in rows})})

    P = np.array([s["pivots"] for s in stills])
    res["pivots"] = {"mean": P.mean(0).tolist(), "std": P.std(0).tolist(),
                     "at_default": float(np.mean(np.all(P == [0.1, 0.4, 0.5, 0.9], axis=1)))}

    ms = np.array([r["mid_spread"] for r in rows if r["mid_spread"] is not None])
    ss = np.array([r["sl_spread"] for r in rows if r["sl_spread"] is not None])
    res["within_shot"] = {"annotator_same_pivots": float(np.mean(ms == 0)),
                          "annotator_mid_abs_diff_median": float(np.median(ms)), "annotator_mid_abs_diff_p90": float(np.percentile(ms, 90)),
                          "annotator_mid_abs_diff_median_when_changed": float(np.median(ms[ms > 0])) if (ms > 0).any() else 0.0,
                          "image_median_abs_diff_median": float(np.median(ss)), "image_median_abs_diff_p90": float(np.percentile(ss, 90))}

    # Does the annotator's middle follow the image? log2(mid) = a + b·log2(statistic).
    stats = [("median", lambda r: r["clip"]), ("median, thumbnail corrected", lambda r: r["clip_cor"]),
             ("median, γ2.4 undone", lambda r: r["clip_g24"]), ("log-mean", lambda r: r["clip_logmean"]),
             ("median of the label histogram", lambda r: r["clip_hist"])]
    stats += [("p%d" % p, (lambda p: lambda r: r["clip_pct"][p])(p)) for p in PCTS if p != 50]
    follow = {}
    for nm, fn in stats:
        x = np.log2([max(fn(r), 1e-4) for r in rows])
        row = {}
        for w in ("mid", "dark", "light"):
            y = np.array([r["mid"][w] for r in rows])
            a, b = score.fit_line(x, y)
            row[w] = {"intercept": a, "slope": b, "pearson": score.pearson(x, y)}
        follow[nm] = row
    res["follow"] = follow

    # Relative (⇧E's frame).
    rel = {}
    for gk in ("location", "session"):
        B, sc = relative_scores(rows, gk)
        for w in ("dark", "light"):
            Bw = relative_block(rows, gk, which=w)
            sc["shipped_vs_" + w] = score.metrics(Bw["shipped"], Bw["target"])
        rel[gk] = sc
        if gk == "location":
            # where ⇧E misses: mean (target − shipped) by tag
            by = {r["shot"]: r for r in rows}
            resid = B["target"] - B["shipped"]
            tags = {}
            for tag in ("night", "sunset", "indoor", "urban"):
                m = np.array([tag in by[k]["labels"] for k in B["shot"]])
                tags[tag] = {"n": int(m.sum()), "mean_resid": float(resid[m].mean()) if m.any() else 0.0,
                             "median_abs_err": float(np.median(np.abs(resid[m]))) if m.any() else 0.0,
                             "mean_target": float(B["target"][m].mean()) if m.any() else 0.0,
                             "mean_shipped": float(B["shipped"][m].mean()) if m.any() else 0.0}
            m = np.array([not ({"night", "sunset", "indoor"} & set(by[k]["labels"])) for k in B["shot"]])
            tags["day outdoor"] = {"n": int(m.sum()), "mean_resid": float(resid[m].mean()), "median_abs_err": float(np.median(np.abs(resid[m]))),
                                   "mean_target": float(B["target"][m].mean()), "mean_shipped": float(B["shipped"][m].mean())}
            rel["by_tag"] = tags
    # the statistic sweep: k × (unclamped match on that statistic), k leave-one-shoot-out, clamped ±1
    sweep = {}
    for nm, fn in stats:
        _, sc = relative_scores(rows, "location", value=fn)
        sweep[nm] = {"shipped": sc["shipped"], "strength_cv_clamped": sc["strength_cv_clamped"], "k": sc["strength_k_all"]}
    rel["sweep"] = sweep
    res["relative"] = rel

    # Absolute: put the middle at 18 % grey.
    t_abs = np.array([math.log2(target.GREY18) - r["mid"]["mid"] for r in rows])
    locs = [r["location"] for r in rows]
    ab = {"target_mean": float(t_abs.mean()), "target_std": float(t_abs.std()),
          "none": score.metrics(np.zeros_like(t_abs), t_abs)}
    for nm, key in (("grey18", "clip"), ("grey18_cor", "clip_cor"), ("grey18_gamma24", "clip_g24")):
        p = np.array([math.log2(target.GREY18 / r[key]) for r in rows])
        ab[nm] = score.metrics(p, t_abs)
        cv, _ = score.cv_strength(locs, p, t_abs)
        ab[nm + "_strength_cv"] = score.metrics(cv, t_abs)
    res["absolute"] = ab
    return res, rows


def fmt(t, m):
    return ("| {t} | {n} | {median_abs:.2f} | {p90_abs:.2f} | {bias:+.2f} | {within_third:.0%} | {pearson:.2f} | {spearman:.2f} | {sign:.0%} ({sign_n}) |"
            .format(t=t, **m).replace("nan", "–"))


HEAD = ("| | shots | median \\|err\\| | p90 \\|err\\| | bias | ≤ ⅓ stop | Pearson | Spearman | sign (n) |\n"
        "|---|---|---|---|---|---|---|---|---|")


def report(res, pkl_name, date):
    L = []
    w = L.append
    rl, rs, ab, f, ws = (res["relative"]["location"], res["relative"]["session"], res["absolute"],
                         res["follow"], res["within_shot"])
    w("# Skim ⇧E vs the adaCG annotator, %s" % date)
    w("")
    w("Numbers only. Data: HDRVS adaCG subset (%s: %d stills, %d shots of two stills, one annotator), measured, "
      "never trained on. Method and caveats: `Tools/exposeval/README.md`. Errors in stops." % (pkl_name, res["stills"], res["shots"]))
    w("")
    w("**The labels hold no exposure choice.** The target is a proxy: the annotator's middle, halfway between where "
      "they put \"dark\" and \"light\" (P3 γ2.4 levels), in linear light; a shot's target is the stops that bring that "
      "middle to its shoot's median (⇧E's frame) or to 18 % grey (absolute). ⇧E is measured on the label thumbnails "
      "(102 × 54, what the tool stored with each label).")
    w("")
    tags = {k: v for k, v in res["relative"]["by_tag"].items() if v["n"] and k != "urban"}
    worst = sorted(tags.items(), key=lambda kv: -abs(kv[1]["mean_resid"]))[:2]
    w("## Summary")
    w("")
    w("- ⇧E as shipped is **%.2f stops** (median) from the annotator, p90 %.2f, r %.2f, right direction on %.0f%% of shots that "
      "move ⅓ stop or more. Doing nothing is %.2f / %.2f." % (rl["shipped"]["median_abs"], rl["shipped"]["p90_abs"], rl["shipped"]["pearson"],
                                                            100 * rl["shipped"]["sign"], rl["none"]["median_abs"], rl["none"]["p90_abs"]))
    w("- The annotator's middle moves **%.2f stops per stop** of the image's median (r %.2f): they keep dark shots darker and bright "
      "shots brighter than a full match. Unclamped, ⇧E overshoots (%.2f / %.2f). The best scale on the full match is k = %.2f, and "
      "⇧E's ±1 clamp already does about as well as that shrinkage (k × match: %.2f / %.2f)." % (
          f["median"]["mid"]["slope"], f["median"]["mid"]["pearson"], rl["unclamped"]["median_abs"], rl["unclamped"]["p90_abs"],
          rl["strength_k_all"], rl["strength_cv_clamped"]["median_abs"], rl["strength_cv_clamped"]["p90_abs"]))
    w("- The rest is scene intent, which a brightness statistic does not see. The largest misses by tag: %s." % "; ".join(
        "%s %+.2f (target %+.2f, ⇧E %+.2f)" % (k, v["mean_resid"], v["mean_target"], v["mean_shipped"]) for k, v in worst))
    w("")
    w("## Per shot, within a shoot (⇧E's frame)")
    w("")
    w("Shoot = location label (%d: %s). Target spread %.2f stops (std); %.0f%% of shots need more than ±1." % (
        rl["n_groups"], ", ".join("%s %d" % kv for kv in res["shots_by_location"].items()), rl["target_std"], 100 * rl["target_abs_over_1"]))
    w("")
    w(HEAD)
    for k, t in (("none", "no change"), ("shipped", "**⇧E as shipped** (±1, 1/100)"), ("unclamped", "⇧E, no clamp"),
                 ("strength_cv", "k × ⇧E unclamped, k leave-one-shoot-out"), ("strength_cv_clamped", "k × ⇧E, clamped ±1")):
        w(fmt(t, rl[k]))
    w("")
    w("k on all shoots %.2f; leave-one-shoot-out: %s." % (rl["strength_k_all"], ", ".join("%s %.2f" % kv for kv in sorted(rl["strength_k"].items()))))
    w("")
    w("Shoot = full label set (%d sessions, e.g. urban+night+london):" % rs["n_groups"])
    w("")
    w(HEAD)
    for k, t in (("none", "no change"), ("shipped", "**⇧E as shipped**"), ("unclamped", "⇧E, no clamp"),
                 ("strength_cv_clamped", "k × ⇧E, clamped ±1")):
        w(fmt(t, rs[k]))
    w("")
    w("Proxy sensitivity (⇧E as shipped, by location): the light pivot alone as the middle %.2f median / %.2f p90 (r %.2f); "
      "the dark pivot alone %.2f / %.2f (r %.2f; the dark pivot sits near 0 and is noisy in stops)." % (
        rl["shipped_vs_light"]["median_abs"], rl["shipped_vs_light"]["p90_abs"], rl["shipped_vs_light"]["pearson"],
        rl["shipped_vs_dark"]["median_abs"], rl["shipped_vs_dark"]["p90_abs"], rl["shipped_vs_dark"]["pearson"]))
    w("")
    w("### Where it misses (by location; residual = target − ⇧E)")
    w("")
    w("| tag | shots | mean target | mean ⇧E | mean residual | median \\|err\\| |\n|---|---|---|---|---|---|")
    for tag, v in res["relative"]["by_tag"].items():
        if v["n"]:
            w("| %s | %d | %+.2f | %+.2f | %+.2f | %.2f |" % (tag, v["n"], v["mean_target"], v["mean_shipped"], v["mean_resid"], v["median_abs_err"]))
    w("")
    w("### Which statistic to match (by location)")
    w("")
    w("| statistic | as ⇧E (full match, ±1) median / p90 | r | k | k × match, ±1, leave-one-out median / p90 | r |\n|---|---|---|---|---|---|")
    for nm, v in res["relative"]["sweep"].items():
        a, b = v["shipped"], v["strength_cv_clamped"]
        w("| %s | %.2f / %.2f | %.2f | %.2f | %.2f / %.2f | %.2f |" % (nm, a["median_abs"], a["p90_abs"], a["pearson"], v["k"], b["median_abs"], b["p90_abs"], b["pearson"]))
    w("")
    w("## Absolute: the middle at 18 % grey")
    w("")
    w("Target mean %+.2f, std %.2f stops." % (ab["target_mean"], ab["target_std"]))
    w("")
    w(HEAD)
    for k, t in (("none", "no change"), ("grey18", "median to 18 % (thumbnail, sRGB curve undone, as Skim)"),
                 ("grey18_cor", "median to 18 % (thumbnail corrected to the TIFF)"), ("grey18_gamma24", "median to 18 % (γ2.4 undone)"),
                 ("grey18_cor_strength_cv", "k × (corrected median to 18 %), leave-one-shoot-out")):
        w(fmt(t, ab[k]))
    w("")
    w("## Does the annotator's middle follow the image?")
    w("")
    w("log2(annotator's pivot, linear) = a + b · log2(image statistic), per shot. b = 1: it moves with the image "
      "(⇧E's full match); b = 0: fixed whatever the image.")
    w("")
    w("| image statistic | b (mid) | r (mid) | b (light) | r (light) | b (dark) | r (dark) |\n|---|---|---|---|---|---|---|")
    for nm, v in f.items():
        w("| %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |" % (nm, v["mid"]["slope"], v["mid"]["pearson"], v["light"]["slope"],
                                                          v["light"]["pearson"], v["dark"]["slope"], v["dark"]["pearson"]))
    w("")
    w("## Noise floor and checks")
    w("")
    w("- Two stills of one video: the annotator kept the same pivots on %.0f%% of shots; where they changed them the middle "
      "moved %.2f stops (median). The image median moves %.2f (p90 %.2f) between the two stills." % (
        100 * ws["annotator_same_pivots"], ws["annotator_mid_abs_diff_median_when_changed"],
        ws["image_median_abs_diff_median"], ws["image_median_abs_diff_p90"]))
    if "thumb_vs_full" in res:
        tv = res["thumb_vs_full"]
        w("- Thumbnails vs the %d full TIFFs on hand (drawn at 320 × 180): thumbnail levels ≈ %.3f · TIFF^%.3f, so ⇧E's "
          "statistic reads %+.2f stops (max |%.2f|) on thumbnails; corrected, %+.2f (max |%.2f|). In ⇧E's frame a near-constant "
          "factor cancels." % (tv["n"], tv["scale"], tv["power"], tv["median_stops"], tv["max_abs_stops"],
                              tv["corrected_median_stops"], tv["corrected_max_abs_stops"]))
    w("- The label histograms (linear Y, 256 bins) match the full TIFF's linear Y on some stills (r 0.99 on choice86400) and "
      "its encoded Y on others (choice86500), so they are a diagnostic row only.")
    w("- Pivots at the tool's defaults on %.1f%% of stills; falloffs at the defaults on all." % (100 * res["pivots"]["at_default"]))
    w("")
    return ("\n".join(L) + "\n").replace("nan", "–")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--pkl", required=True)
    ap.add_argument("--tiffs")
    ap.add_argument("--out", default=os.path.expanduser("~/LuminaEvidence/exposeval"))
    ap.add_argument("--report")
    a = ap.parse_args(argv)
    date = datetime.date.today().isoformat()
    res, rows = run(a.pkl, a.tiffs)
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "results-%s.json" % date), "w") as fh:
        json.dump(res, fh, indent=1)
    with open(os.path.join(a.out, "shots-%s.json" % date), "w") as fh:
        json.dump(rows, fh)
    md = report(res, os.path.basename(a.pkl).split(".")[0] + ".pkl", date)
    if a.report:
        os.makedirs(os.path.dirname(os.path.abspath(a.report)), exist_ok=True)
        with open(a.report, "w") as fh:
            fh.write(md)
    sys.stdout.write(md)


if __name__ == "__main__":
    main()
