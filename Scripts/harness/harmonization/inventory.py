"""Read-only local media inventory. Metadata is evidence, never a decode guarantee."""

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sqlite3
import subprocess
import time


VERSION = "harmonization-inventory-2"
EXTRACTION_VERSION = "harmonization-inventory-1"
EXTENSIONS = {".arw", ".dng", ".heic", ".heif", ".hif", ".jpg", ".jpeg", ".mov", ".mp4", ".m4v"}
EXCLUDED = {".Trashes", ".Spotlight-V100", ".fseventsd", "$RECYCLE.BIN", ".git"}
FIELDS = {
    "FileType", "MIMEType", "Make", "Model", "LensModel", "LensID", "FocalLength",
    "FocalLengthIn35mmFormat", "FNumber", "ExposureTime", "ISO", "DateTimeOriginal",
    "CreateDate", "SubSecDateTimeOriginal", "OffsetTimeOriginal", "OffsetTime",
    "Orientation", "ImageWidth", "ImageHeight", "ExifImageWidth", "ExifImageHeight",
    "RawImageFullSize", "PreviewImageSize", "PreviewImageWidth", "PreviewImageHeight",
    "ThumbnailImageWidth", "ThumbnailImageHeight", "ProfileDescription", "ColorSpace",
    "ColorPrimaries", "TransferCharacteristics", "MatrixCoefficients", "BitDepth",
    "BitsPerSample", "VideoFrameRate", "Duration", "CompressorID", "CompressorName",
    "DNGVersion", "DNGBackwardVersion", "PhotometricInterpretation", "UniqueCameraModel",
    "Software", "BurstUUID", "BurstID", "ImageUniqueID", "CustomRendered",
    "HDRHeadroom", "HDRGain", "HDRGainMapVersion", "AuxiliaryImageType", "Error", "Warning",
}


def stable_id(value):
    return hashlib.sha256(value.encode("utf-8", errors="surrogateescape")).hexdigest()


def sanitize(metadata):
    selected = {}
    gps_present = False
    for key, value in metadata.items():
        tag = key.split(":")[-1]
        if "gps" in key.lower():
            gps_present = True
            continue
        if tag in FIELDS or "gainmap" in tag.lower() or tag.startswith("HDR"):
            selected[key] = value
    return selected, gps_present


def field(metadata, name):
    matches = [(key, value) for key, value in metadata.items() if key.split(":")[-1] == name]
    return matches[0][1] if matches else None


def signature(path):
    with path.open("rb") as source:
        header = source.read(16)
    return header.startswith((b"\xff\xd8\xff", b"II*\x00", b"MM\x00*")) or header[4:8] == b"ftyp"


def discover(roots, excluded, extensionless=False, errors=None):
    seen = set()
    for root in roots:
        def walk_error(error):
            if errors is None:
                raise error
            errors.append({"path": error.filename, "error": str(error), "status": "unavailable_not_scanned"})
        for directory, folders, names in os.walk(root, followlinks=False, onerror=walk_error):
            folders[:] = sorted(name for name in folders if name not in EXCLUDED
                                and not (Path(directory) / name).is_symlink()
                                and not any((Path(directory) / name).is_relative_to(skip) for skip in excluded))
            for name in sorted(names):
                path = Path(directory) / name
                if name.startswith("._") or path.is_symlink() or path in seen:
                    continue
                if any(path.is_relative_to(skip) for skip in excluded):
                    continue
                if path.suffix.lower() not in EXTENSIONS:
                    try:
                        if not (extensionless and not path.suffix
                                and not getattr(path.stat(), "st_flags", 0) & 0x40000000 and signature(path)):
                            continue
                    except OSError as error:
                        walk_error(error)
                        continue
                seen.add(path)
                yield path


def stat_key(path):
    status = path.stat()
    return [status.st_size, status.st_mtime_ns, status.st_ctime_ns, status.st_ino, status.st_dev]


