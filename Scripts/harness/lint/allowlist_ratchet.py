#!/usr/bin/env python3
"""Allowlist ratchet — debt allowlists must not grow vs origin/main."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ALLOWLISTS = (
    ROOT / "artifacts" / "harness" / "banned_patterns_allowlist.txt",
    ROOT / "artifacts" / "harness" / "magic_number_allowlist.txt",
    ROOT / "artifacts" / "harness" / "orphan_register.txt",
    ROOT / "artifacts" / "harness" / "costume_allowlist.txt",
)


def countable_lines(text: str) -> int:
    count = 0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        count += 1
    return count


def origin_main_lines(rel: Path) -> int | None:
    """Countable debt lines on origin/main, or None when the register does not exist there.

    Absent and empty are different facts: an absent register is being introduced by this
    branch and has no baseline to ratchet against yet, while an empty one is a register whose
    debt has been paid off and must stay at zero.
    """
    proc = subprocess.run(
        ["git", "show", f"origin/main:{rel.as_posix()}"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    return countable_lines(proc.stdout)


def main() -> int:
    fail = 0
    for path in ALLOWLISTS:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            print(f"FAIL: missing {rel}", file=sys.stderr)
            fail = 1
            continue
        current = countable_lines(path.read_text(encoding="utf-8"))
        baseline = origin_main_lines(rel)
        if baseline is None:
            # New register seeded on this branch. Announce the starting debt loudly — it
            # becomes the baseline the moment this merges, and may only shrink after that.
            print(f"allowlist_ratchet: NEW register {rel} seeded at {current} debt lines")
            continue
        if current > baseline:
            print(
                f"FAIL: {rel} ratchet — {current} debt lines > origin/main {baseline}",
                file=sys.stderr,
            )
            fail = 1
    if fail:
        return 1
    print("allowlist_ratchet: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
