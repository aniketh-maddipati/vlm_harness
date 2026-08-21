#!/usr/bin/env python3
"""Compile rot-guard — collect every Swift/Clang error in one xcodebuild pass.

FULL lane job #1 on macOS. Uses `build-for-testing` so the app, logic tests,
and UI tests are all compiled. Continues after errors so one file does not
hide the rest. On hosts without xcodebuild: exit 2 (PLATFORM-UNAVAILABLE).
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ERROR_LINE = re.compile(
    r"^(?P<file>.+?):(?P<line>\d+):(?P<col>\d+): error: (?P<msg>.+)$"
)
BARE_ERROR = re.compile(r"^error: (?P<msg>.+)$")


def project_root(explicit: str | None = None) -> Path:
    if explicit:
        root = Path(explicit).resolve()
    else:
        cwd = Path.cwd()
        root = cwd if (cwd / "Lumina.xcodeproj").is_dir() else Path(__file__).resolve().parents[3]
    if not (root / "Lumina.xcodeproj").is_dir():
        raise SystemExit(f"xcode_compile: Lumina.xcodeproj missing under {root}")
    return root


def parse_errors(log: str) -> list[dict[str, str]]:
    """Deduplicate compiler errors from an xcodebuild log."""
    seen: set[tuple[str, str, str]] = set()
    out: list[dict[str, str]] = []
    for raw in log.splitlines():
        line = raw.rstrip()
        match = ERROR_LINE.match(line)
        if match:
            key = (match.group("file"), match.group("line"), match.group("msg"))
            if key in seen:
                continue
            seen.add(key)
            out.append(
                {
                    "file": match.group("file"),
                    "line": match.group("line"),
                    "col": match.group("col"),
                    "message": match.group("msg").strip(),
                }
            )
            continue
        bare = BARE_ERROR.match(line)
        if bare:
            key = ("", "", bare.group("msg"))
            if key in seen:
                continue
            seen.add(key)
            out.append(
                {
                    "file": "",
                    "line": "",
                    "col": "",
                    "message": bare.group("msg").strip(),
                }
            )
    return out


def format_error(item: dict[str, str]) -> str:
    if item["file"]:
        return f"{item['file']}:{item['line']}:{item['col']}: {item['message']}"
    return item["message"]


def platform_unavailable() -> int:
    print("xcode_compile: PLATFORM-UNAVAILABLE (need Darwin + xcodebuild)", file=sys.stderr)
    return 2


def run_build(
    root: Path, derived: Path, configuration: str, action: str, scheme: str = "Lumina"
) -> tuple[int, str]:
    derived.mkdir(parents=True, exist_ok=True)
    cmd = [
        "xcodebuild",
        "-project",
        "Lumina.xcodeproj",
        "-scheme",
        scheme,
        "-configuration",
        configuration,
        "-destination",
        "platform=macOS,arch=arm64",
        "-derivedDataPath",
        str(derived),
        "SWIFT_CONTINUE_BUILDING_AFTER_ERRORS=YES",
        "COMPILER_INDEX_STORE_ENABLE=NO",
        action,
    ]
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
    )
    log = (proc.stdout or "") + ("\n" if proc.stderr else "") + (proc.stderr or "")
    return proc.returncode, log


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=None)
    parser.add_argument("--configuration", default="Debug")
    parser.add_argument(
        "--scheme",
        default="Lumina",
        help="xcodebuild scheme (default: Lumina; use LuminaPlayground for the polish loop)",
    )
    parser.add_argument(
        "--derived-data",
        default=None,
        help="derivedDataPath (default: <root>/DD)",
    )
    parser.add_argument(
        "--parse-log",
        default=None,
        help="Parse an existing xcodebuild log instead of building (unit/debug)",
    )
    parser.add_argument(
        "--action",
        default="build-for-testing",
        choices=("build", "build-for-testing"),
        help="xcodebuild action (default: build-for-testing, includes test targets)",
    )
    args = parser.parse_args(argv)

    if args.parse_log:
        log = Path(args.parse_log).read_text(encoding="utf-8", errors="replace")
        errors = parse_errors(log)
        for item in errors:
            print(f"error: {format_error(item)}", file=sys.stderr)
        print(f"xcode_compile: {len(errors)} error(s)")
        return 1 if errors else 0

    if os.uname().sysname != "Darwin" or shutil.which("xcodebuild") is None:
        return platform_unavailable()

    root = project_root(args.project_root)
    derived = Path(args.derived_data) if args.derived_data else root / "DD"
    if not derived.is_absolute():
        derived = root / derived

    code, log = run_build(root, derived, args.configuration, args.action, args.scheme)
    errors = parse_errors(log)
    if errors:
        print("xcode_compile: FAIL — compiler errors:", file=sys.stderr)
        for item in errors:
            print(f"  {format_error(item)}", file=sys.stderr)
        print(f"xcode_compile: {len(errors)} error(s)")
        return 1
    if code != 0:
        tail = "\n".join(log.strip().splitlines()[-20:])
        print("xcode_compile: FAIL — xcodebuild exited non-zero without parseable errors", file=sys.stderr)
        print(tail, file=sys.stderr)
        return 1
    print("xcode_compile: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
