#!/usr/bin/env python3
"""Stream D — fetch a spread subset of MIT-Adobe FiveK for the Develop eval harness.

FiveK (data.csail.mit.edu/graphics/fivek) is 5,000 RAW photographs, each retouched
by five professionals (experts A–E). It is the public cross-check for the personal
eval set; it carries no slider truth Lumina can read (the catalog is Process Version
2010), so it is compared in pixel space only.

The expert renditions are full-resolution 16-bit ProPhoto TIFFs of ~30 MB each, far
more than the harness needs. Each one is streamed, matched to sRGB and reduced to a
1024 px PNG with `sips`, then the TIFF is deleted — the stored set is ~10 GB for 500
frames × 5 experts instead of ~85 GB. Nothing here is ever committed.

Usage:
    python3 Scripts/harness/eval/fivek_fetch.py DEST [--count 500] [--experts abcde] [--dry-run]

DEST/dng/<name>.dng            the RAW files
DEST/expert_<x>/<stem>.png     the reduced expert renditions
DEST/truth.json                harness truth (one row per frame × expert, no sliders)
DEST/manifest.json             what was fetched and from where

Frames are chosen by an even stride over the sorted file list so the subset spans
the dataset's photographers and cameras rather than the first few hundred names.
Re-running skips anything already on disk.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

BASE = "https://data.csail.mit.edu/graphics/fivek/"
NAME_PATTERN = re.compile(r'dng/([^"/]+\.dng)')
PNG_LONG_EDGE = 1024
SRGB_PROFILE = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
TIMEOUT = 120


def fetch_bytes(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
        return response.read()


def fetch_to(url: str, dest: Path, attempts: int = 3) -> None:
    last: Exception | None = None
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as response, \
                    tempfile.NamedTemporaryFile(dir=dest.parent, delete=False) as tmp:
                while chunk := response.read(1 << 20):
                    tmp.write(chunk)
                temp_path = Path(tmp.name)
            temp_path.replace(dest)
            return
        except Exception as exc:  # noqa: BLE001 — retried, then reported
            last = exc
    raise RuntimeError(f"failed after {attempts} attempts: {url}: {last}")


def file_names() -> list[str]:
    index = fetch_bytes(BASE).decode("utf-8", errors="replace")
    names = sorted(set(NAME_PATTERN.findall(index)))
    if len(names) < 4000:
        raise RuntimeError(f"index page listed only {len(names)} DNG names — layout changed?")
    return names


def spread(names: list[str], count: int) -> list[str]:
    if count >= len(names):
        return names
    stride = len(names) / count
    return [names[int(i * stride)] for i in range(count)]


def reduce_tiff(tiff: Path, png: Path) -> None:
    argv = [
        "sips", "--matchTo", SRGB_PROFILE, "-Z", str(PNG_LONG_EDGE),
        "-s", "format", "png", str(tiff), "--out", str(png),
    ]
    proc = subprocess.run(argv, capture_output=True, text=True, check=False)
    if proc.returncode != 0 or not png.exists():
        raise RuntimeError(f"sips failed on {tiff.name}: {proc.stderr.strip()[:200]}")


def truth_rows(names: list[str], experts: str) -> list[dict]:
    zero = {
        k: 0.0 for k in (
            "exposure", "temperature", "tint", "contrast", "highlights", "shadows", "whites",
            "blacks", "texture", "clarity", "dehaze", "vibrance", "saturation", "sharpness",
            "luminanceNR", "vignette", "cropTop", "cropLeft", "cropAngle",
        )
    }
    rows = []
    for name in names:
        stem = name[: -len(".dng")]
        for expert in experts:
            rows.append({
                **zero,
                "cropBottom": 1.0, "cropRight": 1.0,
                "raw": name,
                "edit": f"expert_{expert}/{stem}.png",
                "expert": expert,
                "virtualCopy": False,
                "whiteBalance": "As Shot",
                "untouched": False,
                "unrenderedMagnitude": 0.0,
                "hasMask": False,
                "hasRetouch": False,
            })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("dest", type=Path)
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--experts", default="abcde")
    parser.add_argument("--dry-run", action="store_true", help="list the selection, fetch nothing")
    args = parser.parse_args()
    experts = "".join(sorted(set(args.experts.lower())))
    if not experts or set(experts) - set("abcde"):
        print("experts must be drawn from a–e", file=sys.stderr)
        return 2

    names = spread(file_names(), args.count)
    print(f"fivek: {len(names)} frames × experts {experts} → {args.dest}")
    if args.dry_run:
        for name in names[:10]:
            print(" ", name)
        print("  …")
        return 0

    dng_dir = args.dest / "dng"
    dng_dir.mkdir(parents=True, exist_ok=True)
    for expert in experts:
        (args.dest / f"expert_{expert}").mkdir(parents=True, exist_ok=True)

    fetched = 0
    failures: list[str] = []
    for index, name in enumerate(names, 1):
        stem = name[: -len(".dng")]
        dng = dng_dir / name
        try:
            if not dng.exists():
                fetch_to(f"{BASE}img/dng/{name}", dng)
                fetched += 1
            for expert in experts:
                png = args.dest / f"expert_{expert}" / f"{stem}.png"
                if png.exists():
                    continue
                tiff = args.dest / f"expert_{expert}" / f"{stem}.tif"
                fetch_to(f"{BASE}img/tiff16_{expert}/{stem}.tif", tiff)
                try:
                    reduce_tiff(tiff, png)
                finally:
                    tiff.unlink(missing_ok=True)
                fetched += 1
        except Exception as exc:  # noqa: BLE001 — one bad file must not end the run
            failures.append(f"{name}: {exc}")
            print(f"[fivek] {index}/{len(names)} {name} FAILED — {exc}", flush=True)
            continue
        print(f"[fivek] {index}/{len(names)} {name}", flush=True)

    (args.dest / "truth.json").write_text(
        json.dumps({
            "schema": 1,
            "source": "mit-adobe-fivek",
            "rendered": [],
            "frames": truth_rows(names, experts),
            "skippedNoRaw": [],
        }, indent=1, sort_keys=True),
        encoding="utf-8",
    )
    (args.dest / "manifest.json").write_text(
        json.dumps({
            "base": BASE, "count": len(names), "experts": experts,
            "pngLongEdge": PNG_LONG_EDGE, "names": names,
        }, indent=1),
        encoding="utf-8",
    )
    print(f"fivek: done, {fetched} files fetched this run, {len(failures)} failures")
    for line in failures:
        print("  " + line)
    # truth.json lists every selected frame; a frame whose files are missing skips in
    # the harness with a loud failure rather than a silent pass. Re-run to fill gaps.
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
