#!/usr/bin/env python3
"""Verify HiFiTokens.* references in Swift resolve to generated token members.

Catches compile errors like
  Type 'HiFiTokens.Motion' has no member 'placeReturnMs'
before xcodebuild on macOS — run in FAST on Linux CI / cloud agents.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GENERATED = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"

SCAN_ROOTS = (
    ROOT / "Lumina",
    ROOT / "LuminaLogicTests",
    ROOT / "DesignTokens",
)

TOKEN_REF = re.compile(r"\bHiFiTokens\.(\w+)\.(\w+)\b")
ENUM_START = re.compile(r"^\s+enum (\w+) \{")
STATIC_MEMBER = re.compile(r"^\s+static (?:let|var) (\w+)(?:\s*[:=])")
STATIC_FUNC = re.compile(r"^\s+static func (\w+)\(")
ENUM_CLOSE = re.compile(r"^\s+\}")

# F07 / SPIKE B — LuminaSpring and motion wiring must stay yaml-backed.
REQUIRED_MOTION_MEMBERS = frozenset(
    {
        "placeReturnMs",
        "springTrajectorySampleRateHz",
        "springMaxOvershoot",
        "springReducedMotionOvershoot",
    }
)


def parse_token_members(text: str) -> dict[str, set[str]]:
    members: dict[str, set[str]] = {}
    stack: list[str] = []
    for line in text.splitlines():
        if match := ENUM_START.match(line):
            name = match.group(1)
            stack.append(name)
            members.setdefault(name, set())
        elif stack and (match := STATIC_MEMBER.match(line)):
            members[stack[-1]].add(match.group(1))
        elif stack and (match := STATIC_FUNC.match(line)):
            members[stack[-1]].add(match.group(1))
        elif ENUM_CLOSE.match(line) and stack:
            stack.pop()
    return members


def collect_swift_refs() -> list[tuple[str, int, str, str]]:
    refs: list[tuple[str, int, str, str]] = []
    for root in SCAN_ROOTS:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            if path.resolve() == GENERATED.resolve():
                continue
            rel = path.relative_to(ROOT).as_posix()
            for line_no, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                for match in TOKEN_REF.finditer(line):
                    refs.append((rel, line_no, match.group(1), match.group(2)))
    return refs


def main() -> int:
    if not GENERATED.is_file():
        print(f"FAIL: missing generated tokens {GENERATED}", file=sys.stderr)
        return 1

    members = parse_token_members(GENERATED.read_text(encoding="utf-8"))
    if "Motion" not in members:
        print("FAIL: HiFiTokens.generated.swift missing Motion enum", file=sys.stderr)
        return 1

    missing_required = REQUIRED_MOTION_MEMBERS - members["Motion"]
    if missing_required:
        for name in sorted(missing_required):
            print(
                f"FAIL: HiFiTokens.Motion.{name} missing from generated tokens "
                f"(run python3 Scripts/harness/codegen/tokens_codegen.py)",
                file=sys.stderr,
            )
        return 1

    fail = 0
    for rel, line_no, enum_name, member in collect_swift_refs():
        enum_members = members.get(enum_name)
        if enum_members is None:
            print(
                f"FAIL: HiFiTokens.{enum_name} undefined — referenced in {rel}:{line_no}",
                file=sys.stderr,
            )
            fail = 1
            continue
        if member not in enum_members:
            print(
                f"FAIL: HiFiTokens.{enum_name}.{member} missing from generated tokens "
                f"— referenced in {rel}:{line_no}",
                file=sys.stderr,
            )
            fail = 1

    if fail:
        print(
            "NOTE: regenerate with python3 Scripts/harness/codegen/tokens_codegen.py",
            file=sys.stderr,
        )
        return 1

    ref_count = len(collect_swift_refs())
    print(
        f"swift_token_refs.py: OK ({ref_count} HiFiTokens references, "
        f"{len(members)} token enums)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
