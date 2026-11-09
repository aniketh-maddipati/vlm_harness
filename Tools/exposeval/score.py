"""Scores of a predicted exposure (stops) against a target (stops), numpy only."""

import numpy as np


def _ranks(x):
    x = np.asarray(x, dtype=np.float64)
    order = np.argsort(x, kind="mergesort")
    r = np.empty(len(x))
    r[order] = np.arange(len(x), dtype=np.float64)
    # ties share their mean rank
    vals, inv, counts = np.unique(x, return_inverse=True, return_counts=True)
    sums = np.bincount(inv, weights=r)
    return (sums / counts)[inv]


def pearson(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    if len(a) < 2 or a.std() == 0 or b.std() == 0:
        return float("nan")
    return float(np.corrcoef(a, b)[0, 1])


def spearman(a, b):
    return pearson(_ranks(a), _ranks(b))


def metrics(pred, target, sign_min=1.0 / 3.0):
    """|error| median / p90, bias (mean of pred − target), share within a third of a stop, correlations,
    and sign agreement on the shots whose target moves at least `sign_min` stops (a prediction of 0 there
    counts as a miss)."""
    p, t = np.asarray(pred, float), np.asarray(target, float)
    e = p - t
    a = np.abs(e)
    big = np.abs(t) >= sign_min
    sign = float(np.mean(np.sign(p[big]) == np.sign(t[big]))) if big.any() else float("nan")
    return {
        "n": int(len(t)),
        "median_abs": float(np.median(a)) if len(a) else float("nan"),
        "p90_abs": float(np.percentile(a, 90)) if len(a) else float("nan"),
        "bias": float(np.mean(e)) if len(e) else float("nan"),
        "within_third": float(np.mean(a <= 1.0 / 3.0)) if len(a) else float("nan"),
        "pearson": pearson(p, t),
        "spearman": spearman(p, t),
        "sign": sign,
        "sign_n": int(big.sum()),
    }


def fit_slope(x, y):
    """Least squares y ≈ k·x through the origin."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    d = float(np.dot(x, x))
    return float(np.dot(x, y) / d) if d else 0.0


def fit_line(x, y):
    """Least squares y ≈ a + b·x → (a, b)."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    b, a = np.polyfit(x, y, 1)
    return float(a), float(b)


def cv_strength(groups, x, y):
    """Leave-one-group-out: k fitted on the other groups, applied to this one. Returns predictions and ks."""
    groups = np.asarray(groups)
    x, y = np.asarray(x, float), np.asarray(y, float)
    pred = np.zeros_like(y)
    ks = {}
    for g in np.unique(groups):
        m = groups == g
        k = fit_slope(x[~m], y[~m])
        ks[str(g)] = k
        pred[m] = k * x[m]
    return pred, ks
