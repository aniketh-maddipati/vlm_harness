#!/usr/bin/env python3
"""Elastic fixture cards — deterministic shoots cut from real frames.

Two kinds of condition live in a Lumina fixture, and only one of them needs a
photograph:

* **Pixel conditions** — clipping, tone, orientation, a real Lightroom sidecar.
  These come from the source frames and are never synthesized, because
  `ImageStats` and `AutoDevelop` read actual pixels.
* **Time conditions** — moments, gaps, light words, bursts, the camera/phone
  mix. Lumina derives every one of these from `DateTimeOriginal` and the file
  extension alone (`ShootChapterArrangement`, `P0SessionModel+Elastic`), so they
  are stamped here rather than shot.

The card plan below is therefore a schedule, not a shoot. It says when each
source frame was taken; the frame supplies what it looks like.

Determinism: sources are consumed in sorted order, every timestamp is derived
from a fixed base date, and nothing is random. Re-running over the same pool
produces byte-identical output apart from the files' own mtimes.

Usage:
    python3 Scripts/harness/fixtures/elastic_cards.py \\
        --raw-dir  /path/to/arws \\
        --phone-dir /path/to/heics \\
        --out      ~/LuminaFixtures

Never write the output inside the repo: a single card runs to hundreds of MB,
and `design/fixture-manifest.md` requires cards be distributed, not committed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# Every card is cut against this day so light words and gaps are reproducible.
BASE_DATE = "2026-05-19"

# Lumina's own rules, mirrored here so the generator can assert what it built.
# Kept in sync by `verify()` failing loudly rather than by hoping.
BURST_GAP_SECONDS = 2
SCENE_GAP_FLOOR = 3 * 60
SCENE_GAP_WALK = 8 * 60
RAW_EXTENSIONS = {"arw", "cr2", "cr3", "nef", "raf", "dng", "orf", "rw2"}

# exiftool tags that identify a person or a place. Stripped from every emitted
# frame: cards are meant to be redistributable, and a source frame may carry
# coordinates even when a sibling from the same camera does not.
SCRUB_TAGS = [
    "-gps:all=",
    "-SerialNumber=",
    "-InternalSerialNumber=",
    "-OwnerName=",
    "-CameraOwnerName=",
    "-Artist=",
    "-Copyright=",
]

# XMP date fields that must follow a restamped frame. `xmp:MetadataDate` is
# deliberately absent — it records when Lightroom wrote the sidecar, which is
# not capture time and must not be rewritten to look like it.
XMP_DATE_FIELDS = (
    "xmp:CreateDate",
    "xmp:ModifyDate",
    "exif:DateTimeOriginal",
    "photoshop:DateCreated",
)


@dataclass(frozen=True)
class Shot:
    """One frame in a moment.

    `pick` names a source basename when the frame's *pixels* matter — a clipping
    case, the cropped sidecar pair. Otherwise it is None and the next unused
    source of `kind` is taken in sorted order.
    """

    offset: int
    kind: str = "raw"
    pick: str | None = None
    exposure_time: str | None = None
    note: str = ""


@dataclass(frozen=True)
class Moment:
    at: str
    note: str
    shots: tuple[Shot, ...]


@dataclass
class Emitted:
    stem: str
    source: Path
    taken: datetime
    kind: str
    sidecar: bool = False
    notes: list[str] = field(default_factory=list)


def burst(start: int, count: int, kind: str = "raw", note: str = "") -> list[Shot]:
    """`count` frames one second apart — inside `burstGap`, so they group."""
    return [
        Shot(offset=start + i, kind=kind, note=note if i == 0 else "")
        for i in range(count)
    ]


# --- The card ---------------------------------------------------------------
#
# Gaps between moments are all well past `sceneGapWalk` (8 min), which always
# splits regardless of the median-derived threshold, so the moment count does
# not depend on how the frames inside a moment happen to be spaced.
#
# Gap heights come from `ElasticLayout.gapHeight`: < 25 min → 14, < 60 min → 40,
# else 64. Labels start at 10 minutes.

ELASTIC_CARD: tuple[Moment, ...] = (
    Moment(
        at="05:40",
        note="before sunrise · first moment, no gap above it",
        shots=(
            Shot(offset=0),
            Shot(offset=22),
        ),
    ),
    Moment(
        at="05:58",
        note="+ 18 min · gapHeight 14 · five-frame burst",
        shots=tuple(
            burst(0, 5, note="five-frame burst — ×5 badge, fold opens it")
            + [Shot(offset=40)]
        ),
    ),
    Moment(
        at="06:35",
        note="+ 37 min · gapHeight 40 · the cropped sidecar pair",
        shots=(
            Shot(offset=0, pick="DSC08324.ARW", note="uncropped half of the A/B"),
            Shot(offset=25, pick="DSC08324-2.ARW", note="cropped + straightened 3.98°"),
            Shot(offset=50),
        ),
    ),
    Moment(
        at="08:15",
        note="+ 1 h 40 min · gapHeight 64 · morning · camera and phone together",
        shots=(
            Shot(offset=0),
            Shot(offset=18),
            Shot(offset=35),
            Shot(offset=52, kind="phone", note="momentMixLine: 3 camera · 2 phone"),
            Shot(offset=70, kind="phone"),
        ),
    ),
    Moment(
        at="12:30",
        note="midday · the frames whose pixels carry the tone conditions",
        shots=(
            Shot(offset=0, kind="phone", pick="IMG_6426.HEIC",
                 note="3.64% highlight clip — tick, recovery, −80 saturation"),
            Shot(offset=30, kind="phone", pick="IMG_6420.HEIC",
                 note="mean 0.551 — AutoDevelop darkens, shadows saturate at +60"),
            Shot(offset=60, pick="DSC08320.ARW",
                 note="10.0% shadow clip — brightening end of the same curve"),
        ),
    ),
    Moment(
        at="16:05",
        note="afternoon · portrait orientation",
        shots=(
            Shot(offset=0, pick="DSC08313.ARW", note="portrait"),
            Shot(offset=20, pick="DSC08314.ARW", note="portrait"),
            Shot(offset=45),
        ),
    ),
    Moment(
        at="18:40",
        note="golden hour · the long exposure",
        shots=(
            Shot(offset=0, exposure_time="2",
                 note="≥1s — shutterLabel's '2s' branch instead of 1/N"),
            Shot(offset=30),
        ),
    ),
    Moment(
        at="20:10",
        note="after sunset · the duplicate pair and a filename with a space",
        shots=(
            Shot(offset=0, kind="phone", pick="IMG_6436.HEIC", note="duplicate A"),
            Shot(offset=0, kind="phone", pick="IMG_6436 2.HEIC",
                 note="duplicate B — byte-identical, same second"),
            Shot(offset=35),
        ),
    ),
)


def run(args: list[str]) -> None:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")


def exiftool_available() -> bool:
    return shutil.which("exiftool") is not None


def discover(directory: Path, extensions: set[str]) -> list[Path]:
    """Sorted so the card is reproducible across machines and filesystems."""
    found = [
        path
        for path in directory.iterdir()
        if path.is_file() and path.suffix.lower().lstrip(".") in extensions
    ]
    return sorted(found, key=lambda p: p.name)


def copy_fast(source: Path, destination: Path) -> None:
    """Clone on APFS where possible; a plain copy everywhere else."""
    try:
        subprocess.run(
            ["cp", "-c", str(source), str(destination)],
            check=True, capture_output=True,
        )
    except subprocess.CalledProcessError:
        shutil.copy2(source, destination)


def restamp_sidecar(text: str, taken: datetime) -> str:
    """Rewrite the capture-time fields, keeping each field's own UTC offset.

    Lumina reads `DateTimeOriginal` from the file itself, but relaunch authority
    reconciles against the sidecar — leaving a stale date here makes a restamped
    frame look externally edited on its first open.
    """
    stamp = taken.strftime("%Y-%m-%dT%H:%M:%S")
    for field_name in XMP_DATE_FIELDS:
        pattern = re.compile(
            rf'({re.escape(field_name)}=")[0-9T:\-]{{19}}([+\-][0-9]{{2}}:[0-9]{{2}}|Z)?(")'
        )
        text = pattern.sub(rf"\g<1>{stamp}\g<2>\g<3>", text)
    return text


def emit(card: tuple[Moment, ...], raw_pool: list[Path], phone_pool: list[Path],
         out_dir: Path) -> list[Emitted]:
    pools = {"raw": list(raw_pool), "phone": list(phone_pool)}
    by_name = {p.name: p for p in raw_pool + phone_pool}
    cursors = {"raw": 0, "phone": 0}
    emitted: list[Emitted] = []
    sequence = 1

    for moment in card:
        start = datetime.strptime(f"{BASE_DATE} {moment.at}", "%Y-%m-%d %H:%M")
        for shot in moment.shots:
            if shot.pick:
                source = by_name.get(shot.pick)
                if source is None:
                    raise SystemExit(
                        f"card needs {shot.pick!r}, which is not in the source pool"
                    )
            else:
                pool = pools[shot.kind]
                if not pool:
                    raise SystemExit(f"no {shot.kind} sources available")
                source = pool[cursors[shot.kind] % len(pool)]
                cursors[shot.kind] += 1

            taken = start + timedelta(seconds=shot.offset)
            stem = f"LUM{sequence:04d}"
            sequence += 1
            destination = out_dir / f"{stem}{source.suffix.upper()}"
            copy_fast(source, destination)

            tags = list(SCRUB_TAGS)
            tags += [
                f"-DateTimeOriginal={taken:%Y:%m:%d %H:%M:%S}",
                f"-CreateDate={taken:%Y:%m:%d %H:%M:%S}",
                f"-ModifyDate={taken:%Y:%m:%d %H:%M:%S}",
            ]
            if shot.exposure_time:
                tags.append(f"-ExposureTime={shot.exposure_time}")
            run(["exiftool", *tags, "-overwrite_original", "-q", "-q", str(destination)])

            record = Emitted(stem=stem, source=source, taken=taken, kind=shot.kind)
            if shot.note:
                record.notes.append(shot.note)

            sidecar_source = source.with_suffix(".xmp")
            if sidecar_source.is_file():
                sidecar_text = restamp_sidecar(
                    sidecar_source.read_text(encoding="utf-8"), taken
                )
                (out_dir / f"{stem}.xmp").write_text(sidecar_text, encoding="utf-8")
                record.sidecar = True

            emitted.append(record)

    return emitted


def light_word(hour: int) -> str:
    if hour < 7:
        return "before sunrise"
    if hour < 10:
        return "morning"
    if hour < 15:
        return "midday"
    if hour < 18:
        return "afternoon"
    if hour < 20:
        return "golden hour"
    return "after sunset"


def gap_height(seconds: float) -> int:
    if seconds >= 60 * 60:
        return 64
    if seconds >= 25 * 60:
        return 40
    return 14


def gap_label(seconds: float) -> str | None:
    if seconds < 10 * 60:
        return None
    total = round(seconds / 60)
    hours, minutes = divmod(total, 60)
    if hours == 0:
        return f"+ {minutes} min"
    if minutes == 0:
        return f"+ {hours} h"
    return f"+ {hours} h {minutes} min"


def verify(emitted: list[Emitted]) -> dict:
    """Re-derive what Lumina will see, so the card proves itself rather than
    trusting that the plan and the code still agree."""
    frames = sorted(emitted, key=lambda e: e.taken)
    gaps = [
        (frames[i].taken - frames[i - 1].taken).total_seconds()
        for i in range(1, len(frames))
    ]
    median = sorted(gaps)[len(gaps) // 2] if gaps else 0
    threshold = min(min(max(median * 3, SCENE_GAP_FLOOR), 15 * 60), SCENE_GAP_WALK)

    # Splitting reads frame-to-frame gaps (`ShootChapterArrangement.arrange`)...
    moments: list[list[Emitted]] = [[frames[0]]] if frames else []
    for index in range(1, len(frames)):
        if gaps[index - 1] >= threshold:
            moments.append([frames[index]])
        else:
            moments[-1].append(frames[index])

    # ...but the gap a reader *sees* is start-to-start between chapters
    # (`P0SessionModel.gapInterval(after:)`, and `startedAt` is the chapter's
    # earliest frame). Measuring the wrong one here would report labels the
    # table never shows.
    starts = [min(f.taken for f in moment) for moment in moments]
    boundaries = [
        (starts[i] - starts[i - 1]).total_seconds() for i in range(1, len(starts))
    ]

    bursts: list[int] = []
    run_length = 1
    for index in range(1, len(frames)):
        if gaps[index - 1] <= BURST_GAP_SECONDS:
            run_length += 1
        else:
            bursts.append(run_length)
            run_length = 1
    bursts.append(run_length)

    summary = {
        "frames": len(frames),
        "sceneThresholdSeconds": threshold,
        "moments": len(moments),
        "lightWords": sorted({light_word(m[0].taken.hour) for m in moments}),
        "gapHeights": sorted({gap_height(g) for g in boundaries}),
        "gapLabels": [gap_label(g) for g in boundaries],
        "largestBurst": max(bursts),
        "phoneFrames": sum(1 for f in frames if f.kind == "phone"),
        "sidecars": sum(1 for f in frames if f.sidecar),
        "mixedMoments": sum(
            1 for m in moments if {f.kind for f in m} == {"raw", "phone"}
        ),
    }

    expected = {
        "moments": len(ELASTIC_CARD),
        "lightWords": [
            "after sunset", "afternoon", "before sunrise",
            "golden hour", "midday", "morning",
        ],
        "gapHeights": [14, 40, 64],
    }
    problems = []
    if summary["moments"] != expected["moments"]:
        problems.append(
            f"moments: built {summary['moments']}, planned {expected['moments']}"
        )
    if summary["lightWords"] != expected["lightWords"]:
        missing = set(expected["lightWords"]) - set(summary["lightWords"])
        problems.append(f"light words missing: {sorted(missing)}")
    if summary["gapHeights"] != expected["gapHeights"]:
        problems.append(f"gap heights: {summary['gapHeights']}, want [14, 40, 64]")
    if summary["largestBurst"] < 5:
        problems.append(f"largest burst is {summary['largestBurst']}, want ≥ 5")
    if summary["mixedMoments"] < 1:
        problems.append("no moment mixes camera and phone frames")

    summary["problems"] = problems
    return summary


def write_checksums(frames_dir: Path, bundle_dir: Path) -> None:
    lines = []
    for path in sorted(frames_dir.iterdir(), key=lambda p: p.name):
        if not path.is_file():
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  frames/{path.name}")
    (bundle_dir / "checksums.sha256").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--phone-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--name", default="card-elastic-v4")
    parser.add_argument("--force", action="store_true",
                        help="replace an existing card of the same name")
    args = parser.parse_args()

    if not exiftool_available():
        print("exiftool not found — brew install exiftool", file=sys.stderr)
        return 2

    raw_pool = discover(args.raw_dir, RAW_EXTENSIONS)
    phone_pool = discover(args.phone_dir, {"heic", "heif", "hif", "jpg", "jpeg"})
    if not raw_pool:
        print(f"no RAW frames under {args.raw_dir}", file=sys.stderr)
        return 2
    if not phone_pool:
        print(f"no phone frames under {args.phone_dir}", file=sys.stderr)
        return 2

    bundle_dir = args.out.expanduser() / args.name
    # Frames live one level down so `card.json` and `checksums.sha256` are not
    # themselves offered to ingest — Lumina counts any non-image in the opened
    # folder as `unsupported`, and a card should not report faults it invented.
    out_dir = bundle_dir / "frames"
    if bundle_dir.exists():
        if not args.force:
            print(f"{bundle_dir} exists — pass --force to replace it", file=sys.stderr)
            return 2
        shutil.rmtree(bundle_dir)
    out_dir.mkdir(parents=True)

    try:
        bundle_dir.resolve().relative_to(ROOT)
    except ValueError:
        pass
    else:
        print(
            f"refusing to write a card inside the repo ({bundle_dir}) — cards are "
            "distributed, not committed (design/fixture-manifest.md §1)",
            file=sys.stderr,
        )
        return 2

    emitted = emit(ELASTIC_CARD, raw_pool, phone_pool, out_dir)
    summary = verify(emitted)
    write_checksums(out_dir, bundle_dir)

    card = {
        "name": args.name,
        "baseDate": BASE_DATE,
        "sourceRaw": str(args.raw_dir),
        "sourcePhone": str(args.phone_dir),
        "summary": summary,
        "frames": [
            {
                "stem": e.stem,
                "from": e.source.name,
                "takenAt": e.taken.isoformat(),
                "kind": e.kind,
                "sidecar": e.sidecar,
                "notes": e.notes,
            }
            for e in sorted(emitted, key=lambda e: e.taken)
        ],
    }
    (bundle_dir / "card.json").write_text(
        json.dumps(card, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )

    print(f"{args.name}: {summary['frames']} frames → {out_dir}")
    print(f"  open with    --p0-open {out_dir}")
    print(f"  moments      {summary['moments']}  (threshold {summary['sceneThresholdSeconds']:.0f}s)")
    print(f"  light words  {', '.join(summary['lightWords'])}")
    print(f"  gap heights  {summary['gapHeights']}")
    print(f"  gap labels   {', '.join(l for l in summary['gapLabels'] if l)}")
    print(f"  largest burst {summary['largestBurst']}")
    print(f"  phone frames {summary['phoneFrames']}  mixed moments {summary['mixedMoments']}")
    print(f"  sidecars     {summary['sidecars']}")

    if summary["problems"]:
        print("\nthe card does not match its plan:", file=sys.stderr)
        for problem in summary["problems"]:
            print(f"  {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
