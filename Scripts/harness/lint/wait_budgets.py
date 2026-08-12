#!/usr/bin/env python3
"""wait_budgets — UITestWait chains must stay far below P0Fast 180 s allowance (F04.4)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
UITEST_WAIT = ROOT / "LuminaUITests" / "Support" / "UITestWait.swift"
PROBE_WAIT = ROOT / "LuminaUITests" / "Support" / "XCUIApplication+Probe.swift"
UI_TESTS = ROOT / "LuminaUITests"
P0_FAST_ALLOWANCE = 180.0
FRACTION_CEILING = 0.5  # no single budget or legal chain may exceed half the allowance


def parse_budgets(text: str) -> dict[str, float]:
    budgets: dict[str, float] = {}
    for match in re.finditer(r"static let (\w+):\s*TimeInterval\s*=\s*(\d+(?:\.\d+)?)", text):
        budgets[match.group(1)] = float(match.group(2))
    allowance = re.search(
        r"static let p0FastMaximumTestExecutionTimeAllowance:\s*TimeInterval\s*=\s*(\d+(?:\.\d+)?)",
        text,
    )
    if allowance:
        budgets["p0FastMaximumTestExecutionTimeAllowance"] = float(allowance.group(1))
    return budgets


def main() -> int:
    failures: list[str] = []
    if not UITEST_WAIT.is_file():
        print(f"FAIL: missing {UITEST_WAIT.relative_to(ROOT)}", file=sys.stderr)
        return 1

    text = UITEST_WAIT.read_text(encoding="utf-8")
    budgets = parse_budgets(text)
    required = ("launchAttempt", "autoOpenNavigation", "recentRow", "transition")
    for name in required:
        if name not in budgets:
            failures.append(f"UITestWait missing named budget `{name}`")

    allowance = budgets.get("p0FastMaximumTestExecutionTimeAllowance", P0_FAST_ALLOWANCE)
    if allowance != P0_FAST_ALLOWANCE:
        failures.append(
            f"p0FastMaximumTestExecutionTimeAllowance must be {P0_FAST_ALLOWANCE}, got {allowance}"
        )

    launch = budgets.get("launchAttempt", 0)
    auto_open = budgets.get("autoOpenNavigation", 0)
    recent = budgets.get("recentRow", 0)
    transition = budgets.get("transition", 0)

    worst_deterministic = launch * 2 + auto_open
    worst_recent_row = launch * 2 + recent + transition
    half = allowance * FRACTION_CEILING

    for label, chain in (
        ("worstDeterministicWaitChain", worst_deterministic),
        ("worstRecentRowWaitChain", worst_recent_row),
    ):
        if chain >= allowance:
            failures.append(f"{label}={chain}s must stay below {allowance}s P0Fast allowance")
        if chain >= half:
            failures.append(f"{label}={chain}s must stay below half allowance ({half}s)")

    for name in required:
        value = budgets.get(name, 0)
        if value >= half:
            failures.append(f"UITestWait.{name}={value}s must stay below half allowance ({half}s)")

    probe_text = PROBE_WAIT.read_text(encoding="utf-8") if PROBE_WAIT.is_file() else ""
    if "ProbePolling.waitUntil" not in probe_text:
        failures.append("waitForProbe must delegate to ProbePolling.waitUntil (nil unless predicate matched)")

    false_success = re.compile(r"waitForProbe\([^)]*\)\s*\?\?\s*")
    for path in sorted(UI_TESTS.rglob("*.swift")):
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if false_success.search(line):
                rel = path.relative_to(ROOT)
                failures.append(
                    f"{rel}:{line_no}: waitForProbe must not fall back with `??` — nil means failure"
                )

    if failures:
        print("FAIL: wait_budgets — probe wait budgets or false-success fallback", file=sys.stderr)
        for msg in failures:
            print(f"  {msg}", file=sys.stderr)
        return 1

    print(
        "wait_budgets: OK "
        f"(deterministic≤{worst_deterministic}s recent-row≤{worst_recent_row}s allowance={allowance}s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
