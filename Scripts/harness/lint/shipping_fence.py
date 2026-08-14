#!/usr/bin/env python3
"""Release shipping fence — headless harness must not compile into LUMINA_SHIPPING_APP."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

SHIPPING_ONLY_SOURCES = (
    ROOT / "Lumina" / "Develop" / "Lab" / "RawHarnessRunner.swift",
    ROOT / "Lumina" / "Develop" / "Lab" / "RamTierHarnessRunner.swift",
    ROOT / "Lumina" / "Develop" / "Lab" / "P0EditHarnessRunner.swift",
    ROOT / "Lumina" / "Develop" / "Lab" / "P0EditLiveRunner.swift",
    ROOT / "Lumina" / "Views" / "Workspace" / "WorkbenchCapture.swift",
)

FENCE = re.compile(r"#if\s+!LUMINA_SHIPPING_APP\b")
APP = ROOT / "Lumina" / "LuminaApp.swift"
HARNESS_CALL = re.compile(
    r"(WorkbenchCapture|RawHarnessRunner|RamTierHarnessRunner|P0EditHarnessRunner|P0EditLiveRunner)\."
)


def first_code_line(text: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("//"):
            return stripped
    return ""


def main() -> int:
    fail = 0
    for path in SHIPPING_ONLY_SOURCES:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            print(f"FAIL: missing shipping-fenced source {rel}", file=sys.stderr)
            fail = 1
            continue
        text = path.read_text(encoding="utf-8")
        if not FENCE.search(text):
            print(f"FAIL: {rel} missing #if !LUMINA_SHIPPING_APP fence", file=sys.stderr)
            fail = 1
            continue
        if not text.rstrip().endswith("#endif"):
            print(f"FAIL: {rel} must end with #endif for shipping fence", file=sys.stderr)
            fail = 1

    if APP.is_file():
        text = APP.read_text(encoding="utf-8")
        for match in HARNESS_CALL.finditer(text):
            prefix = text[: match.start()]
            if "#if !LUMINA_SHIPPING_APP" not in prefix.split("#endif")[-1]:
                print(
                    f"FAIL: LuminaApp.swift references {match.group(1)} outside "
                    "#if !LUMINA_SHIPPING_APP",
                    file=sys.stderr,
                )
                fail = 1

    pbx = ROOT / "Lumina.xcodeproj" / "project.pbxproj"
    if "LUMINA_SHIPPING_APP" not in pbx.read_text(encoding="utf-8"):
        print("FAIL: Release Lumina target missing LUMINA_SHIPPING_APP flag", file=sys.stderr)
        fail = 1

    if fail:
        return 1
    print("shipping_fence: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
