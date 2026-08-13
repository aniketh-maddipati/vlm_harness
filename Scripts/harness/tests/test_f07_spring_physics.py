#!/usr/bin/env python3
"""F07.4–F07.6 spring physics seal (SPIKE B).

BUILD_LOG records F07.4 dead-stop drift at sealed ε — test module restores the gate;
when LuminaSpring sources are absent the seal is UNMEASURED and the step is skipped (exit 0)
so missing-file does not mask an honest FAIL once sources land.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPRING_SWIFT = ROOT / "Lumina" / "Design" / "LuminaSpring.swift"
SPRING_PY = ROOT / "Scripts" / "harness" / "physics" / "lumina_spring.py"


def main() -> int:
    if not SPRING_SWIFT.is_file() or not SPRING_PY.is_file():
        print(
            "SKIP: spring_physics_f07 — LuminaSpring sources absent; SPIKE B seal UNMEASURED",
            file=sys.stderr,
        )
        return 0

    # Delegate to physics mirror when sources exist (F07.4 may FAIL per BUILD_LOG drift).
    from physics.lumina_spring import run_f07_gates  # type: ignore[import-not-found]

    return run_f07_gates(ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
