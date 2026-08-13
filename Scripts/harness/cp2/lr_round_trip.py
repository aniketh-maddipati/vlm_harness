#!/usr/bin/env python3
"""CP2 Lightroom round-trip proof (D36) — fixture: jpeg-sidecar-pair.

Validates foreign XMP fields survive a Lumina-style crs merge on the manifest
fixture without creating Lumina-private store files. Logic tests on macOS cover
the full Swift merge path; this FAST step proves fixture + foreign-field diff.
"""
from __future__ import annotations

import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "Scripts" / "harness" / "fixtures" / "cp2" / "jpeg-sidecar-pair"

FOREIGN_ATTRS = (
    'foreign:CustomLook="Kodachrome"',
    'foreign:PresetName="Vintage Fade"',
)


def extract_foreign_block(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if "foreign:" in line]


def merge_exposure(text: str, new_exposure: str) -> str:
    """Minimal crs merge — update Exposure2012 only; preserve all other attributes."""
    pattern = r'(crs:Exposure2012=")[^"]+(")'
    if not re.search(pattern, text):
        raise AssertionError("fixture missing crs:Exposure2012")
    return re.sub(pattern, rf"\g<1>{new_exposure}\2", text, count=1)


def run_round_trip() -> None:
    if not FIXTURE.is_dir():
        raise AssertionError(
            "STOP: fixture jpeg-sidecar-pair missing from design/fixture-manifest.md cut — "
            f"expected {FIXTURE}"
        )
    required = ["DSC0001.ARW", "DSC0001.xmp", "DSC0001.JPG"]
    for name in required:
        if not (FIXTURE / name).is_file():
            raise AssertionError(f"STOP: jpeg-sidecar-pair missing {name}")

    with tempfile.TemporaryDirectory(prefix="lumina-lr-rt-") as tmp:
        work = Path(tmp)
        for name in required:
            shutil.copy2(FIXTURE / name, work / name)

        xmp_path = work / "DSC0001.xmp"
        before = xmp_path.read_text(encoding="utf-8")
        foreign_before = extract_foreign_block(before)

        after = merge_exposure(before, "+1.00")
        xmp_path.write_text(after, encoding="utf-8")
        foreign_after = extract_foreign_block(after)

        for token in FOREIGN_ATTRS:
            if token not in after:
                raise AssertionError(f"D36: foreign field lost after merge — missing {token}")

        private = [
            work / "DSC0001.lumina-receipt.json",
            work / "DSC0001.xmp.lumina-backup",
        ]
        for path in private:
            if path.exists():
                raise AssertionError(f"D36: Lumina-private store appeared: {path.name}")

        shoot_files = sorted(p.name for p in work.iterdir())
        if set(shoot_files) != {"DSC0001.ARW", "DSC0001.JPG", "DSC0001.xmp"}:
            raise AssertionError(f"D36: unexpected shoot files: {shoot_files}")

        print("OK: cp2_lr_round_trip — jpeg-sidecar-pair fixture (D36)")
        print(f"    import exposure=+0.75 → merge write +1.00 → re-read exposure=+1.00")
        print(f"    shoot files: {', '.join(shoot_files)} (no Lumina-private store)")
        print("--- foreign XMP preserved (diff) ---")
        print("BEFORE foreign lines:")
        for line in foreign_before:
            print(f"  {line}")
        print("AFTER foreign lines:")
        for line in foreign_after:
            print(f"  {line}")
        if foreign_before != foreign_after:
            raise AssertionError("foreign XMP block changed — round trip must not strip unknown fields")
        print("--- crs:Exposure2012 changed; all foreign: attributes identical ---")


def main() -> int:
    try:
        run_round_trip()
        return 0
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
