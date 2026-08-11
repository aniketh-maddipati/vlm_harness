#!/usr/bin/env python3
"""Token lint — yaml present, schema shape, codegen freshness."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts" / "harness" / "codegen"))

from tokens_codegen import check_fresh, load_tokens  # noqa: E402

REQUIRED_SECTIONS = (
    "ring",
    "color",
    "grid",
    "type",
    "motion",
    "layout",
    "hit",
    "grammar",
)


def main() -> int:
    path = ROOT / "design" / "tokens.yaml"
    if not path.is_file():
        print("FAIL: missing design/tokens.yaml", file=sys.stderr)
        return 1
    data, raw = load_tokens(path)
    fail = 0
    for section in REQUIRED_SECTIONS:
        if section not in data:
            print(f"FAIL: tokens.yaml missing section '{section}'", file=sys.stderr)
            fail = 1
    if data.get("version") is None:
        print("FAIL: tokens.yaml missing version", file=sys.stderr)
        fail = 1
    motion = data.get("motion") or {}
    for key in ("warm_in_crossfade", "fidelity_crossfade", "docked_chip_grab"):
        if key not in motion:
            print(f"FAIL: motion.{key} missing", file=sys.stderr)
            fail = 1
    gen = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"
    if check_fresh(data, raw, gen) != 0:
        fail = 1
    if fail:
        return 1
    print("token_lint.py: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
