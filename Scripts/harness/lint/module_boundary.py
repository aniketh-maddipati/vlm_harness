#!/usr/bin/env python3
"""Import-boundary lint — keep Core models free of UI/GPU frameworks."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

CORE_DIRS = (
    ROOT / "Lumina" / "Models",
    ROOT / "Lumina" / "Core",
    ROOT / "Lumina" / "Persistence",
)

FORBIDDEN_IN_CORE = frozenset(
    {
        "SwiftUI",
        "AppKit",
        "Metal",
        "MetalKit",
        "CoreImage",
        "Vision",
        "SQLite3",
    }
)

IMPORT = re.compile(r"^\s*import\s+(\w+)")


def main() -> int:
    fail = 0
    for root in CORE_DIRS:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            for line in path.read_text(encoding="utf-8").splitlines():
                match = IMPORT.match(line)
                if not match:
                    continue
                module = match.group(1)
                if module in FORBIDDEN_IN_CORE:
                    print(
                        f"FAIL: {rel} imports {module} — move adapter to Services/Views",
                        file=sys.stderr,
                    )
                    fail = 1
    if fail:
        return 1
    print("module_boundary: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
