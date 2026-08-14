#!/usr/bin/env python3
"""Ratchet duplicate PNG/HTML evidence dirs out of the tracked tree."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

CANONICAL = {
    "artifacts/workbench-v6",
    "artifacts/raw-harness-v6",
    "artifacts/raw-perf",
}

LEGACY_PREFIXES = (
    "artifacts/workbench-v3",
    "artifacts/workbench-v4",
    "artifacts/workbench-v5",
    "artifacts/raw-perf-v3",
    "artifacts/raw-perf-release",
    "artifacts/raw-harness-v5",
    "artifacts/lab-theme",
)


def tracked_paths() -> list[str]:
    proc = subprocess.run(
        ["git", "ls-files", "artifacts"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=True,
    )
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def main() -> int:
    tracked = tracked_paths()
    offenders = sorted(
        {
            path
            for path in tracked
            for legacy in LEGACY_PREFIXES
            if path == legacy or path.startswith(legacy + "/")
        }
    )
    if offenders:
        print("FAIL: duplicate artifact evidence still tracked:", file=sys.stderr)
        for path in offenders[:20]:
            print(f"  {path}", file=sys.stderr)
        if len(offenders) > 20:
            print(f"  … and {len(offenders) - 20} more", file=sys.stderr)
        print(f"NOTE: keep canonical dirs only: {sorted(CANONICAL)}", file=sys.stderr)
        return 1
    print("repo_artifact_bloat: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
