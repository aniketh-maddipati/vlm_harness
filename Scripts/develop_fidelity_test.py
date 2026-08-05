#!/usr/bin/env python3
"""Preview/export fidelity comparison scaffold.

On macOS with rendered PNG pairs, computes per-channel MAE, luminance MAE, and SSIM.
Without fixtures, documents the method and exits 0 with a blocked status.

Usage:
  python3 Scripts/develop_fidelity_test.py [preview.png] [export_downsampled.png]
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path


def mae(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / max(len(a), 1)


def luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ssim_simple(xs, ys):
    """Lightweight SSIM on flat luminance samples (not windowed — diagnostic only)."""
    n = len(xs)
    if n == 0:
        return 0.0
    mx = sum(xs) / n
    my = sum(ys) / n
    vx = sum((x - mx) ** 2 for x in xs) / n
    vy = sum((y - my) ** 2 for y in ys) / n
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / n
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    return ((2 * mx * my + c1) * (2 * cov + c2)) / ((mx * mx + my * my + c1) * (vx + vy + c2) + 1e-12)


def load_png_rgb(path: Path):
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        return None
    im = Image.open(path).convert("RGB")
    return list(im.getdata()), im.size


def main() -> int:
    report = {
        "method": {
            "downsample": "CGContext high-quality / Lanczos-equivalent on export → preview long edge",
            "align": "identical oriented extent after shared crop; pixel-grid alignment",
            "metrics": ["per_channel_mae", "luminance_mae", "ssim_luminance", "clip_fraction"],
            "tolerance_policy": "Set from measured evidence on representative ARW; do not invent perfect-match thresholds",
        },
        "status": "blocked",
        "reason": "No preview/export PNG pair provided or Pillow unavailable",
    }

    if len(sys.argv) >= 3:
        preview = Path(sys.argv[1])
        export = Path(sys.argv[2])
        if preview.exists() and export.exists():
            a = load_png_rgb(preview)
            b = load_png_rgb(export)
            if a and b:
                (pa, sa), (pb, sb) = a, b
                if sa != sb:
                    report["status"] = "fail"
                    report["reason"] = f"size mismatch {sa} vs {sb}"
                else:
                    ra, ga, ba = [p[0] for p in pa], [p[1] for p in pa], [p[2] for p in pa]
                    rb, gb, bb = [p[0] for p in pb], [p[1] for p in pb], [p[2] for p in pb]
                    ya = [luminance(r, g, b) for r, g, b in pa]
                    yb = [luminance(r, g, b) for r, g, b in pb]
                    clip_a = sum(1 for r, g, b in pa if r >= 254 or g >= 254 or b >= 254) / len(pa)
                    clip_b = sum(1 for r, g, b in pb if r >= 254 or g >= 254 or b >= 254) / len(pb)
                    report.update(
                        {
                            "status": "measured",
                            "reason": None,
                            "size": list(sa),
                            "mae_r": mae(ra, rb),
                            "mae_g": mae(ga, gb),
                            "mae_b": mae(ba, bb),
                            "mae_y": mae(ya, yb),
                            "ssim_y": ssim_simple(ya, yb),
                            "clip_fraction_preview": clip_a,
                            "clip_fraction_export": clip_b,
                            "note": "Interpret against hardware/fixture notes; thresholds TBD from evidence",
                        }
                    )
            else:
                report["reason"] = "Pillow not installed — cannot decode PNG on this host"

    out = Path("artifacts/develop-lab/fidelity_report.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] in ("measured", "blocked") else 1


if __name__ == "__main__":
    raise SystemExit(main())
