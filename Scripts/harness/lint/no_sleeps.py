#!/usr/bin/env python3
"""no_sleeps — ban wall-clock sleeps in UI tests and harness (F04.3).

Scans LuminaUITests/** and Scripts/harness/** for:
  Thread.sleep, time.sleep, usleep, sleep(

Exactly one allowlisted exception: watch-mode poll in Scripts/harness/run.py.
Measured baseline: LuminaUITests/** has zero — keep it there.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCAN_ROOTS = (
    ROOT / "LuminaUITests",
    ROOT / "Scripts" / "harness",
)
SCAN_SUFFIXES = {".swift", ".py", ".sh"}
SKIP_FILES = {
    (ROOT / "Scripts" / "harness" / "lint" / "no_sleeps.py").resolve(),
}

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Thread.sleep", re.compile(r"Thread\.sleep\b")),
    ("time.sleep", re.compile(r"time\.sleep\b")),
    ("usleep", re.compile(r"\busleep\s*\(")),
    ("sleep(", re.compile(r"\bsleep\s*\(")),
)

# Single allowlist: watch-mode poll loop in run.py (F04.3).
WATCH_POLL_ALLOWLIST = (
    ROOT / "Scripts" / "harness" / "run.py",
    re.compile(r"time\.sleep\s*\(\s*1\.0\s*\)"),
)


def _is_comment_line(line: str) -> bool:
    stripped = line.lstrip()
    return stripped.startswith("#") or stripped.startswith("//")


def _in_watch_loop(lines: list[str], line_index: int) -> bool:
    func_start = None
    for idx, line in enumerate(lines):
        if line.startswith("def watch_loop"):
            func_start = idx
            break
    if func_start is None or line_index <= func_start:
        return False
    for line in lines[func_start + 1 : line_index + 1]:
        if line.startswith("def ") and not line.startswith("def watch_loop"):
            return False
    return True


def _allowlisted(path: Path, line: str, lines: list[str], line_index: int) -> bool:
    allow_path, pattern = WATCH_POLL_ALLOWLIST
    if path.resolve() != allow_path.resolve():
        return False
    if not pattern.search(line):
        return False
    return _in_watch_loop(lines, line_index)


def scan_file(path: Path) -> list[str]:
    rel = path.relative_to(ROOT)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    hits: list[str] = []
    for line_index, line in enumerate(lines, start=1):
        if _is_comment_line(line):
            continue
        if _allowlisted(path, line, lines, line_index):
            continue
        for label, pattern in PATTERNS:
            if pattern.search(line):
                hits.append(f"{rel}:{line_index}: {label} — {line.strip()}")
                break
    return hits


def iter_scan_files() -> list[Path]:
    files: list[Path] = []
    for root in SCAN_ROOTS:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in SCAN_SUFFIXES and path.resolve() not in SKIP_FILES:
                files.append(path)
    return files


def main() -> int:
    failures: list[str] = []
    for path in iter_scan_files():
        failures.extend(scan_file(path))

    if failures:
        print("FAIL: no_sleeps — wall-clock sleep banned (one allowlist: run.py watch poll)", file=sys.stderr)
        for msg in failures:
            print(f"  {msg}", file=sys.stderr)
        return 1

    print("no_sleeps: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
