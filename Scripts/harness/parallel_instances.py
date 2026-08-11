#!/usr/bin/env python3
"""Parallel headless instances — N isolated fixture sandboxes.

STUB (F2): Sandbox orchestration is Python-permitted; launching headless Lumina
instances + fake-clock injection is Swift-on-macOS REQUIRED.
owned-by-HEAVY — live multi-instance driver not wired; --dry-run only proves
sandbox isolation (orchestration). Without --dry-run this refuses vacuous PASS.
"""
from __future__ import annotations

import argparse
import json
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
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Orchestration-only sandbox proof (not an app-coupled PASS)",
    )
    args = parser.parse_args(argv)
    root = Path(tempfile.mkdtemp(prefix="lumina-parallel-"))
    try:
        instances = [make_sandbox(i, root) for i in range(args.n)]
        state_dirs = {i["state_dir"] for i in instances}
        journals = {i["journal_root"] for i in instances}
        assert len(state_dirs) == args.n
        assert len(journals) == args.n
        report = {"n": args.n, "instances": instances, "dry_run": args.dry_run}
        print(json.dumps(report, indent=2))
        if args.dry_run:
            print("parallel_instances.py: OK (dry-run orchestration only)")
            return 0
        print(
            "STUB: parallel_instances live launch — Swift headless instances "
            "not wired yet (owned-by-HEAVY). Refusing vacuous PASS.",
            file=__import__("sys").stderr,
        )
        return 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
