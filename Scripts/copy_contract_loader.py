"""Shared loader for design/copy-contract.txt — used by Prompt-9 and A1 tests."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "design" / "copy-contract.txt"


def load_contract_strings() -> set[str]:
    text = CONTRACT_PATH.read_text(encoding="utf-8")
    strings: set[str] = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[[^\]]+\]\s+(.+)$", line)
        if m:
            strings.add(m.group(1).strip())
    return strings


def string_in_contract(value: str, contract: set[str]) -> bool:
    if value in contract:
        return True
    return any(value in entry for entry in contract)


def load_contract_lines() -> list[str]:
    return sorted(load_contract_strings())
