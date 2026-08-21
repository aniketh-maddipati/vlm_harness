#!/usr/bin/env python3
"""Re-hash a cut latency card and fail on drift.

E1 Gate 2 verification. A fixture whose bytes have changed silently invalidates
every number ever recorded against it, so the checksum manifest written at cut
time is re-verified here.

Usage:
    python3 Scripts/fixtures/verify_latency_card.py ~/Pictures/lumina-fixtures/card-clean-500

Exit 0 = every frame matches. Exit 1 = drift, missing, or extra files.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(chunk), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    card = Path(sys.argv[1]).expanduser().resolve()
    checksums = card / "checksums.sha256"
    meta_path = card / "fixture.json"

    if not checksums.is_file():
        print(f"FAIL: no checksum manifest at {checksums}")
        return 1

    expected: dict[str, str] = {}
    for line in checksums.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, name = line.split("  ", 1)
        expected[name] = digest

    on_disk = {
        p.name for p in card.iterdir()
        if p.is_file() and p.name not in {"checksums.sha256", "fixture.json"}
    }

    missing = sorted(set(expected) - on_disk)
    extra = sorted(on_disk - set(expected))
    drifted: list[str] = []

    for name, digest in sorted(expected.items()):
        target = card / name
        if not target.is_file():
            continue
        if sha256(target) != digest:
            drifted.append(name)

    fixture_id = card.name
    if meta_path.is_file():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        fixture_id = meta.get("fixture_id", fixture_id)

    if missing or extra or drifted:
        print(f"FAIL: {fixture_id} has drifted.")
        for name in missing[:10]:
            print(f"  missing: {name}")
        for name in extra[:10]:
            print(f"  unexpected: {name}")
        for name in drifted[:10]:
            print(f"  checksum drift: {name}")
        total = len(missing) + len(extra) + len(drifted)
        if total > 30:
            print(f"  … {total} problems in total")
        return 1

    print(f"OK: {fixture_id} — {len(expected)} frames match checksums.sha256")
    return 0


if __name__ == "__main__":
    sys.exit(main())
