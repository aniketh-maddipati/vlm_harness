#!/usr/bin/env python3
"""F11.4 — read LuminaBuildManifest.json from a built Lumina.app."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

MANIFEST_NAME = "LuminaBuildManifest.json"


def manifest_path(app: Path) -> Path:
    return app / "Contents" / "Resources" / MANIFEST_NAME


def read_manifest(app: Path) -> dict:
    path = manifest_path(app)
    if not path.is_file():
        raise FileNotFoundError(f"missing embedded manifest: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def validate_manifest(data: dict) -> list[str]:
    errors: list[str] = []
    required = (
        "gitSha",
        "tokensHash",
        "fixtureManifestVersion",
        "contractVersion",
        "buildDate",
        "marketingVersion",
    )
    for key in required:
        if not data.get(key):
            errors.append(f"missing or empty field: {key}")
    if data.get("gitSha") == "unknown":
        errors.append("gitSha is unknown")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Path to Lumina.app")
    parser.add_argument("--check", action="store_true", help="Validate required fields")
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("F11.4 read manifest: PLATFORM-UNAVAILABLE (macOS only)")
        return 2

    app = args.app
    if not (app / "Contents" / "MacOS" / "Lumina").is_file():
        print(f"F11.4 read manifest: PLATFORM-UNAVAILABLE (not a built app: {app})")
        return 2

    try:
        data = read_manifest(app)
    except FileNotFoundError as exc:
        print(f"F11.4 read manifest: FAIL — {exc}")
        return 1

    print(json.dumps(data, indent=2, sort_keys=True))
    if args.check:
        errors = validate_manifest(data)
        if errors:
            print("\nF11.4 manifest validation: FAIL", file=sys.stderr)
            for err in errors:
                print(f"  - {err}", file=sys.stderr)
            return 1
        print("\nF11.4 manifest validation: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
