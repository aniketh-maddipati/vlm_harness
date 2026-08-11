#!/usr/bin/env python3
"""STUB (F2): HEAVY app-coupled job launcher — Swift-on-macOS REQUIRED.

owned-by-HEAVY — each job id is registered in heavy_placeholders.py with an
owner. This entrypoint refuses vacuous PASS until the Mac runner exists.
"""
from __future__ import annotations

import argparse
import sys

OWNERS = {
    "ingest_timing": "HEAVY",
    "kill_fuzz_replay": "HEAVY/CP2",
    "eject_fault_injection": "HEAVY",
    "ram_tier_runs": "HEAVY",
    "lr_round_trip": "HEAVY/CP2",
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("job_id")
    args = parser.parse_args(argv)
    owner = OWNERS.get(args.job_id, "HEAVY")
    print(
        f"STUB: heavy job '{args.job_id}' — live runner not wired yet "
        f"(owned-by-{owner}). Refusing vacuous PASS.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
