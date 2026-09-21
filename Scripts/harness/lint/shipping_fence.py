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
    ROOT / "Lumina" / "Develop" / "Lab" / "RawBackendBenchmarkRunner.swift",
    ROOT / "Lumina" / "Views" / "Workspace" / "WorkbenchCapture.swift",
)

FENCE = re.compile(r"#if\s+!LUMINA_SHIPPING_APP\b")
APP = ROOT / "Lumina" / "LuminaApp.swift"
RELEASE_CONFIGS = {
    "Lumina": "A1000001000000000000000F",
    "LuminaPlayground": "A6000001000000000000000F",
}
HARNESS_CALL = re.compile(
    r"(WorkbenchCapture|RawHarnessRunner|RamTierHarnessRunner|P0EditHarnessRunner|P0EditLiveRunner|RawBackendBenchmarkRunner)\."
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
    pbx_text = pbx.read_text(encoding="utf-8")
    for target, config_id in RELEASE_CONFIGS.items():
        match = re.search(
            rf"{config_id} /\* Release \*/ = \{{(?P<body>.*?)\n\t\t\}};",
            pbx_text,
            re.DOTALL,
        )
        if match is None:
            print(f"FAIL: missing {target} Release build configuration", file=sys.stderr)
            fail = 1
        elif "LUMINA_SHIPPING_APP" not in match.group("body"):
            print(
                f"FAIL: {target} Release missing LUMINA_SHIPPING_APP flag",
                file=sys.stderr,
            )
            fail = 1

    if fail:
        return 1
    print("shipping_fence: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
