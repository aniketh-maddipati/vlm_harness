#!/usr/bin/env python3
"""Keep P0SessionModel's develop scheduler file-private.

Call sites must use displayedCIImage / developFidelity / editMetricsLine.
A private-access slip here is a compile break on the next visibility tighten.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ALLOWED = {
    "Lumina/ViewModels/P0SessionModel.swift",
}
PATTERN = re.compile(r"\.developScheduler\b")
SCAN_ROOTS = (
    ROOT / "Lumina",
    ROOT / "LuminaLogicTests",
    ROOT / "LuminaUITests",
)


def main() -> int:
    fail = 0
    for scan in SCAN_ROOTS:
        if not scan.is_dir():
            continue
        for path in sorted(scan.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            if rel in ALLOWED:
                continue
            for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if PATTERN.search(line):
                    print(
                        f"FAIL: {rel}:{index} reaches developScheduler — "
                        "use displayedCIImage / developFidelity / editMetricsLine",
                        file=sys.stderr,
                    )
                    fail = 1
    if fail:
        return 1
    print("session_surface: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
