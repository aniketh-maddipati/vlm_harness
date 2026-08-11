#!/usr/bin/env python3
"""STUB (F2): Live Probe v2 mid-script client — Swift-on-macOS REQUIRED.

owned-by-CP4 — connects to StateProbeV2Server NDJSON and queries generation
counters mid-script. Python may orchestrate; the in-app probe is Swift.
"""
from __future__ import annotations

import sys


def main() -> int:
    print(
        "STUB: run_live_probe.py — live probe client not wired yet "
        "(owned-by-CP4). Refusing vacuous PASS.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
