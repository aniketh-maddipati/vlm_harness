#!/usr/bin/env python3
"""CP2 journal kill-mid-write proof (D35 quit-anywhere).

Spawns a writer subprocess that appends JSONL decision records beside a shoot folder,
SIGKILLs it during a partial trailing write, then verifies every complete line survived
using the same trailing-line recovery rule as ShootDecisionJournal.readCommittedRecords.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
WORKER = Path(__file__).resolve().parent / "journal_kill_worker.py"

COMMITTED_LINES = 8


def read_committed_records(journal_path: Path) -> list[dict[str, Any]]:
    """Mirror ShootDecisionJournal.readCommittedRecords trailing-line recovery."""
    if not journal_path.is_file():
        return []
    data = journal_path.read_bytes()
    if not data:
        return []
    text = data.decode("utf-8")
    lines = text.split("\n")
    records: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        if not line:
            continue
        is_last = index == len(lines) - 1
        try:
            record = json.loads(line)
            if records and record.get("sequence", 0) <= records[-1].get("sequence", 0):
                raise ValueError("sequence regression")
            records.append(record)
        except (json.JSONDecodeError, ValueError):
            if is_last:
                continue
            raise
    return records


def run_kill_proof() -> None:
    with tempfile.TemporaryDirectory(prefix="lumina-cp2-kill-") as tmp:
        shoot = Path(tmp)
        journal_dir = shoot / ".lumina"
        journal_dir.mkdir()
        journal_path = journal_dir / "decisions.journal.jsonl"

        env = os.environ.copy()
        env["LUMINA_JOURNAL_PATH"] = str(journal_path)
        env["LUMINA_JOURNAL_COMMITTED"] = str(COMMITTED_LINES)

        proc = subprocess.Popen(
            [sys.executable, str(WORKER)],
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            if journal_path.is_file():
                try:
                    records = read_committed_records(journal_path)
                    if len(records) >= COMMITTED_LINES:
                        raw = journal_path.read_bytes()
                        if raw and not raw.endswith(b"\n"):
                            proc.send_signal(signal.SIGKILL)
                            proc.wait(timeout=2)
                            break
                except (json.JSONDecodeError, ValueError):
                    pass
        else:
            proc.kill()
            proc.wait(timeout=2)
            raise AssertionError("timed out waiting for partial trailing write")

        if proc.returncode is None:
            proc.kill()
            proc.wait(timeout=2)

        recovered = read_committed_records(journal_path)
        if len(recovered) != COMMITTED_LINES:
            raise AssertionError(
                f"D35 kill-mid-write: expected {COMMITTED_LINES} committed records, "
                f"recovered {len(recovered)}"
            )
        sequences = [r["sequence"] for r in recovered]
        if sequences != list(range(1, COMMITTED_LINES + 1)):
            raise AssertionError(f"D35 kill-mid-write: bad sequences {sequences}")

        tail = journal_path.read_bytes()
        if tail.endswith(b"\n"):
            raise AssertionError("D35 kill-mid-write: journal must end with partial line after SIGKILL")

        print(
            f"OK: cp2_journal_kill_fuzz — SIGKILL mid-write; "
            f"{len(recovered)}/{COMMITTED_LINES} committed lines recovered (D35)"
        )


def main() -> int:
    if not WORKER.is_file():
        print(f"FAIL: missing worker {WORKER}", file=sys.stderr)
        return 1
    try:
        run_kill_proof()
        return 0
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
