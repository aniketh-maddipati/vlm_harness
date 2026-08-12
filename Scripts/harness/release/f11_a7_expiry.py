#!/usr/bin/env python3
"""F11.6 — A7 beta diagnostics expiry gate (D45 / A7).

FAIL when marketingVersion >= 1.0 and embedded manifest still records betaDiagnostics.
Expiry must be written into the socket so 1.0 cannot ship with A7 path by neglect.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOCKET = ROOT / "Lumina" / "Core" / "BetaDiagnosticsSocket.swift"


def parse_version(version: str) -> tuple[int, int, int]:
    parts = version.strip().split(".")
    nums = [int(p) for p in parts if p.isdigit()]
    while len(nums) < 3:
        nums.append(0)
    return nums[0], nums[1], nums[2]


def version_gte(a: str, b: str) -> bool:
    return parse_version(a) >= parse_version(b)


def socket_active() -> bool:
    if not SOCKET.is_file():
        return False
    text = SOCKET.read_text(encoding="utf-8")
    if "activeKind: String? = nil" in text:
        return False
    return bool(re.search(r"activeKind:\s*String\?\s*=\s*\"[^\"]+\"", text))


def check_manifest(manifest: dict) -> tuple[bool, list[str]]:
    errors: list[str] = []
    marketing = str(manifest.get("marketingVersion", "0"))
    beta = manifest.get("betaDiagnostics")
    if beta and version_gte(marketing, "1.0"):
        errors.append(
            f"marketingVersion {marketing} >= 1.0 but betaDiagnostics still present: {beta!r}"
        )
    if beta:
        expires = beta.get("expiresAtMarketingVersion")
        if expires != "1.0":
            errors.append(f"betaDiagnostics.expiresAtMarketingVersion must be '1.0', got {expires!r}")
    if socket_active() and not beta:
        errors.append("BetaDiagnosticsSocket active in source but manifest omits betaDiagnostics")
    return len(errors) == 0, errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, help="JSON file or omit to use --app")
    parser.add_argument("--app", type=Path, help="Built Lumina.app")
    parser.add_argument(
        "--simulate-marketing-version",
        help="Override marketingVersion for dry-run (e.g. 1.0 to prove gate)",
    )
    args = parser.parse_args(argv)

    if args.manifest:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    elif args.app:
        if sys.platform != "darwin":
            print("F11.6 A7 expiry: PLATFORM-UNAVAILABLE (macOS only)")
            return 2
        path = args.app / "Contents" / "Resources" / "LuminaBuildManifest.json"
        if not path.is_file():
            print(f"F11.6: FAIL — no manifest in app: {path}", file=sys.stderr)
            return 1
        manifest = json.loads(path.read_text(encoding="utf-8"))
    else:
        # Source-only check for FAST lane (wave build, no app).
        manifest = {
            "marketingVersion": args.simulate_marketing_version or "0.1.0",
            "betaDiagnostics": None,
        }
        if socket_active():
            manifest["betaDiagnostics"] = {
                "kind": "testflight_crash_reporting",
                "path": str(SOCKET.relative_to(ROOT)),
                "expiresAtMarketingVersion": "1.0",
            }

    if args.simulate_marketing_version:
        manifest = dict(manifest)
        manifest["marketingVersion"] = args.simulate_marketing_version

    ok, errors = check_manifest(manifest)
    print("=== F11.6 A7 expiry ===")
    print(json.dumps(manifest, indent=2, sort_keys=True))
    if ok:
        print("\nF11.6: PASS")
        return 0
    print("\nF11.6: FAIL", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
