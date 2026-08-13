#!/usr/bin/env python3
"""HEAVY-lane registry — orchestration bookkeeping (Python permitted).

STUB (F2): Live job bodies are Swift-on-macOS (owned-by-HEAVY via run_job.py).
This file only proves every HEAVY job id has an owner + entrypoint so no gap
remains unowned. It is not an app-coupled PASS.
"""
from __future__ import annotations

import json
import sys

JOBS = [
    {
        "id": "ingest_timing",
        "owner": "HEAVY",
        "entrypoint": "Scripts/harness/heavy/ingest_timing.sh",
        "status": "registered",
        "requires": ["macOS", "card-clean-500"],
    },
    {
        "id": "kill_fuzz_replay",
        "owner": "HEAVY",
        "entrypoint": "Scripts/harness/heavy/kill_fuzz_replay.sh",
        "status": "active",
        "requires": ["macOS", "CP2"],
    },
    {
        "id": "eject_fault_injection",
        "owner": "HEAVY",
        "entrypoint": "Scripts/harness/heavy/eject_faults.sh",
        "status": "registered",
        "requires": ["macOS", "card-two-card"],
    },
    {
        "id": "ram_tier_runs",
        "owner": "W6",
        "entrypoint": "Scripts/harness/heavy/ram_tiers.sh",
        "status": "active",
        "requires": ["macOS", "card-clean-500", "mixed-200"],
    },
    {
        "id": "lr_round_trip",
        "owner": "HEAVY",
        "entrypoint": "Scripts/harness/heavy/lr_round_trip.sh",
        "status": "registered",
        "requires": ["macOS", "CP2"],
    },
    {
        "id": "zero_egress_audit",
        "owner": "HEAVY",
        "entrypoint": "Scripts/harness/lint/banned_patterns.sh",
        "status": "active",
    },
    {
        "id": "grammar_stability_rerun",
        "owner": "HEAVY",
        "entrypoint": "Scripts/harness/probe/run_scripts.py",
        "status": "active",
        "notes": "Re-run ALL prior scripts unchanged (D51).",
    },
]


def main() -> int:
    missing = [j for j in JOBS if not j.get("owner")]
    if missing:
        print(f"FAIL: unowned HEAVY jobs: {missing}", file=sys.stderr)
        return 1
    print(json.dumps({"ok": True, "jobs": JOBS}, indent=2))
    print("heavy_placeholders.py: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
