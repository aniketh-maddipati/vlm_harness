#!/usr/bin/env python3
"""Copy-table lint — frozen rows, banned words, A5 Adapt banner shape."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "design" / "copy-contract.txt"

BANNED = (
    "sync",
    "preset",
    "copy settings",
    "catalog",
    "smart",
    "analyze",
    "generate",
    "magic",
)

REQUIRED_VERBATIM = (
    "Re-pressing the mark on a marked frame clears it to unreviewed, in place. Decision keys never autorepeat.",
    "P keeps · X rejects · same key again clears",
    "After ⇧⏎ stages, ⏎ cannot commit until Return is physically released. One held press can never stage-and-commit.",
    "Crop · ⏎ applies · Esc cancels",
    "body not yet supported",
    "Sample shoot — yours replaces it",
    "sharpness not final",
)


def shippable_rows(text: str) -> list[str]:
    rows = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("##"):
            continue
        rows.append(line)
    return rows


def main() -> int:
    if not CONTRACT.is_file():
        print(f"FAIL: missing {CONTRACT}", file=sys.stderr)
        return 1
    text = CONTRACT.read_text(encoding="utf-8")
    fail = 0
    for needle in REQUIRED_VERBATIM:
        if needle not in text:
            print(f"FAIL: copy-contract missing verbatim: {needle}", file=sys.stderr)
            fail = 1
    # A5: Adapt word must appear in a banner row; compressed form with count.
    if not re.search(r"Adapt → \d+", text):
        print("FAIL: A5 Adapt banner form missing (Adapt → N)", file=sys.stderr)
        fail = 1
    for row in shippable_rows(text):
        # Strip tags like [○][P+V]
        body = re.sub(r"^\[[^\]]+\]", "", row)
        body = re.sub(r"^\[[^\]]+\]", "", body).strip()
        lower = body.lower()
        for word in BANNED:
            if word in lower:
                # Allow NOTES section commentary only — shippable rows already filtered.
                print(f"FAIL: banned '{word}' in copy row: {row}", file=sys.stderr)
                fail = 1
        if re.search(r"(^|[^a-z])auto([^a-z]|$)", lower) and "develop" not in lower:
            print(f"FAIL: banned Auto in copy row: {row}", file=sys.stderr)
            fail = 1
        if "(hover)" in body:
            print(f"FAIL: superseded hover parenthetical in copy row: {row}", file=sys.stderr)
            fail = 1
    # Lightroom exactly once in shippable body (sovereignty PL).
    body_only = "\n".join(shippable_rows(text))
    lr = len(re.findall(r"Lightroom", body_only))
    if lr != 1:
        print(f"FAIL: Lightroom must appear exactly once in shippable rows (found {lr})", file=sys.stderr)
        fail = 1
    if fail:
        return 1
    print("copy_table_lint.py: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
