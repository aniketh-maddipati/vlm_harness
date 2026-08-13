#!/usr/bin/env python3
"""HEAVY app-coupled job launcher — delegates to shell entrypoints when wired."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HEAVY = ROOT / "Scripts" / "harness" / "heavy"

JOB_SCRIPTS = {
    "kill_fuzz_replay": "kill_fuzz_replay.sh",
    "ram_tier_runs": "ram_tiers.sh",
}

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

    script_name = JOB_SCRIPTS.get(args.job_id)
    if script_name:
        script = HEAVY / script_name
        if not script.is_file():
            print(f"FAIL: missing {script.relative_to(ROOT)}", file=sys.stderr)
            return 1
        proc = subprocess.run(["bash", str(script)], cwd=str(ROOT))
        return proc.returncode

    owner = OWNERS.get(args.job_id, "HEAVY")
    print(
        f"STUB: heavy job '{args.job_id}' — live runner not wired yet "
        f"(owned-by-{owner}). Refusing vacuous PASS.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
