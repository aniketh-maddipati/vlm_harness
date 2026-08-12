#!/usr/bin/env python3
"""F11.2 — Zero outgoing network on app paths (Release artifact).

Scope: Lumina.app entitlements and linked networking frameworks on the app's own
binary paths only. Does NOT cover OS-level crash reporters or TestFlight telemetry
(CONFLICT 4 / A7 — out of scope for this check).

macOS only.
"""
from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

NETWORK_ENTITLEMENT_KEYS = (
    "com.apple.security.network.client",
    "com.apple.security.network.server",
    "com.apple.security.network.client.local-network",
)

NETWORK_FRAMEWORKS = (
    "CFNetwork",
    "Network",
    "NetworkExtension",
)


def find_release_app(explicit: Path | None) -> Path | None:
    if explicit and explicit.is_dir():
        return explicit
    candidate = ROOT / "build" / "Release" / "Lumina.app"
    if (candidate / "Contents" / "MacOS" / "Lumina").is_file():
        return candidate
    return None


def read_entitlements(app: Path) -> tuple[str, dict | None, str]:
    proc = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(app)],
        capture_output=True,
    )
    if proc.returncode != 0:
        return "PLATFORM-UNAVAILABLE", None, proc.stderr.decode("utf-8", errors="replace").strip()
    if not proc.stdout.strip():
        return "OK", {}, "no entitlements blob (empty)"
    try:
        data = plistlib.loads(proc.stdout)
    except plistlib.InvalidFileException as exc:
        return "FAIL", None, f"invalid entitlements plist: {exc}"
    if not isinstance(data, dict):
        return "OK", {}, "no entitlements dictionary"
    return "OK", data, "entitlements read"


def otool_network_frameworks(app: Path) -> tuple[str, list[str], str]:
    binary = app / "Contents" / "MacOS" / "Lumina"
    proc = subprocess.run(["otool", "-L", str(binary)], capture_output=True, text=True)
    if proc.returncode != 0:
        return "PLATFORM-UNAVAILABLE", [], proc.stderr.strip()
    hits: list[str] = []
    for line in proc.stdout.splitlines()[1:]:  # skip self
        line = line.strip()
        if not line:
            continue
        lib = line.split()[0]
        for fw in NETWORK_FRAMEWORKS:
            if f"/{fw}.framework/" in lib or lib.endswith(f"{fw}.framework/{fw}"):
                hits.append(lib)
                break
    return "OK", hits, proc.stdout.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("F11.2 zero network: PLATFORM-UNAVAILABLE (macOS only)")
        return 2

    print("=== F11.2 zero network (app paths only) ===")
    print(
        "Scope note: this check covers Lumina.app entitlements and the app's linked "
        "networking frameworks only — not OS-level crash reporters or TestFlight "
        "telemetry (CONFLICT 4 / A7)."
    )

    app = find_release_app(args.app)
    if app is None:
        print("\nPLATFORM-UNAVAILABLE: Release Lumina.app not found — build Release first.")
        return 2

    print(f"\nApp: {app}")

    ent_status, entitlements, ent_detail = read_entitlements(app)
    print(f"\n--- Entitlements ({ent_detail}) ---")
    if ent_status == "PLATFORM-UNAVAILABLE":
        print(f"PLATFORM-UNAVAILABLE: {ent_detail}")
        return 2

    ent_fail = False
    for key in NETWORK_ENTITLEMENT_KEYS:
        val = entitlements.get(key) if entitlements else None
        if val:
            print(f"  [FAIL] {key} = {val!r}")
            ent_fail = True
        else:
            print(f"  [PASS] {key} absent")

    otool_status, fw_hits, otool_raw = otool_network_frameworks(app)
    print("\n--- Linked networking frameworks (otool -L) ---")
    if otool_status == "PLATFORM-UNAVAILABLE":
        print(f"PLATFORM-UNAVAILABLE: {otool_raw}")
        return 2
    if fw_hits:
        for hit in fw_hits:
            print(f"  [FAIL] {hit}")
    else:
        print("  [PASS] no CFNetwork / Network / NetworkExtension on app binary")

    if ent_fail or fw_hits:
        print("\nF11.2: FAIL")
        return 1
    print("\nF11.2: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
