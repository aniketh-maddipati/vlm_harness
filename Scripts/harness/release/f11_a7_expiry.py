#!/usr/bin/env python3
"""F11.6 — betaDiagnostics null assertion (D45 / A13).

FAIL when any wave/beta manifest records non-null betaDiagnostics, or when
BetaDiagnosticsSocket.activeKind is non-nil in source. A7 (TestFlight reporter)
was withdrawn — R-9.1 applies in full to beta, wave, and launch builds.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOCKET = ROOT / "Lumina" / "Core" / "BetaDiagnosticsSocket.swift"


def socket_active() -> bool:
    if not SOCKET.is_file():
        return False
    text = SOCKET.read_text(encoding="utf-8")
    if "activeKind: String? = nil" in text:
        return False
    return bool(re.search(r"activeKind:\s*String\?\s*=\s*\"[^\"]+\"", text))


def check_manifest(manifest: dict) -> tuple[bool, list[str]]:
    errors: list[str] = []
    beta = manifest.get("betaDiagnostics")
    if beta is not None:
        marketing = str(manifest.get("marketingVersion", "0"))
        errors.append(
            f"betaDiagnostics must be null on wave/beta builds (D45/A13); "
            f"marketingVersion={marketing!r} got {beta!r}"
        )
    if socket_active():
        errors.append(
            "BetaDiagnosticsSocket.activeKind must be nil (A7 withdrawn A13); "
            "socket is active in source"
        )
    return len(errors) == 0, errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, help="JSON file or omit to use --app")
    parser.add_argument("--app", type=Path, help="Built Lumina.app")
    parser.add_argument(
        "--simulate-marketing-version",
        help="Override marketingVersion for dry-run",
    )
    args = parser.parse_args(argv)

    if args.manifest:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    elif args.app:
        if sys.platform != "darwin":
            print("F11.6 betaDiagnostics null: PLATFORM-UNAVAILABLE (macOS only)")
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
    print("=== F11.6 betaDiagnostics null (D45/A13) ===")
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
