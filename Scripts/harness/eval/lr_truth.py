#!/usr/bin/env python3
"""Stream D — extract the photographer's own Lightroom develop settings as ground truth.

Reads the embedded XMP (`crs:` namespace, Process Version 15.x, the 2012 tone
fields) from a folder of Lightroom exports with exiftool and writes one JSON
file of numbers. No pixels are read, copied or written. Filenames in the
output are the camera's frame numbers (DSC0xxxx), nothing else.

Usage:
    python3 Scripts/harness/eval/lr_truth.py EDIT_DIR RAW_DIR OUT_JSON

EDIT_DIR  folder of Lightroom JPEG exports carrying their develop settings
RAW_DIR   folder of the matching RAW files (a frame is kept only when its RAW exists)
OUT_JSON  where to write truth.json (keep it outside the repo — it is per-photographer)

Every frame carries every field Lumina's `EditRecipe` names, plus the ones the
engine does not render (whites, blacks, texture, clarity, dehaze, vignette) so the
harness can report how much of an edit lives outside the rendered subset.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

RAW_SUFFIXES = {".arw", ".cr2", ".cr3", ".nef", ".raf", ".dng"}

# crs field → (truth key, default when absent)
FIELDS: tuple[tuple[str, str, float], ...] = (
    ("Exposure2012", "exposure", 0.0),
    ("ColorTemperature", "temperature", 0.0),
    ("Tint", "tint", 0.0),
    ("Contrast2012", "contrast", 0.0),
    ("Highlights2012", "highlights", 0.0),
    ("Shadows2012", "shadows", 0.0),
    ("Whites2012", "whites", 0.0),
    ("Blacks2012", "blacks", 0.0),
    ("Texture", "texture", 0.0),
    ("Clarity2012", "clarity", 0.0),
    ("Dehaze", "dehaze", 0.0),
    ("Vibrance", "vibrance", 0.0),
    ("Saturation", "saturation", 0.0),
    ("Sharpness", "sharpness", 0.0),
    ("LuminanceSmoothing", "luminanceNR", 0.0),
    ("PostCropVignetteAmount", "vignette", 0.0),
    ("CropTop", "cropTop", 0.0),
    ("CropLeft", "cropLeft", 0.0),
    ("CropBottom", "cropBottom", 1.0),
    ("CropRight", "cropRight", 1.0),
    ("CropAngle", "cropAngle", 0.0),
)

# Fields that Lumina's render graph applies. Everything else in FIELDS is measured
# only so the residual can be attributed (docs/DEVELOP_ENGINE.md, control matrix).
RENDERED = ("exposure", "temperature", "tint", "contrast", "highlights", "shadows",
            "vibrance", "saturation", "sharpness", "luminanceNR")
TONE_FIELDS = ("exposure", "contrast", "highlights", "shadows", "whites", "blacks",
               "texture", "clarity", "dehaze", "vibrance", "saturation")


def _num(value: object, default: float) -> float:
    if value is None:
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _exiftool(edit_dir: Path) -> list[dict]:
    argv = ["exiftool", "-j", "-n", "-XMP-crs:all", "-ImageSize", "-Orientation", str(edit_dir)]
    proc = subprocess.run(argv, capture_output=True, text=True, check=False)
    if proc.returncode not in (0, 1) or not proc.stdout.strip():
        raise SystemExit(f"exiftool failed ({proc.returncode}): {proc.stderr.strip()[:200]}")
    return json.loads(proc.stdout)


def _raw_index(raw_dir: Path) -> dict[str, str]:
    index: dict[str, str] = {}
    for path in sorted(raw_dir.iterdir()):
        if path.suffix.lower() in RAW_SUFFIXES and path.stat().st_size > 1_000_000:
            index[path.stem] = path.name
    return index


def build_truth(edit_dir: Path, raw_dir: Path) -> dict:
    raws = _raw_index(raw_dir)
    frames: list[dict] = []
    skipped: list[str] = []
    for item in _exiftool(edit_dir):
        jpg = Path(item["SourceFile"]).name
        stem = Path(jpg).stem
        base = stem.split("-")[0]  # "DSC08191-2" is a Lightroom virtual copy of DSC08191
        raw_name = raws.get(base)
        if raw_name is None:
            skipped.append(jpg)
            continue
        frame: dict = {
            "raw": raw_name,
            "edit": jpg,
            "virtualCopy": stem != base,
            "whiteBalance": item.get("WhiteBalance", "As Shot"),
            "processVersion": _num(item.get("ProcessVersion"), 0.0),
            "hasMask": any(k.startswith("MaskGroupBasedCorr") for k in item),
            "hasRetouch": any(k.startswith("RetouchArea") for k in item),
            "hasLensProfile": _num(item.get("LensProfileEnable"), 0.0) == 1.0,
            "cameraProfile": item.get("CameraProfile", ""),
            "toneCurve": item.get("ToneCurveName2012", ""),
        }
        for crs, key, default in FIELDS:
            frame[key] = _num(item.get(crs), default)
        frame["untouched"] = (
            all(frame[k] == 0.0 for k in TONE_FIELDS)
            and frame["whiteBalance"] == "As Shot"
            and frame["vignette"] == 0.0
        )
        frame["unrenderedMagnitude"] = sum(
            abs(frame[k]) for k in ("whites", "blacks", "texture", "clarity", "dehaze")
        ) + abs(frame["vignette"])
        frames.append(frame)
    frames.sort(key=lambda f: (f["raw"], f["edit"]))
    return {
        "schema": 1,
        "source": "lightroom-embedded-xmp",
        "rendered": list(RENDERED),
        "frames": frames,
        "skippedNoRaw": skipped,
    }


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    edit_dir, raw_dir, out = Path(argv[1]), Path(argv[2]), Path(argv[3])
    if not edit_dir.is_dir() or not raw_dir.is_dir():
        print(f"not a directory: {edit_dir} or {raw_dir}", file=sys.stderr)
        return 2
    truth = build_truth(edit_dir, raw_dir)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(truth, indent=1, sort_keys=True), encoding="utf-8")
    frames = truth["frames"]
    untouched = sum(1 for f in frames if f["untouched"])
    print(
        f"truth: {len(frames)} frames ({untouched} untouched, "
        f"{sum(1 for f in frames if f['virtualCopy'])} virtual copies, "
        f"{len(truth['skippedNoRaw'])} exports without a RAW skipped) → {out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
