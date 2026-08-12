#!/usr/bin/env python3
"""flake_policy — test plans must not encode repetition or retry-on-failure (F04.6).

Reads TestPlans/*.xctestplan and fails when test repetition or retry-on-failure
appears. Quarantine tags must not appear anywhere in test plans.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
TEST_PLANS = ROOT / "TestPlans"

REPETITION_MODE_KEY = re.compile(r"testRepetitionMode", re.IGNORECASE)
MAX_REPETITIONS_KEY = re.compile(r"maximumTestRepetitions", re.IGNORECASE)
RETRY_KEY = re.compile(r"retry", re.IGNORECASE)
QUARANTINE = re.compile(r"quarantine", re.IGNORECASE)


def _path_str(parts: list[str]) -> str:
    return ".".join(parts) if parts else "(root)"


def _check_value(key: str, value: Any, path: list[str], plan_rel: str, failures: list[str]) -> None:
    key_l = key.lower()
    if RETRY_KEY.search(key) and "failure" in key_l:
        failures.append(
            f"{plan_rel} `{_path_str(path)}.{key}` — retry-on-failure key forbidden"
        )
    if key_l in {"runtestsuntilfailure", "testiterations", "testrepetitions"}:
        failures.append(
            f"{plan_rel} `{_path_str(path)}.{key}` — test repetition forbidden"
        )
    if REPETITION_MODE_KEY.search(key):
        if isinstance(value, str):
            mode = value.strip().lower()
            if mode and mode != "none":
                failures.append(
                    f"{plan_rel} `{_path_str(path)}.{key}={value!r}` — "
                    "testRepetitionMode must be absent or none"
                )
    if MAX_REPETITIONS_KEY.search(key):
        if isinstance(value, (int, float)) and value > 1:
            failures.append(
                f"{plan_rel} `{_path_str(path)}.{key}={value}` — "
                "maximumTestRepetitions must not exceed 1"
            )
        elif isinstance(value, str) and value.strip().isdigit() and int(value.strip()) > 1:
            failures.append(
                f"{plan_rel} `{_path_str(path)}.{key}={value}` — "
                "maximumTestRepetitions must not exceed 1"
            )


def _walk(node: Any, path: list[str], plan_rel: str, failures: list[str]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            _check_value(str(key), value, path, plan_rel, failures)
            if isinstance(value, str) and QUARANTINE.search(value):
                failures.append(
                    f"{plan_rel} `{_path_str(path)}.{key}={value!r}` — quarantine tag forbidden"
                )
            _walk(value, path + [str(key)], plan_rel, failures)
    elif isinstance(node, list):
        for idx, item in enumerate(node):
            if isinstance(item, str) and QUARANTINE.search(item):
                failures.append(
                    f"{plan_rel} `{_path_str(path)}[{idx}]={item!r}` — quarantine tag forbidden"
                )
            _walk(item, path + [f"[{idx}]"], plan_rel, failures)


def scan_plan(path: Path) -> list[str]:
    rel = path.relative_to(ROOT).as_posix()
    failures: list[str] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{rel}: invalid JSON — {exc}"]
    _walk(data, [], rel, failures)
    return failures


def main() -> int:
    if not TEST_PLANS.is_dir():
        print(f"FAIL: missing {TEST_PLANS.relative_to(ROOT)}", file=sys.stderr)
        return 1

    plans = sorted(TEST_PLANS.glob("*.xctestplan"))
    if not plans:
        print("FAIL: flake_policy — no TestPlans/*.xctestplan files", file=sys.stderr)
        return 1

    failures: list[str] = []
    for plan in plans:
        failures.extend(scan_plan(plan))

    if failures:
        print("FAIL: flake_policy — repetition/retry/quarantine forbidden in test plans", file=sys.stderr)
        for msg in failures:
            print(f"  {msg}", file=sys.stderr)
        return 1

    print("flake_policy: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
