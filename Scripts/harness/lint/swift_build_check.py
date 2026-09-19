#!/usr/bin/env python3
"""macOS compile gate — xcodebuild build-for-testing when Xcode is available.

On Linux / headless cloud agents: exit 0 with SKIP (FAST stays platform-agnostic;
FULL / regression.sh invoke this on Darwin only).
"""
from __future__ import annotations

import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main() -> int:
    if platform.system() != "Darwin":
        print(
            "SKIP: swift_build_check — xcodebuild requires macOS "
            "(static swift_token_refs covers token drift on Linux)",
            file=sys.stderr,
        )
        return 0

    if not shutil.which("xcodebuild"):
        print("FAIL: Darwin host missing xcodebuild", file=sys.stderr)
        return 1

    proc = subprocess.run(
        [
            sys.executable,
            str(ROOT / "Scripts" / "harness" / "build_cache.py"),
            "--ensure-build-for-testing",
        ],
        cwd=str(ROOT),
    )
    if proc.returncode != 0:
        print("FAIL: xcodebuild build-for-testing failed", file=sys.stderr)
        return proc.returncode

    print("swift_build_check: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
