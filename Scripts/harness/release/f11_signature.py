#!/usr/bin/env python3
"""F11.3 — Developer ID signing, notarization, and staple (Release artifact).

Verifies:
  - codesign --verify --deep --strict
  - spctl --assess --type execute
  - stapled notarization ticket (stapler validate)

Signed-but-unstapled fails. Missing Developer ID / notarization credentials →
PLATFORM-UNAVAILABLE for steps that cannot run, never PASS.

macOS only.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def find_release_app(explicit: Path | None) -> Path | None:
    if explicit and explicit.is_dir():
        return explicit
    candidate = ROOT / "build" / "Release" / "Lumina.app"
    if (candidate / "Contents" / "MacOS" / "Lumina").is_file():
        return candidate
    return None


def run_cmd(label: str, argv: list[str]) -> tuple[str, str]:
    proc = subprocess.run(argv, capture_output=True, text=True)
    out = (proc.stdout + proc.stderr).strip()
    if proc.returncode == 0:
        return "PASS", out or f"{label} OK"
    text = out.lower()
    if "no identity found" in text or "errsec" in text or "cannot be checked" in text:
        return "PLATFORM-UNAVAILABLE", out
    return "FAIL", out


def codesign_display(app: Path) -> str:
    proc = subprocess.run(
        ["codesign", "-dv", "--verbose=4", str(app)],
        capture_output=True,
        text=True,
    )
    return (proc.stdout + proc.stderr).strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("F11.3 signature: PLATFORM-UNAVAILABLE (macOS only)")
        return 2

    print("=== F11.3 Developer ID + notarization + staple ===")

    app = find_release_app(args.app)
    if app is None:
        print("PLATFORM-UNAVAILABLE: Release Lumina.app not found — build Release first.")
        return 2

    print(f"\nApp: {app}")
    print("\n--- codesign -dv (identity) ---")
    print(codesign_display(app))

    checks = [
        (
            "codesign --verify --deep --strict",
            ["codesign", "--verify", "--deep", "--strict", str(app)],
        ),
        (
            "spctl --assess --type execute",
            ["spctl", "--assess", "--type", "execute", str(app)],
        ),
        (
            "stapler validate (stapled ticket required)",
            ["xcrun", "stapler", "validate", str(app)],
        ),
    ]

    results: list[tuple[str, str, str]] = []
    for label, argv in checks:
        status, detail = run_cmd(label, argv)
        results.append((label, status, detail))
        print(f"\n--- {label} ---")
        print(f"  [{status}]")
        if detail:
            for line in detail.splitlines()[:20]:
                print(f"    {line}")

    any_fail = any(s == "FAIL" for _, s, _ in results)
    any_unavail = any(s == "PLATFORM-UNAVAILABLE" for _, s, _ in results)
    all_pass = all(s == "PASS" for _, s, _ in results)

    if all_pass:
        print("\nF11.3: PASS")
        return 0
    if any_fail:
        print("\nF11.3: FAIL (signed-but-unstapled or assessment rejected counts as FAIL)")
        return 1
    if any_unavail:
        print("\nF11.3: PLATFORM-UNAVAILABLE (notarization/Developer ID not runnable on this host)")
        return 2
    print("\nF11.3: INCOMPLETE")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
