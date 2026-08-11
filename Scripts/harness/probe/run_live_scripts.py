#!/usr/bin/env python3
"""STUB (F2): Live input-script driver — Swift-on-macOS REQUIRED.

owned-by-CP4 — launches headless Lumina, streams JSON events into the app,
asserts via Probe v2 NDJSON socket. Python orchestration may spawn the app;
the event driver and probe client themselves are Swift.
"""
from __future__ import annotations

import sys


def main() -> int:
    print(
        "STUB: run_live_scripts.py — Swift event driver not wired yet "
        "(owned-by-CP4). Refusing vacuous PASS.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
