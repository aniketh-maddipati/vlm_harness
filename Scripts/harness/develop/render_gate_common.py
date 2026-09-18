#!/usr/bin/env python3
"""Shared helpers for macOS progressive-render live gates."""
from __future__ import annotations

import json
import platform
from pathlib import Path
from typing import Any

THRESHOLDS = Path(__file__).with_name("render_thresholds.json")


def resolve_app(project_root: Path, derived_data: Path) -> Path:
    candidates = [
        derived_data / "Build" / "Products" / "Debug" / "Lumina.app",
        project_root / "DD" / "Build" / "Products" / "Debug" / "Lumina.app",
    ]
    for candidate in candidates:
        if candidate.is_dir():
            executable = candidate / "Contents" / "MacOS" / "Lumina"
            if executable.is_file():
                return executable
    raise RuntimeError(
        "built Debug Lumina.app missing; FULL must run xcode_compile before live render gates"
    )


def read_report(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"missing report {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"malformed report {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"report root must be an object: {path}")
    return value


def thresholds(section: str) -> dict[str, Any]:
    value = read_report(THRESHOLDS).get(section)
    if not isinstance(value, dict):
        raise RuntimeError(f"missing threshold section {section!r}")
    return value


def measured_ledger(gate: str, fixture: Path, metrics: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "mode": "measured",
        "gates_active": True,
        "gate": gate,
        "fixture_root": str(fixture),
        "host": {
            "machine": platform.machine(),
            "macOS": platform.mac_ver()[0],
        },
        "metrics": metrics,
    }


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
