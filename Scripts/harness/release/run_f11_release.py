#!/usr/bin/env python3
"""Run F11.1–F11.7 release integrity checks against a built Release app."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

RELEASE = Path(__file__).resolve().parent
ROOT = RELEASE.parents[2]


def _run(script: str, extra: list[str]) -> int:
    proc = subprocess.run([sys.executable, str(RELEASE / script), *extra])
    return proc.returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build" / "Release" / "Lumina.app")
    parser.add_argument("--promote-shipped", action="store_true", help="F11.5 rotate shipped artifacts")
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("F11 release integrity: PLATFORM-UNAVAILABLE (macOS only)")
        return 2

    app = args.app
    app_flag = ["--app", str(app)]
    steps = [
        ("F11.1 hooks absent", "f11_hooks_absent.py", app_flag),
        ("F11.2 zero network", "f11_zero_network.py", app_flag),
        ("F11.3 signature", "f11_signature.py", app_flag),
        ("F11.4 read manifest", "f11_read_manifest.py", app_flag + ["--check"]),
        ("F11.6 betaDiagnostics null", "f11_a7_expiry.py", app_flag),
        ("F11.7 no licensing", "f11_no_licensing.py", []),
    ]
    worst = 0
    for label, script, extra in steps:
        print(f"\n{'=' * 60}\n{label}\n{'=' * 60}")
        code = _run(script, extra)
        if code == 2:
            worst = max(worst, 2)
        elif code != 0:
            worst = 1

    if args.promote_shipped and worst == 0:
        print(f"\n{'=' * 60}\nF11.5 promote shipped\n{'=' * 60}")
        code = _run("retain_shipped_artifact.py", ["promote", *app_flag])
        if code != 0:
            worst = 1

    if worst == 0:
        print("\nF11 release integrity: PASS")
    elif worst == 2:
        print("\nF11 release integrity: PLATFORM-UNAVAILABLE")
    else:
        print("\nF11 release integrity: FAIL")
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
