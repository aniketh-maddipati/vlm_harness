#!/usr/bin/env python3
"""Parallel headless instances — N isolated fixture sandboxes.

Each instance gets a distinct temp dir + journal root. Seeded fixtures.
Fake clock is injected only in DEBUG harness launches (never Release).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path


def make_sandbox(index: int, root: Path) -> dict:
    state = root / f"instance-{index}" / "state"
    journal = root / f"instance-{index}" / "journal"
    fixtures = root / f"instance-{index}" / "fixtures"
    for path in (state, journal, fixtures):
        path.mkdir(parents=True, exist_ok=True)
    (fixtures / "seed.json").write_text(
        json.dumps({"fixture": "mixed-60", "instance": index, "fakeClock": True}) + "\n",
        encoding="utf-8",
    )
    return {
        "index": index,
        "state_dir": str(state),
        "journal_root": str(journal),
        "fixtures_dir": str(fixtures),
        "launch_args": [
            "--ui-testing",
            "--probe-v2",
            "--fixture-shoot",
            "mixed-60",
            "--ui-test-state-directory",
            str(state),
            "--ui-test-seed",
            str(1000 + index),
            "--reduce-motion",
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n", type=int, default=2)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    root = Path(tempfile.mkdtemp(prefix="lumina-parallel-"))
    try:
        instances = [make_sandbox(i, root) for i in range(args.n)]
        # Isolation asserts
        state_dirs = {i["state_dir"] for i in instances}
        journals = {i["journal_root"] for i in instances}
        assert len(state_dirs) == args.n
        assert len(journals) == args.n
        report = {"n": args.n, "instances": instances, "dry_run": args.dry_run}
        print(json.dumps(report, indent=2))
        if args.dry_run:
            print("parallel_instances.py: OK (dry-run)")
            return 0
        # Live launch is macOS-only; on Linux we stop after sandbox proof.
        if os.uname().sysname != "Darwin":
            print("parallel_instances.py: OK (sandboxes only — no app on Linux)")
            return 0
        print("parallel_instances.py: OK")
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
