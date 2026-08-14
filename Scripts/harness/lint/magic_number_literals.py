#!/usr/bin/env python3
"""Derive forbidden UI literals from DesignTokens/HiFiTokens.generated.swift."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GENERATED = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"

ASSIGNMENT = re.compile(
    r"=\s*(-?\d+(?:\.\d+)?(?:e-?\d+)?)\s*(?://|$)"
)
ARRAY_LITERAL = re.compile(r"\[([^\]]+)\]")

# 0/1 are universal sentinels; 2–9 are treated as small array indices (W1 rule).
EXCLUDED_INTS = frozenset(range(0, 10))


def _parse_numeric(raw: str) -> float | None:
    try:
        return float(raw)
    except ValueError:
        return None


def _canonical_forms(value: float) -> set[str]:
    forms: set[str] = set()
    if abs(value - round(value)) < 1e-12:
        iv = int(round(value))
        forms.add(str(iv))
        forms.add(f"{iv}.0")
    else:
        text = f"{value:.6f}".rstrip("0").rstrip(".")
        forms.add(text)
        # Always include 0-prefixed decimals; skip bare ".N" — it prefix-matches longer literals.
        if not text.startswith("0.") and "." in text:
            forms.add(f"0.{text.split('.', 1)[1]}")
        elif text.startswith("0."):
            forms.add(text)
    return forms


def extract_forbidden_literals(generated_path: Path = GENERATED) -> dict[str, set[str]]:
    """Return map canonical-literal-string -> set of token labels (for diagnostics)."""
    text = generated_path.read_text(encoding="utf-8")
    by_literal: dict[str, set[str]] = {}

    def add(value: float, label: str) -> None:
        if value in (0.0, 1.0):
            return
        if abs(value - round(value)) < 1e-12 and int(round(value)) in EXCLUDED_INTS:
            return
        for form in _canonical_forms(value):
            by_literal.setdefault(form, set()).add(label)

    for match in ASSIGNMENT.finditer(text):
        raw = match.group(1)
        value = _parse_numeric(raw)
        if value is None:
            continue
        line = text[: match.start()].splitlines()[-1]
        label = line.strip().split()[-1] if line.strip() else raw
        add(value, label)

    for match in ARRAY_LITERAL.finditer(text):
        for part in match.group(1).split(","):
            part = part.strip()
            if re.fullmatch(r"-?\d+(?:\.\d+)?", part):
                value = _parse_numeric(part)
                if value is not None:
                    add(value, f"array:{part}")

    return by_literal


def literal_in_line(literal: str, line: str) -> bool:
    """Match a forbidden literal without hex/substring false positives."""
    pattern = rf"(?<![0-9.]){re.escape(literal)}(?![0-9.eE])"
    return re.search(pattern, line) is not None


def compile_literal_pattern(literals: list[str]) -> re.Pattern[str]:
    """Compile one matcher for a set of literals, preferring longest forms."""
    alternatives = "|".join(
        re.escape(literal) for literal in sorted(literals, key=len, reverse=True)
    )
    if not alternatives:
        return re.compile(r"(?!x)x")
    return re.compile(rf"(?<![0-9.])(?:{alternatives})(?![0-9.eE])")


def line_skipped(line: str) -> bool:
    if re.match(r"\s*//", line):
        return True
    if re.search(r"HiFiTokens|LuminaTokens|CopyContract", line):
        return True
    if re.search(r"0x[0-9a-fA-F]+", line):
        return True
    return False


def index_literal_skipped(line: str, literal: str) -> bool:
    """Skip `[N]` subscripts when N is a small index excluded from the set."""
    if not literal.isdigit():
        return False
    n = int(literal)
    if n not in EXCLUDED_INTS:
        return False
    return re.search(rf"\[\s*{n}\s*\]", line) is not None
