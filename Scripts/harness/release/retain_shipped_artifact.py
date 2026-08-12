#!/usr/bin/env python3
"""F11.5 — retain previous shipped Release artifact + manifest (D51 / R-I.2 rollback).

Promote: move `current/` → `previous/`, copy new app + manifest into `current/`.
Rollback is copying `previous/Lumina.app` — no rebuild required.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SHIPPED = ROOT / "artifacts" / "release" / "shipped"
CURRENT = SHIPPED / "current"
PREVIOUS = SHIPPED / "previous"


def _copy_app(src: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest, symlinks=True)


def promote(app: Path, manifest: Path | None) -> dict:
    SHIPPED.mkdir(parents=True, exist_ok=True)
    report: dict = {"promotedAt": datetime.now(timezone.utc).isoformat()}

    if CURRENT.is_dir():
        if PREVIOUS.is_dir():
            shutil.rmtree(PREVIOUS)
        CURRENT.rename(PREVIOUS)
        report["rotated"] = str(PREVIOUS)

    CURRENT.mkdir(parents=True, exist_ok=True)
    dest_app = CURRENT / "Lumina.app"
    _copy_app(app, dest_app)
    report["currentApp"] = str(dest_app)

    if manifest is None:
        manifest = app / "Contents" / "Resources" / "LuminaBuildManifest.json"
    if manifest.is_file():
        dest_manifest = CURRENT / "LuminaBuildManifest.json"
        shutil.copy2(manifest, dest_manifest)
        report["currentManifest"] = str(dest_manifest)
    else:
        report["currentManifest"] = None

    if (PREVIOUS / "Lumina.app").is_dir():
        report["previousApp"] = str(PREVIOUS / "Lumina.app")
        prev_manifest = PREVIOUS / "LuminaBuildManifest.json"
        report["previousManifest"] = str(prev_manifest) if prev_manifest.is_file() else None

    ledger = SHIPPED / "promote-log.json"
    ledger.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def status() -> dict:
    out: dict = {"shippedRoot": str(SHIPPED)}
    for label, base in ("current", CURRENT), ("previous", PREVIOUS):
        app = base / "Lumina.app"
        manifest = base / "LuminaBuildManifest.json"
        out[label] = {
            "app": str(app) if app.is_dir() else None,
            "manifest": str(manifest) if manifest.is_file() else None,
        }
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("promote", help="Rotate current→previous and copy new shipped artifact")
    p.add_argument("--app", type=Path, required=True)
    p.add_argument("--manifest", type=Path)
    sub.add_parser("status", help="Print shipped artifact paths")
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("F11.5 shipped artifact: PLATFORM-UNAVAILABLE (macOS only)")
        return 2

    if args.cmd == "status":
        print(json.dumps(status(), indent=2, sort_keys=True))
        return 0

    if not args.app.is_dir():
        print(f"F11.5: FAIL — app not found: {args.app}", file=sys.stderr)
        return 1
    report = promote(args.app, args.manifest)
    print(json.dumps(report, indent=2, sort_keys=True))
    print("\nF11.5: PASS — rollback file at artifacts/release/shipped/previous/Lumina.app")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
