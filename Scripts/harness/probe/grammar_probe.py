"""Shared grammar snapshot extraction for oracle ↔ Swift-machine parity (F02.5)."""
from __future__ import annotations

from typing import Any


def focus_index(probe_state: dict[str, Any]) -> int:
    fid = probe_state["focus"]["assetId"]
    ids = [r["id"] for r in probe_state["records"]]
    return ids.index(fid) if fid in ids else 0


def extract_grammar(probe_state: dict[str, Any]) -> dict[str, Any]:
    """Grammar-relevant slice of Probe v2 state — comparable across oracle and machine."""
    records = probe_state["records"]
    marks = [probe_state["marks"][r["id"]] for r in records]
    st = probe_state["staging"]
    holds = probe_state.get("activeHolds") or []
    if isinstance(holds, set):
        holds = sorted(holds)
    return {
        "focusIndex": focus_index(probe_state),
        "marks": marks,
        "staging": {
            "active": bool(st["active"]),
            "ring": st["ring"],
            "scopeCount": int(st["scopeCount"]),
            "excludedCount": int(st["excludedCount"]),
            "bannerCount": int(st["bannerCount"]),
            "headerCount": int(st["headerCount"]),
            "receiptCount": int(st["receiptCount"]),
            "returnReleaseArmed": bool(st["returnReleaseArmed"]),
        },
        "armedControl": probe_state["focus"].get("armedControl"),
        "undoDepth": int(probe_state.get("undoDepth") or 0),
        "activeHolds": sorted(holds),
        "valueEchoPresent": bool(probe_state.get("valueEchoPresent")),
    }


def grammar_diff(oracle: dict[str, Any], machine: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    if oracle != machine:
        for key in sorted(set(oracle) | set(machine)):
            if oracle.get(key) != machine.get(key):
                lines.append(f"  {key}: oracle={oracle.get(key)!r} machine={machine.get(key)!r}")
    return lines
