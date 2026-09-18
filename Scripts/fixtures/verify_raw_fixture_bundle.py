#!/usr/bin/env python3
"""Fetch or verify the versioned external RAW correctness bundle."""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "design" / "fixture-manifest.yaml"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def bundle_spec() -> dict:
    data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    spec = data.get("raw_correctness_bundle")
    if not isinstance(spec, dict):
        raise RuntimeError("fixture manifest has no raw_correctness_bundle")
    return spec


def safe_extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise RuntimeError(
                        f"fixture archive links are forbidden: {member.filename}"
                    )
                target = (destination / member.filename).resolve()
                if destination.resolve() not in target.parents and target != destination.resolve():
                    raise RuntimeError(f"unsafe archive member {member.filename}")
            bundle.extractall(destination)
        return
    if tarfile.is_tarfile(archive):
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                if member.issym() or member.islnk():
                    raise RuntimeError(f"fixture archive links are forbidden: {member.name}")
                if not member.isfile() and not member.isdir():
                    raise RuntimeError(
                        f"fixture archive special entries are forbidden: {member.name}"
                    )
                target = (destination / member.name).resolve()
                if destination.resolve() not in target.parents and target != destination.resolve():
                    raise RuntimeError(f"unsafe archive member {member.name}")
            bundle.extractall(destination)
        return
    raise RuntimeError("fixture archive must be zip or tar")


def fetch_credentials(spec: dict) -> tuple[str, str]:
    url_env = str(spec["download_url_env"])
    sha_env = str(spec["archive_sha256_env"])
    url = os.environ.get(url_env)
    expected = os.environ.get(sha_env, "").lower()
    if not url or len(expected) != 64:
        raise RuntimeError(
            f"BLOCKED: fetching requires {url_env} and a 64-character {sha_env}"
        )
    return url, expected


def archive_matches(archive: Path, expected: str) -> bool:
    return archive.is_file() and sha256(archive).lower() == expected


def download_archive(url: str, archive: Path, expected: str) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    partial = archive.with_name(archive.name + ".partial")
    with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)
    actual = sha256(partial)
    if actual != expected:
        partial.unlink(missing_ok=True)
        raise RuntimeError(
            f"fixture archive checksum mismatch: expected {expected}, got {actual}"
        )
    partial.replace(archive)


def extract_root(archive: Path, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    safe_extract(archive, destination)


def fetch(destination: Path, spec: dict, archive: Path | None = None) -> None:
    url, expected = fetch_credentials(spec)
    if archive is not None:
        archive = archive.expanduser()
        if not archive_matches(archive, expected):
            download_archive(url, archive, expected)
        extract_root(archive, destination)
        return
    with tempfile.TemporaryDirectory(prefix="lumina-raw-fixtures-") as temp:
        ephemeral = Path(temp) / "bundle"
        download_archive(url, ephemeral, expected)
        extract_root(ephemeral, destination)


def verify_checksums(root: Path, checksum_name: str) -> tuple[int, set[Path]]:
    checksum_file = root / checksum_name
    if not checksum_file.is_file():
        raise RuntimeError(f"BLOCKED: missing {checksum_file}")
    checked = 0
    verified: set[Path] = set()
    for raw in checksum_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            raise RuntimeError(f"invalid checksum line: {raw!r}")
        expected, relative = parts
        relative = relative.lstrip("*")
        path = (root / relative).resolve()
        if root.resolve() not in path.parents:
            raise RuntimeError(f"checksum path escapes fixture root: {relative}")
        if not path.is_file():
            raise RuntimeError(f"fixture file missing: {relative}")
        actual = sha256(path)
        if actual.lower() != expected.lower():
            raise RuntimeError(f"checksum mismatch: {relative}")
        checked += 1
        verified.add(path)
    if checked == 0:
        raise RuntimeError("checksum manifest contains no files")
    return checked, verified


def verify(root: Path, tier: str, spec: dict) -> int:
    if not root.is_dir():
        raise RuntimeError(f"BLOCKED: fixture root does not exist: {root}")
    checked, verified = verify_checksums(root, str(spec["checksums"]))
    tier_spec = spec["tiers"][tier]
    files = [path for path in root.rglob("*") if path.is_file()]
    extensions = {path.suffix.upper() for path in files}
    required = {str(ext).upper() for ext in tier_spec["required_extensions"]}
    missing = sorted(required - extensions)
    if missing:
        raise RuntimeError(f"BLOCKED: {tier} fixture tier missing {', '.join(missing)}")
    minimum = int(tier_spec["minimum_photos"])
    unverified_media = [
        path for path in files
        if path.suffix.upper() in required and path.resolve() not in verified
    ]
    if unverified_media:
        names = ", ".join(str(path.relative_to(root)) for path in unverified_media[:5])
        raise RuntimeError(f"required media missing from checksums: {names}")
    media_count = sum(1 for path in verified if path.suffix.upper() in required)
    if media_count < minimum:
        raise RuntimeError(
            f"BLOCKED: {tier} tier has {media_count} required media files; need {minimum}"
        )
    return checked


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--tier", choices=("hosted", "full"), default="hosted")
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument(
        "--archive",
        help="Persistent archive path used as a SHA256-keyed cache for --fetch",
    )
    parser.add_argument("--print-root", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root).expanduser().resolve()
    archive = Path(args.archive).expanduser() if args.archive else None
    try:
        spec = bundle_spec()
        if args.fetch and not root.is_dir():
            fetch(root, spec, archive=archive)
        checked = verify(root, args.tier, spec)
        if args.print_root:
            print(root)
        else:
            print(
                f"verify_raw_fixture_bundle: OK "
                f"(version={spec['version']} tier={args.tier} files={checked})"
            )
        return 0
    except (RuntimeError, OSError, KeyError, urllib.error.URLError) as exc:
        print(f"FAIL: verify_raw_fixture_bundle: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
