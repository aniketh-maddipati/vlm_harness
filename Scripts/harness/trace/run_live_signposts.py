#!/usr/bin/env python3
"""STUB (F2): Live acceptance signpost capture — Swift-on-macOS REQUIRED.

owned-by-SPIKE-A — os_signpost emission is Swift (not wired);
this orchestrator collects a measured trace and writes a gates_active ledger.
Until wired, acceptance numbers remain UNMEASURED (F4).
"""
from __future__ import annotations

import sys


def main() -> int:
    print(
        "STUB: run_live_signposts.py — measured signpost capture not wired yet "
        "(owned-by-SPIKE-A). Refusing vacuous PASS.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
