#!/usr/bin/env python3
"""F07.4–F07.6 spring physics seal (SPIKE B).

Runs against sealed params in design/tokens.yaml §motion only — tolerances from the seal,
never invented by the test. When seal keys are absent, exits 0 STUB (SPIKE B owner).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "Scripts" / "harness"
SPRING_SWIFT = ROOT / "Lumina" / "Design" / "LuminaSpring.swift"
SPRING_PY = HARNESS / "physics" / "lumina_spring.py"


def main() -> int:
    if not SPRING_SWIFT.is_file() or not SPRING_PY.is_file():
        print(
            "SKIP: spring_physics_f07 — LuminaSpring sources absent; SPIKE B UNMEASURED",
            file=sys.stderr,
        )
        return 0

    sys.path.insert(0, str(HARNESS))
    from physics.lumina_spring import load_motion_seal, run_f07_gates  # noqa: WPS433

    if load_motion_seal(ROOT) is None:
        print(
            "STUB: spring_physics_f07 — motion seal absent from tokens.yaml §motion; "
            "F07.4–F07.6 owned by SPIKE B",
            file=sys.stderr,
        )
        return 0

    return run_f07_gates(ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
