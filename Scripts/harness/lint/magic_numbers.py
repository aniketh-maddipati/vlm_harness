#!/usr/bin/env python3
"""Magic-number gate — forbid hand-literals owned by tokens.yaml in UI sources."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ALLOW = ROOT / "artifacts" / "harness" / "magic_number_allowlist.txt"
GENERATED = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"
CODEGEN = ROOT / "Scripts" / "harness" / "codegen" / "tokens_codegen.py"

SCAN_ROOTS = (
    ROOT / "Lumina" / "Views",
    ROOT / "Lumina" / "Design",
    ROOT / "Lumina" / "Shell",
)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from magic_number_literals import (  # noqa: E402
    compile_literal_pattern,
    extract_forbidden_literals,
    index_literal_skipped,
    line_skipped,
)


def load_allowlist() -> set[tuple[str, str]]:
    allowed: set[tuple[str, str]] = set()
    if not ALLOW.is_file():
        return allowed
    for raw in ALLOW.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) == 2:
            allowed.add((parts[0], parts[1]))
    return allowed


def scan_files(
    forbidden: dict[str, set[str]] | None = None,
) -> list[tuple[str, int, str, str]]:
    forbidden = (
        extract_forbidden_literals(GENERATED) if forbidden is None else forbidden
    )
    literal_pattern = compile_literal_pattern(list(forbidden))
    hits: list[tuple[str, int, str, str]] = []
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
                if line_skipped(line):
                    continue
                for match in literal_pattern.finditer(line):
                    literal = match.group(0)
                    if index_literal_skipped(line, literal):
                        continue
                    hits.append((rel, line_no, literal, line.strip()))
    return hits


def main() -> int:
    if not GENERATED.is_file():
        print(f"FAIL: missing generated tokens {GENERATED}", file=sys.stderr)
        return 1
    proc = subprocess.run(
        [sys.executable, str(CODEGEN), "--check"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or proc.stdout)
        return proc.returncode

    forbidden = extract_forbidden_literals(GENERATED)
    allowed = load_allowlist()
    hits = scan_files(forbidden)
    fail = 0
    for rel, line_no, literal, _ in hits:
        if (rel, literal) in allowed:
            continue
        print(
            f"FAIL: raw magic {literal} (token-owned) in {rel}:{line_no} "
            f"— use generated HiFiTokens.*",
            file=sys.stderr,
        )
        fail = 1

    if fail:
        print(
            f"NOTE: allowlist format: '<path> <literal>' per line in {ALLOW}",
            file=sys.stderr,
        )
        return 1

    print(f"magic_numbers.py: OK ({len(forbidden)} token literals derived)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
