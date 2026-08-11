#!/usr/bin/env python3
"""Run FULL/HEAVY against a disposable git worktree snapshot.

Guarantees: the editing worktree is never locked by FULL/HEAVY. A red FULL lane
blocks MERGE, never EDITING.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def create_snapshot(base: Path | None = None) -> Path:
    base = base or ROOT
    stamp = tempfile.mkdtemp(prefix="lumina-full-")
    snap = Path(stamp) / "snap"
    # Prefer git worktree; fall back to archive checkout.
    branch = subprocess.check_output(
        ["git", "-C", str(base), "rev-parse", "--abbrev-ref", "HEAD"],
        text=True,
    ).strip()
    head = subprocess.check_output(
        ["git", "-C", str(base), "rev-parse", "HEAD"],
        text=True,
    ).strip()
    try:
        subprocess.check_call(
            ["git", "-C", str(base), "worktree", "add", "--detach", str(snap), head],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        subprocess.check_call(
            ["git", "-C", str(base), "archive", head],
            stdout=open(os.path.join(stamp, "archive.tar"), "wb"),
        )
        snap.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(["tar", "-xf", os.path.join(stamp, "archive.tar"), "-C", str(snap)])
    meta = {
        "source": str(base),
        "branch": branch,
        "head": head,
        "snapshot": str(snap),
    }
    (Path(stamp) / "meta.txt").write_text("\n".join(f"{k}={v}" for k, v in meta.items()) + "\n")
    return snap


def cleanup_snapshot(snap: Path) -> None:
    base = ROOT
    try:
        subprocess.call(
            ["git", "-C", str(base), "worktree", "remove", "--force", str(snap)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass
    parent = snap.parent
    if parent.exists() and parent.name.startswith("lumina-full-"):
        shutil.rmtree(parent, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--print-path", action="store_true")
    args = parser.parse_args(argv)
    snap = create_snapshot()
    if args.print_path:
        print(snap)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
