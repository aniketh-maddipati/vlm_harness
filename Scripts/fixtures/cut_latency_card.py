#!/usr/bin/env python3
"""Cut the `card-clean-*` latency fixtures from a seed set of real camera RAW.

E1 Gate 2. E2's Gate 1 measures a 60 s glide and needs a ~2000-frame card; the
`card-clean-500` row in `design/fixture-manifest.md` has been named-but-absent
since the v6 seal (render-hazard inventory, 2026-08-15, "Absent as files").

Rules this script obeys:

  * Seeds must be REAL camera RAW. Decode cost is the load being measured, so a
    synthesized flat JPEG is not a latency fixture. `--seed` is validated.
  * Single volume, stable unique names, no videos.
  * Replication is allowed but never silent: the manifest row records seed body,
    seed count and replication factor, and this script writes them into
    `fixture.json` next to the cut.
  * Every cut file is checksummed into `checksums.sha256` so drift is detectable.

Usage:
    python3 Scripts/fixtures/cut_latency_card.py \
        --seed /Volumes/Untitled/DCIM/100MSDCF \
        --out  ~/Pictures/lumina-fixtures \
        --card card-clean-500

Nothing is written to the seed directory. It is opened read-only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

RAW_EXTENSIONS = {".arw", ".cr3", ".nef", ".raf", ".dng", ".heic"}

# Frame count and replication policy per card. Keep in step with
# `design/fixture-manifest.md` §2.
CARDS = {
    "card-clean-500": {"frames": 500, "distinct_seeds": 500},
    "card-clean-2000": {"frames": 2000, "distinct_seeds": 1000},
}

MIN_REAL_RAW_BYTES = 1_000_000  # a 4-byte ASCII stub is not a camera RAW


def volume_free_bytes(path: Path) -> int:
    stat = os.statvfs(path)
    return stat.f_bavail * stat.f_frsize


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(chunk), b""):
            digest.update(block)
    return digest.hexdigest()


def probe_body(sample: Path) -> tuple[str, str]:
    """Return (make, model) via exiftool, or ("unknown", "unknown")."""
    try:
        out = subprocess.run(
            ["exiftool", "-s3", "-Make", "-Model", str(sample)],
            capture_output=True, text=True, timeout=30, check=False,
        ).stdout.splitlines()
        if len(out) >= 2:
            return out[0].strip(), out[1].strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return "unknown", "unknown"


def collect_seeds(seed_dir: Path) -> list[Path]:
    seeds = sorted(
        p for p in seed_dir.iterdir()
        if p.is_file()
        and p.suffix.lower() in RAW_EXTENSIONS
        and not p.name.startswith("._")  # AppleDouble resource forks, not photographs
    )
    if not seeds:
        sys.exit(
            f"STOP: no real RAW found in {seed_dir}.\n"
            f"       Looked for: {', '.join(sorted(RAW_EXTENSIONS))}.\n"
            "       A latency fixture cut from synthesized JPEGs would not exercise\n"
            "       decode cost, which is the load being measured. Refusing."
        )
    stubs = [p for p in seeds[:50] if p.stat().st_size < MIN_REAL_RAW_BYTES]
    if stubs:
        sys.exit(
            f"STOP: {len(stubs)} seed file(s) are under {MIN_REAL_RAW_BYTES} bytes "
            f"(e.g. {stubs[0].name}, {stubs[0].stat().st_size} B).\n"
            "       These are stubs, not camera RAW. Refusing to cut a latency fixture."
        )
    return seeds


def plan(seeds: list[Path], frames: int, distinct: int) -> list[Path]:
    """Choose the smallest `distinct` seeds, then repeat them to reach `frames`.

    Smallest-first keeps the cut inside a sane disk budget without touching decode
    realism: every file is still a whole, real RAW from the seed body.
    """
    by_size = sorted(seeds, key=lambda p: p.stat().st_size)
    pool = by_size[: min(distinct, len(by_size))]
    pool = sorted(pool)  # restore capture order for stable, sequential names
    return [pool[i % len(pool)] for i in range(frames)]


def cut(card: str, seed_dir: Path, out_root: Path, clone: bool, force: bool) -> None:
    spec = CARDS[card]
    frames, distinct = spec["frames"], spec["distinct_seeds"]

    seeds = collect_seeds(seed_dir)
    make, model = probe_body(seeds[0])

    dest = out_root / card
    if dest.exists():
        if not force:
            sys.exit(f"STOP: {dest} already exists. Pass --force to re-cut.")
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    chosen = plan(seeds, frames, distinct)
    actual_distinct = len({p.resolve() for p in chosen})
    replication = round(frames / actual_distinct, 4)

    free_before = volume_free_bytes(dest)
    ext = chosen[0].suffix.upper()
    manifest_rows: list[tuple[str, str, str]] = []
    total_bytes = 0

    # First occurrence of a seed is always a real copy. Later occurrences may be APFS
    # clones, but only cloned FROM the copy already inside `dest` — `cp -c` across
    # volumes silently degrades to a full copy, which would defeat the disk saving
    # and quietly make `clone_backed` a lie.
    first_copy: dict[Path, Path] = {}
    clones_made = 0

    for index, src in enumerate(chosen, start=1):
        name = f"LUM{index:05d}{ext}"
        target = dest / name
        key = src.resolve()
        origin = first_copy.get(key)
        if origin is None:
            shutil.copy2(src, target)
            first_copy[key] = target
        elif clone:
            subprocess.run(["cp", "-c", str(origin), str(target)], check=True)
            clones_made += 1
        else:
            shutil.copy2(origin, target)
        total_bytes += target.stat().st_size
        manifest_rows.append((name, sha256(target), src.name))
        if index % 100 == 0 or index == frames:
            print(f"  {card}: {index}/{frames}", flush=True)

    checksum_path = dest / "checksums.sha256"
    with checksum_path.open("w", encoding="utf-8") as handle:
        for name, digest, _ in manifest_rows:
            handle.write(f"{digest}  {name}\n")

    meta = {
        "fixture_id": card,
        "frames": frames,
        "seed_dir_basename": seed_dir.name,
        "seed_body_make": make,
        "seed_body_model": model,
        "seed_count_distinct": actual_distinct,
        "replication_factor": replication,
        "clone_backed": clones_made > 0,
        "clones_made": clones_made,
        "extension": ext,
        "logical_bytes": total_bytes,
        "physical_bytes_estimate": max(0, free_before - volume_free_bytes(dest)),
        "checksums": checksum_path.name,
        "content_variety": (
            "full — every frame distinct" if replication == 1
            else f"partial — {actual_distinct} distinct frames repeated {replication}x"
        ),
        "decode_cost": "preserved — every file is a whole real RAW from the seed body",
        "cold_io_caveat": (
            "understated — replicated frames share physical blocks (APFS clone)"
            if clones_made else
            "faithful — every frame is physically distinct bytes"
        ),
    }
    (dest / "fixture.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")

    physical = max(0, free_before - volume_free_bytes(dest))
    print(f"\ncut {card}: {frames} frames")
    print(f"  logical size:  {total_bytes / 2**30:.2f} GiB (sum of file sizes)")
    print(f"  physical cost: {physical / 2**30:.2f} GiB (volume free-space delta)")
    print(f"  body: {make} {model}")
    print(f"  distinct seeds: {actual_distinct}  replication: {replication}x  clone: {clone}")
    print(f"  checksums: {checksum_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seed", required=True, type=Path,
                        help="directory of real camera RAW (read-only)")
    parser.add_argument("--out", required=True, type=Path,
                        help="fixture root; the card is cut into <out>/<card>")
    parser.add_argument("--card", required=True, choices=sorted(CARDS),
                        help="which card to cut")
    parser.add_argument("--clone", action="store_true",
                        help="use APFS clones for replicated frames (saves disk, "
                             "understates cold I/O — declared in fixture.json)")
    parser.add_argument("--force", action="store_true", help="re-cut over an existing card")
    args = parser.parse_args()

    seed_dir = args.seed.expanduser().resolve()
    out_root = args.out.expanduser().resolve()
    if not seed_dir.is_dir():
        sys.exit(f"STOP: seed directory not found: {seed_dir}")
    out_root.mkdir(parents=True, exist_ok=True)

    cut(args.card, seed_dir, out_root, clone=args.clone, force=args.force)


if __name__ == "__main__":
    main()
