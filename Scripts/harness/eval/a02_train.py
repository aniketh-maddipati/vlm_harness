#!/usr/bin/env python3
"""W6 / A02 — predict the six tone controls from measured image statistics.

Standalone: runs outside the app target, on features.jsonl dumped by
LuminaLogicTests/A02FeatureExtractionTests. The features are the product's own
`ImageStats`, and `a00_*` is the shipping deterministic proposal for the same
frame, so the comparison is against the real incumbent rather than a re-creation.

    ~/.venvs/lumina-a02/bin/python Scripts/harness/eval/a02_train.py FEATURES OUT_DIR

Design constraints, all from the contract:
  * Same six controls, same clamps, same renderer as the incumbent. The only thing
    that changes is how the numbers are chosen.
  * Hold out FUTURE shoots, not random frames. A whole event stays on one side.
  * Deduplicate derivatives before splitting.
  * Compare against a constant-prediction baseline. A model that cannot beat
    predicting the training median is an expensive mean.
  * Resampling unit is the SHOOT. Intervals come from leave-one-event-out over the
    training events, never from per-frame resampling.
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from datetime import date
from pathlib import Path

import numpy as np
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.linear_model import RidgeCV
from sklearn.preprocessing import StandardScaler

CONTROLS = ["exposure", "contrast", "highlights", "shadows", "vibrance", "saturation"]

# ModelAutoDevelop.Band — what a model proposal is allowed to emit.
BAND = {
    "exposure": (-1.0, 1.0), "contrast": (-25.0, 25.0), "highlights": (-60.0, 10.0),
    "shadows": (-10.0, 50.0), "vibrance": (-10.0, 25.0), "saturation": (-15.0, 15.0),
}
# AutoDevelop's own reachable range, for reference. A00 is NOT Band-bounded, so a
# Band-clamped model judged against an unbounded incumbent is being handicapped.
A00_RANGE = {
    "exposure": (-1.0, 0.35), "contrast": (0.0, 0.0), "highlights": (-80.0, 0.0),
    "shadows": (0.0, 20.0), "vibrance": (8.0, 8.0), "saturation": (0.0, 0.0),
}

EVENT_GAP_DAYS = 7
TEST_EVENT_PREFIX = "2026:05:19"   # mehendi — sealed by the D1 ruling, never fitted


def parse_day(s: str):
    try:
        return date(*map(int, s[:10].split(":")))
    except Exception:
        return None


def assign_events(rows):
    days = sorted({parse_day(r["dateTimeOriginal"]) for r in rows if parse_day(r["dateTimeOriginal"])})
    clusters, cur = [], [days[0]]
    for d in days[1:]:
        if (d - cur[-1]).days > EVENT_GAP_DAYS:
            clusters.append(cur); cur = [d]
        else:
            cur.append(d)
    clusters.append(cur)
    day_to_event = {}
    for i, c in enumerate(clusters):
        for d in c:
            day_to_event[d] = i
    for r in rows:
        r["event"] = day_to_event.get(parse_day(r["dateTimeOriginal"]), -1)
    return len(clusters)


def dedup(rows):
    """One row per distinct RAW.

    46 RAWs carry more than one accepted export (virtual copies). Those are genuine
    variation, but a single-output regressor cannot represent two targets for one
    input, and leaving both in would also leak the same photograph across a split.
    Collapsed to the per-control median; the count is reported, not hidden.
    """
    by_raw = defaultdict(list)
    for r in rows:
        by_raw[r["rawSha256"] or r["raw"]].append(r)
    out, collapsed = [], 0
    for _, group in by_raw.items():
        base = dict(group[0])
        if len(group) > 1:
            collapsed += 1
            for c in CONTROLS:
                base["label_" + c] = float(np.median([g["label_" + c] for g in group]))
        out.append(base)
    return out, collapsed


def featurize(rows):
    X = []
    for r in rows:
        bins = np.asarray(r["luminanceBins"], dtype=float)
        total = bins.sum()
        bins = bins / total if total > 0 else bins
        X.append(np.concatenate([
            bins,
            [r["shadowClipFraction"], r["highlightClipFraction"], r["mean"],
             (r["nativeTemperature"] or 6500.0) / 1000.0],
        ]))
    return np.asarray(X)


def clamp(v, lo, hi):
    return np.minimum(np.maximum(v, lo), hi)


def mae(pred, true):
    return float(np.mean(np.abs(np.asarray(pred) - np.asarray(true))))


def fit_predict(Xtr, ytr, Xte, kind):
    scaler = StandardScaler().fit(Xtr)
    a, b = scaler.transform(Xtr), scaler.transform(Xte)
    if kind == "ridge":
        m = RidgeCV(alphas=np.logspace(-3, 4, 40)).fit(a, ytr)
    else:
        m = GradientBoostingRegressor(
            n_estimators=200, max_depth=2, learning_rate=0.05,
            subsample=0.8, random_state=0).fit(a, ytr)
    return m.predict(b)


def evaluate(train, test, label=""):
    Xtr, Xte = featurize(train), featurize(test)
    out = {}
    for c in CONTROLS:
        lo, hi = BAND[c]
        ytr = np.asarray([r["label_" + c] for r in train], dtype=float)
        yte = np.asarray([r["label_" + c] for r in test], dtype=float)
        a00 = np.asarray([r["a00_" + c] for r in test], dtype=float)
        const = np.full_like(yte, float(np.median(ytr)))
        row = {
            "n_train": len(train), "n_test": len(test),
            "a00": mae(a00, yte),
            "constant": mae(clamp(const, lo, hi), yte),
            "constant_unclamped": mae(const, yte),
        }
        for kind in ("ridge", "tree"):
            p = fit_predict(Xtr, ytr, Xte, kind)
            row[kind] = mae(clamp(p, lo, hi), yte)
            row[kind + "_unclamped"] = mae(p, yte)
        out[c] = row
    if label:
        out["_label"] = label
    return out


def main(argv):
    features = Path(argv[1])
    out_dir = Path(argv[2])
    rows = [json.loads(l) for l in features.read_text().splitlines() if l.strip()]
    n_events = assign_events(rows)
    rows, collapsed = dedup(rows)
    assign_events(rows)

    test = [r for r in rows if r["dateTimeOriginal"].startswith(TEST_EVENT_PREFIX)]
    train = [r for r in rows if not r["dateTimeOriginal"].startswith(TEST_EVENT_PREFIX)]
    train_events = sorted({r["event"] for r in train})

    report = {
        "rows_after_dedup": len(rows),
        "rawsWithMultipleExportsCollapsed": collapsed,
        "events_total": n_events,
        "train_rows": len(train), "train_events": len(train_events),
        "test_rows": len(test), "test_event": TEST_EVENT_PREFIX,
        "feature_count": featurize(rows[:1]).shape[1],
        "note_a00_not_band_bounded": A00_RANGE,
    }

    # 1. Sealed holdout: the mehendi event.
    report["sealed_holdout"] = evaluate(train, test, "mehendi 2026-05-19")

    # 2. Leave-one-event-out over the TRAINING events. This is the only place an
    #    interval can come from: the sealed holdout is one event and an interval
    #    over n=1 has no width.
    loeo = {}
    for e in train_events:
        tr = [r for r in train if r["event"] != e]
        te = [r for r in train if r["event"] == e]
        if len(te) < 5 or len(tr) < 30:
            continue
        loeo[str(e)] = evaluate(tr, te, f"held-out event {e} (n={len(te)})")
    report["leave_one_event_out"] = loeo

    # 3. Learning curve. The contract asks for 100/300/1000; 1000 does not exist,
    #    so the top of the curve is the whole training set.
    curve = {}
    rng = np.random.default_rng(0)
    for n in (100, 200, len(train)):
        if n > len(train):
            continue
        idx = rng.choice(len(train), size=n, replace=False)
        curve[str(n)] = evaluate([train[i] for i in idx], test, f"n={n}")
    report["learning_curve"] = curve

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "a02-report.json").write_text(json.dumps(report, indent=2, sort_keys=True))

    # Console summary
    print(f"train {len(train)} rows / {len(train_events)} events   "
          f"test {len(test)} rows (mehendi)   features {report['feature_count']}")
    print(f"virtual-copy RAWs collapsed to median: {collapsed}")
    print()
    h = report["sealed_holdout"]
    print("SEALED HOLDOUT (mehendi) — mean absolute error, lower is better")
    print(f"{'control':<12}{'A00':>8}{'constant':>10}{'ridge':>8}{'tree':>8}   verdict")
    for c in CONTROLS:
        r = h[c]
        best = min(r["ridge"], r["tree"])
        v = []
        v.append("beats A00" if best < r["a00"] else "LOSES to A00")
        v.append("beats const" if best < r["constant"] else "NOT better than mean")
        print(f"{c:<12}{r['a00']:>8.2f}{r['constant']:>10.2f}{r['ridge']:>8.2f}"
              f"{r['tree']:>8.2f}   {'; '.join(v)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