def extract(paths, executable):
    command = [executable, "-json", "-G1", "-n", "-api", "LargeFileSupport=1", *map(str, paths)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    try:
        rows = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("exiftool did not return valid JSON") from error
    return {row["SourceFile"]: row for row in rows}


def normalize(path, status, metadata, gps_present, previous=None):
    get = lambda name: field(metadata, name)
    kind = get("FileType") or "unknown"
    model = str(get("Model") or get("UniqueCameraModel") or "unknown")
    is_phone = "iphone" in model.lower()
    is_sony = model == "ILCE-7M3"
    capture = get("SubSecDateTimeOriginal") or get("DateTimeOriginal") or get("CreateDate")
    offset = get("OffsetTimeOriginal") or get("OffsetTime")
    hdr = {key: value for key, value in metadata.items()
           if any(word in key.lower() for word in ("hdr", "gainmap", "transfer", "primaries", "auxiliary"))}
    identity = None
    if previous and previous.get("bytes") == status[0] and abs(previous.get("mtime", -1) - status[1] / 1e9) < 0.001:
        identity = previous.get("contentIdentity")
    classification = "raw_candidate" if kind in {"ARW", "DNG"} else "rendered"
    if kind in {"MOV", "MP4", "M4V"}:
        classification = "video"
    if kind == "unknown" or get("Error"):
        classification = "unrecognized"
    software = str(get("Software") or "")
    library = any(part.endswith((".lrlibrary", ".photoslibrary")) for part in path.parts)
    derivative_path = library and bool({"previews", "derivatives", "renders", "Thumbnails"}.intersection(path.parts))
    if "imagecore" in software.lower() or derivative_path:
        classification = "cache_derivative"
    return {
        "schema_version": 1, "asset_id": stable_id(str(path)), "source_path": str(path),
        "fingerprint": {"method": "path+size+mtime_ns+ctime_ns+inode+device", "stat": status,
                        "content_identity": identity, "content_identity_evidence": "reused-prior-stat-match" if identity else None},
        "format": kind, "codec": get("CompressorID") or get("CompressorName"),
        "classification": classification, "device_family": "iphone" if is_phone else "sony_a7iii" if is_sony else "other_or_unknown",
        "source_role": "library_derivative" if derivative_path else "local_original_candidate" if library and "originals" in path.parts else "unverified_file",
        "capture": {"value": capture, "offset": offset, "timezone_evidence": "explicit_offset" if offset else "unknown",
                    "source": "EXIF" if get("DateTimeOriginal") else "container_or_unknown"},
        "camera": {"make": get("Make"), "model": model, "lens": get("LensModel") or get("LensID"),
                   "focal_mm": get("FocalLength"), "aperture": get("FNumber"), "shutter_seconds": get("ExposureTime"), "iso": get("ISO")},
        "image": {"width": get("ImageWidth"), "height": get("ImageHeight"), "orientation": get("Orientation"),
                  "preview_width": get("PreviewImageWidth"), "preview_height": get("PreviewImageHeight"),
                  "preview_size": get("PreviewImageSize")},
        "color": {"profile": get("ProfileDescription"), "color_space": get("ColorSpace"),
                  "hdr_evidence": hdr, "hdr_status": "metadata_present_unverified" if hdr else "unknown",
                  "gain_map_status": "UNVERIFIED", "proraw_status": "candidate_requires_decoder_verification" if kind == "DNG" and is_phone else "not_verified"},
        "gps_present": gps_present,
        "video": {"duration_seconds": get("Duration"), "fps": get("VideoFrameRate"), "temporal_validation": "UNMEASURED"},
        "burst_id": get("BurstUUID") or get("BurstID"), "near_duplicate_group": None,
        "decode_status": "UNMEASURED", "metadata_error": get("Error"), "metadata_warning": get("Warning"),
        "missing_fields": [name for name in ("DateTimeOriginal", "Model", "ImageWidth", "ImageHeight", "ProfileDescription", "ISO", "LensModel") if get(name) is None],
        "metadata": metadata,
    }


def candidates(rows):
    buckets = defaultdict(list)
    for row in rows:
        stamp = row["capture"]["value"]
        if not isinstance(stamp, str) or len(stamp) < 16 or row["classification"] in {"cache_derivative", "unrecognized"}:
            continue
        try:
            moment = datetime.strptime(stamp[:19], "%Y:%m:%d %H:%M:%S")
        except ValueError:
            continue
        key = moment.strftime("%Y-%m-%dT%H:") + str(moment.minute // 10)
        buckets[key].append(row)
    groups = []
    for key, members in sorted(buckets.items()):
        families = sorted({row["device_family"] for row in members})
        if len(members) < 2:
            continue
        groups.append({"candidate_id": stable_id(key), "wall_clock_bucket": key,
                       "asset_ids": [row["asset_id"] for row in members], "device_families": families,
                       "cross_device_candidate": {"iphone", "sony_a7iii"}.issubset(families),
                       "scene_verified": False, "event_verified": False,
                       "evidence": "10-minute wall-clock bucket only; offsets and camera clock skew unverified",
                       "rank": 2 if {"iphone", "sony_a7iii"}.issubset(families) else 1})
    return sorted(groups, key=lambda group: (-group["rank"], group["wall_clock_bucket"]))


def summarize(rows, groups):
    counts = {}
    for key, getter in {
        "device": lambda row: row["camera"]["model"], "format": lambda row: row["format"],
        "lens": lambda row: row["camera"]["lens"], "iso": lambda row: row["camera"]["iso"],
        "month": lambda row: str(row["capture"]["value"] or "unknown")[:7],
        "classification": lambda row: row["classification"],
    }.items():
        counts[key] = dict(Counter(str(getter(row)) for row in rows).most_common())
    return {"assets": len(rows), "counts": counts, "candidate_groups": len(groups),
            "cross_device_candidates": sum(group["cross_device_candidate"] for group in groups),
            "metadata_errors": sum(bool(row["metadata_error"]) for row in rows),
            "verified_scenes": 0, "verified_proraw": 0, "decode": "UNMEASURED"}


def atomic_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n")
    temporary.replace(path)


def run(args):
    roots = sorted({path.resolve(strict=True) for path in args.root})
    out = args.out.resolve()
    repository = Path(__file__).resolve().parents[3]
    if any((parent / ".git").exists() for parent in (out, *out.parents)):
        raise ValueError("Private evidence must be outside every git worktree")
    if any(out == root or out.is_relative_to(root) for root in [repository, *roots]):
        raise ValueError("Evidence output must be outside the repository and all scanned roots")
    if any(not root.is_dir() for root in roots):
        raise ValueError("Scan roots must be directories")
    out.mkdir(parents=True, exist_ok=True, mode=0o700)
    prior = {}
    for source in args.reuse_raw:
        for line in source.read_text().splitlines():
            row = json.loads(line)
            prior[row["path"]] = row
    tool_version = subprocess.check_output([args.exiftool, "-ver"], text=True).strip()
    cache = sqlite3.connect(out / "metadata.sqlite")
    cache.execute("CREATE TABLE IF NOT EXISTS cache (path TEXT PRIMARY KEY, signature TEXT, record TEXT)")
    started = time.monotonic()
    rows, pending, cache_hits, extraction_seconds = [], [], 0, []
    discovery_errors = []
    excluded = [path.resolve() for path in args.exclude]

    def flush():
        if not pending:
            return
        tick = time.monotonic()
        extracted = extract([item[0] for item in pending], args.exiftool)
        extraction_seconds.append(time.monotonic() - tick)
        for path, status, key in pending:
            raw = extracted.get(str(path), {"Error": "metadata record missing"})
            metadata, gps = sanitize(raw)
            if stat_key(path) != status:
                raise RuntimeError("Source changed during read: " + str(path))
            row = normalize(path, status, metadata, gps, prior.get(str(path)))
            cache.execute("INSERT OR REPLACE INTO cache VALUES (?, ?, ?)", (str(path), key, json.dumps(row)))
            rows.append(row)
        cache.commit()
        pending.clear()

    try:
        for path in discover(roots, excluded, args.extensionless, discovery_errors):
            status = stat_key(path)
            if getattr(path.stat(), "st_flags", 0) & 0x40000000:
                row = normalize(path, status, {"Error": "cloud_placeholder_not_opened"}, False)
                row["source_role"] = "unavailable_cloud_placeholder"
                rows.append(row)
                continue
            key = json.dumps([EXTRACTION_VERSION, tool_version, status])
            cached = cache.execute("SELECT record FROM cache WHERE path=? AND signature=?", (str(path), key)).fetchone()
            if cached:
                saved = json.loads(cached[0])
                refreshed = normalize(path, status, saved["metadata"], saved["gps_present"], prior.get(str(path)))
                if refreshed["fingerprint"]["content_identity"] is None:
                    refreshed["fingerprint"] = saved["fingerprint"]
                rows.append(refreshed)
                cache_hits += 1
            else:
                pending.append((path, status, key))
            if len(pending) >= args.batch_size:
                flush()
        flush()
    finally:
        cache.close()
    rows.sort(key=lambda row: row["source_path"])
    groups = candidates(rows)
    summary = summarize(rows, groups)
    elapsed = time.monotonic() - started
    manifest = {"schema_version": 1, "algorithm": VERSION, "exiftool_version": tool_version,
                "created_utc": datetime.now(timezone.utc).isoformat(), "roots": list(map(str, roots)),
                "excluded": list(map(str, excluded)), "extensionless": args.extensionless,
                "discovery_errors": discovery_errors, "scan_complete": not discovery_errors,
                "host": platform.platform(), "cache_hits": cache_hits, "metadata_elapsed_seconds": elapsed,
                "metadata_assets_per_second": len(rows) / elapsed if elapsed else None,
                "batch_seconds": extraction_seconds, "os_cache": "uncontrolled", "application_cache": "sqlite stat-key cache",
                "peak_rss": "UNMEASURED; use external /usr/bin/time -l", "physical_footprint": "UNMEASURED; use external /usr/bin/time -l",
                "decode_features_inference_render_export": "UNMEASURED", "summary": summary, "assets": rows}
    atomic_json(out / "manifest.json", manifest)
    atomic_json(out / "candidates.json", groups)
    report = ["# Harmonization inventory", "", f"{len(rows)} files; {cache_hits} metadata cache hits; {elapsed:.2f} seconds.",
              "Metadata scan only. Decode, ProRAW and HDR/gain-map support remain unverified.",
              "Asset IDs identify paths, not byte equality. Reused content identities retain their original evidence.",
              "Source originals were opened read-only. GPS coordinates are excluded; presence is retained.",
              f"Unavailable paths: {len(discovery_errors)}. Cloud-only library records were not queried or downloaded.",
              "", f"{summary['cross_device_candidates']} possible cross-device time groups; 0 verified scenes."]
    for category, values in summary["counts"].items():
        report += ["", "## " + category, "", *[f"- {key}: {count}" for key, count in values.items()]]
    (out / "REPORT.md").write_text("\n".join(report) + "\n")
    print(json.dumps({key: value for key, value in manifest.items() if key != "assets"}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, action="append", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--exclude", type=Path, action="append", default=[])
    parser.add_argument("--reuse-raw", type=Path, action="append", default=[])
    parser.add_argument("--extensionless", action="store_true")
    parser.add_argument("--exiftool", default="exiftool")
    parser.add_argument("--batch-size", type=int, default=64)
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 256:
        parser.error("batch size must be between 1 and 256")
    run(args)


if __name__ == "__main__":
    main()
