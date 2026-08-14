#!/usr/bin/env python3
"""Lane test inventory + vacuous-green guard (F1)."""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

MANIFEST_PATH = Path(__file__).resolve().parent / "manifests.json"


def load_manifest(path: Path = MANIFEST_PATH) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    for lane, definition in manifest["lanes"].items():
        ids = [test["id"] for test in definition["tests"]]
        duplicates = sorted(
            test_id for test_id, count in Counter(ids).items() if count > 1
        )
        if duplicates:
            raise ValueError(f"{lane} manifest contains duplicate test ids: {duplicates}")
    return manifest


def expected_ids(lane: str, manifest: dict[str, Any] | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    return [t["id"] for t in manifest["lanes"][lane]["tests"]]


def expected_app_coupled_ids(lane: str, manifest: dict[str, Any] | None = None) -> list[str]:
    manifest = manifest or load_manifest()
    return [t["id"] for t in manifest["lanes"][lane]["tests"] if t["kind"] == "app-coupled"]


def evaluate_inventory(
    lane: str,
    executed_ids: list[str],
    *,
    manifest: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Compare executed test IDs to the lane manifest.

    Returns verdict in {PASS, FAIL, INCOMPLETE} plus counts.
    Vacuous-green: zero app-coupled executed when any were expected → INCOMPLETE.
    Missing any expected id → INCOMPLETE.
    Extra ids are allowed (reported) but do not fail.
    """
    manifest = manifest or load_manifest()
    expected = expected_ids(lane, manifest)
    expected_app = expected_app_coupled_ids(lane, manifest)
    executed = list(executed_ids)
    missing = [i for i in expected if i not in executed]
    executed_app = [
        i
        for i in executed
        if i in expected_app
        or any(
            t["id"] == i and t["kind"] == "app-coupled"
            for t in manifest["lanes"][lane]["tests"]
        )
    ]
    # Count app-coupled only from those that were both expected and executed.
    app_executed_count = len([i for i in expected_app if i in executed])
    orchestration_executed = len(executed) - app_executed_count

    verdict = "PASS"
    reasons: list[str] = []
    if missing:
        verdict = "INCOMPLETE"
        reasons.append(f"missing {len(missing)} manifest test(s): {missing}")
    if expected_app and app_executed_count == 0:
        verdict = "INCOMPLETE"
        reasons.append(
            f"vacuous-green guard: 0 app-coupled tests executed; manifest expects {len(expected_app)}"
        )
    elif expected_app and app_executed_count < len(expected_app):
        verdict = "INCOMPLETE"
        reasons.append(
            f"app-coupled shortfall: {app_executed_count}/{len(expected_app)}"
        )

    return {
        "lane": lane,
        "verdict": verdict,
        "expected_count": len(expected),
        "executed_count": len(executed),
        "expected_app_coupled": len(expected_app),
        "executed_app_coupled": app_executed_count,
        "executed_orchestration": orchestration_executed,
        "missing": missing,
        "extra": [i for i in executed if i not in expected],
        "reasons": reasons,
    }


def format_lane_summary(
    lane: str,
    status: str,
    elapsed_ms: int,
    inventory: dict[str, Any],
) -> str:
    """Human line that cannot hide zero app tests behind a bare PASS."""
    app = inventory.get("executed_app_coupled", 0)
    orch = inventory.get("executed_orchestration", 0)
    exp_app = inventory.get("expected_app_coupled", 0)
    return (
        f"=== {lane.upper()} {status} in {elapsed_ms}ms "
        f"({app} app tests executed / {exp_app} expected; {orch} orchestration)"
    )
