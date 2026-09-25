#!/usr/bin/env python3
"""T1 — build the training label set by matching exported JPEGs back to their source RAWs.

Scales `lr_truth.py` from one folder to a whole library. The develop settings come
from the exported JPEG's embedded XMP (`crs:`), parsed with `lr_truth`'s own FIELDS
table and `untouched` rule — this script does not reimplement that parsing, it
imports it.

Read-only. Never writes to the photograph volume, never copies pixels. Output is
paths, hashes and numbers.

Usage:
    python3 Scripts/harness/eval/export_labels.py ROOT OUT_DIR [--limit N] [--no-hash]

MATCHING, in priority order. Every row records which rule fired.

  rawfilename   `XMP-crs:RawFileName` names the source RAW outright, and exactly one
                RAW on the volume has that basename. Lightroom writes this itself;
                it is the photographer's own record of the pair, not an inference.
  rawfilename+dto
                `RawFileName` matched several RAWs (Sony frame numbers recur across
                cards), and `DateTimeOriginal` to the second picks exactly one.
  stem          Contract rule 1 — identical stem, same shoot folder, unique.
  dto           Contract rule 2 — `DateTimeOriginal` equal to the second, unique
                across the whole volume.

  Anything with more than one surviving candidate is recorded as ambiguous and
  emitted nowhere. A wrong pair is a poisoned label; an unmatched export costs
  only coverage.

NOTE ON RULE 2. The contract specifies "DateTimeOriginal equality plus body serial".
Lightroom strips MakerNotes on export, so no exported JPEG on this volume carries a
serial — the field the rule needs does not exist on the files the rule applies to.
Uniqueness across the volume is substituted and the substitution is reported; see
coverage.json["rule2_serial_available"].
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lr_truth  # noqa: E402  — reused, never reimplemented

RAW_SUFFIXES = lr_truth.RAW_SUFFIXES
JPEG_SUFFIXES = {".jpg", ".jpeg"}

# Trees that are not photographer edits. LuminaExperiments and the perf cards are
# this project's own renders and fixtures; feeding them back in would train the
# model on its own output.
EXCLUDED_TREES = {"LuminaExperiments", "Lumina-performance-2026-09-23", "lumina_testing_raws"}


def walk(root: Path, suffixes: set[str]) -> list[Path]:
    """Photographs only.

    `._NAME.jpg` is an AppleDouble resource-fork stub, written by macOS when copying
    to exFAT. It is not a photograph and carries no image metadata. T7 holds 1,883 of
    them; counting them as files inflates the library inventory by about a third and
    makes the XMP-coverage denominator meaningless.
    """
    return sorted(
        p for p in root.rglob("*")
        if p.suffix.lower() in suffixes and not p.name.startswith("._") and p.is_file()
    )


def tree_of(path: Path, root: Path) -> str:
    rel = path.relative_to(root).parts
    return rel[0] if len(rel) > 1 else "."


def exiftool(paths: list[Path], tags: list[str], chunk: int = 400) -> list[dict]:
    """Bulk metadata read. Read-only: no tag is ever assigned."""
    out: list[dict] = []
    for i in range(0, len(paths), chunk):
        batch = paths[i:i + chunk]
        argv = ["exiftool", "-j", "-n", "-m", *tags, *[str(p) for p in batch]]
        proc = subprocess.run(argv, capture_output=True, text=True, check=False)
        if proc.returncode not in (0, 1) or not proc.stdout.strip():
            print(f"  exiftool chunk {i} failed ({proc.returncode}): {proc.stderr.strip()[:160]}",
                  file=sys.stderr)
            continue
        out.extend(json.loads(proc.stdout))
        print(f"  ...{min(i + chunk, len(paths))}/{len(paths)}", file=sys.stderr)
    return out


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def build(root: Path, out_dir: Path, limit: int | None, do_hash: bool) -> dict:
    print(f"scanning {root} ...", file=sys.stderr)
    stub_count = sum(1 for p in root.rglob("._*")
                     if p.suffix.lower() in (RAW_SUFFIXES | JPEG_SUFFIXES))
    raws = [p for p in walk(root, RAW_SUFFIXES) if tree_of(p, root) not in EXCLUDED_TREES]
    jpegs_all = walk(root, JPEG_SUFFIXES)
    jpegs = [p for p in jpegs_all if tree_of(p, root) not in EXCLUDED_TREES]
    excluded_jpegs = len(jpegs_all) - len(jpegs)
    if limit:
        jpegs = jpegs[:limit]
    print(f"  {len(raws)} RAW, {len(jpegs)} JPEG ({excluded_jpegs} excluded by tree)", file=sys.stderr)

    print("reading RAW metadata ...", file=sys.stderr)
    raw_meta = exiftool(raws, ["-SourceFile", "-DateTimeOriginal", "-Model", "-InternalSerialNumber"])
    print("reading JPEG metadata ...", file=sys.stderr)
    jpeg_meta = exiftool(jpegs, [
        "-SourceFile", "-DateTimeOriginal", "-Model", "-ImageSize", "-Orientation",
        "-XMP-crs:all", "-XMP-xmpMM:OriginalDocumentID", "-XMP-xmpMM:DocumentID",
    ])

    # RAW indices
    by_basename: dict[str, list[dict]] = defaultdict(list)
    by_stem_tree: dict[tuple[str, str], list[dict]] = defaultdict(list)
    by_dto: dict[str, list[dict]] = defaultdict(list)
    raw_serials = 0
    for item in raw_meta:
        p = Path(item["SourceFile"])
        rec = {"path": str(p), "stem": p.stem, "tree": tree_of(p, root),
               "dto": item.get("DateTimeOriginal"), "serial": item.get("InternalSerialNumber")}
        by_basename[p.name.lower()].append(rec)
        by_stem_tree[(rec["tree"], p.stem.lower())].append(rec)
        if rec["dto"]:
            by_dto[str(rec["dto"])].append(rec)
        if rec["serial"]:
            raw_serials += 1

    rows: list[dict] = []
    identity_rows: list[dict] = []
    rule_counts: Counter = Counter()
    ambiguous: list[dict] = []
    unmatched: list[dict] = []
    no_xmp = 0
    identity = 0
    jpeg_serials = 0
    vc_groups: dict[str, set[str]] = defaultdict(set)

    for item in jpeg_meta:
        jpath = Path(item["SourceFile"])
        dto = item.get("DateTimeOriginal")
        if item.get("SerialNumber") or item.get("InternalSerialNumber"):
            jpeg_serials += 1

        # Falsifier 1: no crs XMP at all — invisible to this method. An in-camera
        # JPEG off the card looks exactly like this, and is not an edit.
        has_crs = any(k in item for k, _, _ in
                      ((c, 0, 0) for c, _k, _d in lr_truth.FIELDS)) or "ProcessVersion" in item
        if not has_crs:
            no_xmp += 1
            continue

        raw_file_name = item.get("RawFileName")
        cands: list[dict] = []
        rule = None
        if raw_file_name:
            cands = by_basename.get(str(raw_file_name).lower(), [])
            rule = "rawfilename"
            if len(cands) > 1 and dto:
                narrowed = [c for c in cands if c["dto"] == dto]
                if len(narrowed) == 1:
                    cands, rule = narrowed, "rawfilename+dto"
        if len(cands) != 1:
            stem_c = by_stem_tree.get((tree_of(jpath, root), jpath.stem.lower()), [])
            if len(stem_c) == 1:
                cands, rule = stem_c, "stem"
        if len(cands) != 1 and dto:
            dto_c = by_dto.get(str(dto), [])
            if len(dto_c) == 1:
                cands, rule = dto_c, "dto"

        if len(cands) != 1:
            entry = {"jpeg": str(jpath), "rawFileName": raw_file_name,
                     "dto": dto, "candidates": len(cands)}
            (ambiguous if len(cands) > 1 else unmatched).append(entry)
            continue

        raw = cands[0]
        frame: dict = {
            "raw": raw["path"],
            "jpeg": str(jpath),
            "match_rule": rule,
            "tree": tree_of(jpath, root),
            "rawFileName": raw_file_name,
            "dateTimeOriginal": dto,
            "originalDocumentID": item.get("OriginalDocumentID"),
            "documentID": item.get("DocumentID"),
            "whiteBalance": item.get("WhiteBalance", "As Shot"),
            "processVersion": lr_truth._num(item.get("ProcessVersion"), 0.0),
            "hasMask": any(k.startswith("MaskGroupBasedCorr") for k in item),
            "hasRetouch": any(k.startswith("RetouchArea") for k in item),
            "cameraProfile": item.get("CameraProfile", ""),
            "toneCurve": item.get("ToneCurveName2012", ""),
        }
        for crs, key, default in lr_truth.FIELDS:
            frame[key] = lr_truth._num(item.get(crs), default)

        # Falsifier 2: a straight export carries defaults. That is not an edit and
        # is not a label — counted, not emitted.
        frame["untouched"] = (
            all(frame[k] == 0.0 for k in lr_truth.TONE_FIELDS)
            and frame["whiteBalance"] == "As Shot"
            and frame["vignette"] == 0.0
        )
        if frame["untouched"]:
            identity += 1
            identity_rows.append(frame)
            # An identity recipe is not a label. It IS, however, the cleanest possible
            # measurement of the decoder gap: the photographer accepted Lightroom's
            # default rendering, so any difference from Lumina's neutral render is
            # pipeline, not taste.
            continue

        if frame["originalDocumentID"]:
            vc_groups[frame["originalDocumentID"]].add(str(jpath))
        rule_counts[rule] += 1
        rows.append(frame)

    if do_hash:
        print(f"hashing {len({r['raw'] for r in rows})} matched RAWs ...", file=sys.stderr)
        uniq = sorted({r["raw"] for r in rows})
        with ThreadPoolExecutor(max_workers=4) as pool:
            digests = dict(zip(uniq, pool.map(lambda p: sha256(Path(p)), uniq)))
        for r in rows:
            r["rawSha256"] = digests.get(r["raw"])

    multi = {k: sorted(v) for k, v in vc_groups.items() if len(v) > 1}
    coverage = {
        "root": str(root),
        "appleDoubleStubsIgnored": stub_count,
        "rawFilesScanned": len(raws),
        "jpegFilesScanned": len(jpegs),
        "jpegExcludedByTree": excluded_jpegs,
        "excludedTrees": sorted(EXCLUDED_TREES),
        "genuinePairs": len(rows),
        "matchedByRule": dict(rule_counts),
        "identityRecipeNotALabel": identity,
        "noEmbeddedXMP": no_xmp,
        "ambiguousNotEmitted": len(ambiguous),
        "unmatched": len(unmatched),
        "distinctRawsLabelled": len({r["raw"] for r in rows}),
        "rule2_serial_available": {
            "rawsWithInternalSerial": raw_serials,
            "jpegsWithAnySerial": jpeg_serials,
            "note": "Lightroom strips MakerNotes on export; volume-wide uniqueness substituted.",
        },
        "virtualCopyGroups": {
            "groupsWithMoreThanOneExport": len(multi),
            "exportsInThoseGroups": sum(len(v) for v in multi.values()),
        },
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "labels.jsonl").open("w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
    (out_dir / "coverage.json").write_text(json.dumps(coverage, indent=2, sort_keys=True), encoding="utf-8")
    (out_dir / "unmatched.json").write_text(
        json.dumps({"ambiguous": ambiguous[:500], "unmatched": unmatched[:500]}, indent=2), encoding="utf-8")
    (out_dir / "virtual-copy-groups.json").write_text(json.dumps(multi, indent=2, sort_keys=True), encoding="utf-8")
    with (out_dir / "identity-frames.jsonl").open("w", encoding="utf-8") as fh:
        for r in identity_rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
    return coverage


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--no-hash", action="store_true")
    args = ap.parse_args(argv[1:])
    if not args.root.is_dir():
        print(f"not a directory: {args.root}", file=sys.stderr)
        return 2
    cov = build(args.root, args.out_dir, args.limit, not args.no_hash)
    print(json.dumps(cov, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
