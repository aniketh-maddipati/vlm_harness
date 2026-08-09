#!/usr/bin/env python3
"""A1 invariant — banner, header, and receipt share ONE count source."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))

from copy_contract_loader import load_contract_strings  # noqa: E402


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def pass_(message: str) -> None:
    print(f"PASS: {message}")


# Mirror CopyContract formatting (keep in sync with StagingCopyContext.swift / CopyContract.swift)


def staged_header(scope: int, row: int, lane: str, excluded: int = 0, ring: str = "row") -> str:
    if excluded > 0:
        ring_label = f"row {row}" if ring == "row" else ring
        return f"STAGED · {ring_label} · {scope} selected · {excluded} excluded · ⏎ applies · Esc cancels"
    return (
        f"STAGED · row {row} · {lane} · {scope} selected · ⏎ applies · Esc cancels, nothing applied"
    )


def adapt_banner(scope: int, excluded: int = 0, ring: str = "row") -> str:
    if excluded > 0 and ring == "shoot":
        return f"Adapt → {scope} · {excluded} excluded ⏎ · ⇧⏎ shoot"
    if ring == "scene":
        return f"Adapt → {scope} ⏎ · ⇧⏎ scene · Esc"
    return f"Adapt → {scope} ⏎ · Esc"


def adapted_receipt(count: int) -> str:
    return f"Adapted → {count} · ⌘Z"


def committed_count(text: str) -> int | None:
    for prefix in ("Adapted → ", "Adapt → ", "Develop → "):
        if prefix in text:
            rest = text.split(prefix, 1)[1]
            digits = ""
            for ch in rest:
                if ch.isdigit():
                    digits += ch
                elif digits:
                    break
            return int(digits) if digits else None
    if " selected" in text:
        for segment in text.split("·"):
            segment = segment.strip()
            if segment.endswith(" selected"):
                return int(segment.split()[0])
    return None


def excluded_count(text: str) -> int | None:
    if " excluded" not in text:
        return None
    for segment in text.split("·"):
        segment = segment.strip()
        if " excluded" in segment:
            return int(segment.split()[0])
    return None


def validate(header: str, banner: str, receipt: str, scope: int, excluded: int = 0) -> bool:
    hc = committed_count(header)
    bc = committed_count(banner)
    rc = committed_count(receipt)
    if hc != scope or bc != scope or rc != scope:
        return False
    if excluded > 0:
        if excluded_count(header) != excluded:
            return False
        if excluded_count(banner) != excluded:
            return False
    return True


contract = load_contract_strings()
for required in [
    staged_header(4, 4, "18:17"),
    adapt_banner(4),
    adapted_receipt(4),
    staged_header(12, 4, "18:17", excluded=2, ring="scene"),
    adapt_banner(12, excluded=2, ring="shoot"),
]:
    if required not in contract:
        fail(f"Formatted copy missing from contract: {required}")

snap = dict(scope=4, row=4, lane="18:17", excluded=0)
header = staged_header(**snap)
banner = adapt_banner(snap["scope"])
receipt = adapted_receipt(snap["scope"])
if not validate(header, banner, receipt, snap["scope"]):
    fail("A1 row-scope invariant failed")

snap2 = dict(scope=12, row=4, lane="18:17", excluded=2, ring="scene")
header2 = staged_header(**snap2)
banner2 = adapt_banner(snap2["scope"], excluded=2, ring="shoot")
receipt2 = adapted_receipt(snap2["scope"])
if not validate(header2, banner2, receipt2, snap2["scope"], excluded=2):
    fail("A1 excluded-count invariant failed")

pass_("A1 invariant covers row scope and excluded-count formats")
print("A1 invariant test: all checks passed")
