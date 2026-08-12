"""Budget breach reporting (F04.7) — delete or demote only; never other remedies."""
from __future__ import annotations

import sys
from typing import TextIO


def slowest_test_rows(results: list[dict]) -> list[dict]:
    """Manifest test ids sorted by measured ms descending."""
    return sorted(results, key=lambda r: r.get("ms", 0), reverse=True)


def budget_breach_lines(
    lane: str,
    elapsed_ms: int,
    budget_ms: int,
    results: list[dict],
) -> list[str]:
    lines = [
        f"BUDGET BREACH: {lane.upper()} {elapsed_ms}ms > {budget_ms}ms ceiling",
        "Slowest manifest test ids (measured ms, descending):",
    ]
    for row in slowest_test_rows(results):
        lines.append(f"  {row.get('step', '?')}: {row.get('ms', 0)}ms")
    lines.append("delete or demote")
    return lines


def emit_budget_breach(
    lane: str,
    elapsed_ms: int,
    budget_ms: int,
    results: list[dict],
    *,
    stream: TextIO = sys.stderr,
) -> None:
    for line in budget_breach_lines(lane, elapsed_ms, budget_ms, results):
        print(line, file=stream)
