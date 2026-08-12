#!/usr/bin/env python3
"""leaf_only_ids — container accessibilityIdentifier with identified children fails (F03.3)."""
from __future__ import annotations

import sys
from pathlib import Path

from probe_contract import (
    P0_VIEW_DIR,
    ROOT,
    appkit_duplicate_accessibility,
    swiftui_leaf_violations,
)


def main() -> int:
    violations: list[str] = []
    if P0_VIEW_DIR.is_dir():
        for path in sorted(P0_VIEW_DIR.rglob("*.swift")):
            source = path.read_text(encoding="utf-8")
            rel = path.relative_to(ROOT).as_posix()
            violations.extend(swiftui_leaf_violations(source, rel))
            violations.extend(appkit_duplicate_accessibility(source, rel))

    if violations:
        for msg in violations:
            print(f"FAIL: leaf_only_ids: {msg}", file=sys.stderr)
        return 1

    print("leaf_only_ids: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
