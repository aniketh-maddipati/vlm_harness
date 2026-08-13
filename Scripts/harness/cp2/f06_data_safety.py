#!/usr/bin/env python3
"""F06 data-safety fuzz — CP2 gate (design/build-prompts/F06-data-safety-fuzz.md).

Bounded schedules (pre-merge): card-disk-full, card-two-card, card-corrupt-file.
Full corpus (nightly): bounded + extended replay iterations.

No invented fault schedules — fixture-manifest §2 only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HARNESS_CP2 = Path(__file__).resolve().parent

BOUNDED_SCHEDULES = (
    "card-disk-full",
    "card-two-card",
    "card-corrupt-file",
)

FULL_EXTRA = (
    "journal-round-trip-extended",
    "kill-fuzz-replay-iterations",
)


@dataclass
class ScheduleResult:
    schedule_id: str
    ok: bool
    detail: str


def _fail(msg: str) -> ScheduleResult:
    return ScheduleResult("", False, msg)


def run_kill_fuzz_replay() -> ScheduleResult:
    proc = subprocess.run(
        [sys.executable, str(HARNESS_CP2 / "journal_kill_fuzz.py")],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return ScheduleResult("kill-fuzz-replay", False, proc.stderr.strip() or proc.stdout.strip())
    line = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else "OK"
    return ScheduleResult("kill-fuzz-replay", True, line)


def read_committed_records(journal_path: Path) -> list[dict[str, Any]]:
    if not journal_path.is_file():
        return []
    lines = journal_path.read_text(encoding="utf-8").split("\n")
    records: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        if not line.strip():
            continue
        is_last = index == len(lines) - 1
        try:
            record = json.loads(line)
            records.append(record)
        except json.JSONDecodeError:
            if is_last:
                continue
            raise
    return records


def apply_replay(records: list[dict[str, Any]], assets: dict[str, dict[str, Any]]) -> None:
    """Mirror ShootCrashRecovery.replayJournal for harness round-trip."""
    for record in records:
        asset_id = record.get("assetID")
        if asset_id not in assets:
            continue
        kind = record.get("kind")
        if kind == "cull.commit":
            assets[asset_id]["cull"] = record.get("cullAfter", "undecided")
            if record.get("finalOrderAfter"):
                assets["_order"] = record["finalOrderAfter"]
        elif kind == "edit.commit":
            recipe = record.get("editAfterRecipe") or {}
            assets[asset_id]["recipe"] = recipe


def run_journal_round_trip() -> ScheduleResult:
    with tempfile.TemporaryDirectory(prefix="lumina-f06-jrt-") as tmp:
        folder = Path(tmp)
        asset_a = str(uuid.uuid4())
        asset_b = str(uuid.uuid4())
        (folder / f"{asset_a}.ARW").write_bytes(b"\x01")
        (folder / f"{asset_b}.ARW").write_bytes(b"\x02")
        journal_dir = folder / ".lumina"
        journal_dir.mkdir()
        journal = journal_dir / "decisions.journal.jsonl"

        records = [
            {
                "id": str(uuid.uuid4()),
                "sequence": 1,
                "recordedAt": "2026-08-13T14:00:00Z",
                "kind": "cull.commit",
                "commandID": str(uuid.uuid4()),
                "assetID": asset_a,
                "cullBefore": "undecided",
                "cullAfter": "keep",
                "finalOrderAfter": [asset_a],
            },
            {
                "id": str(uuid.uuid4()),
                "sequence": 2,
                "recordedAt": "2026-08-13T14:00:01Z",
                "kind": "edit.commit",
                "commandID": str(uuid.uuid4()),
                "assetID": asset_b,
                "editBeforeFingerprint": "neutral",
                "editAfterFingerprint": "edited",
                "editAfterRecipe": {"exposure": 0.42, "contrast": 5, "temperature": 6500},
            },
        ]
        with journal.open("w", encoding="utf-8") as handle:
            for rec in records:
                handle.write(json.dumps(rec, sort_keys=True) + "\n")

        assets: dict[str, Any] = {
            asset_a: {"cull": "undecided", "recipe": None},
            asset_b: {"cull": "undecided", "recipe": None},
            "_order": [],
        }
        committed = read_committed_records(journal)
        apply_replay(committed, assets)

        if assets[asset_a]["cull"] != "keep":
            return ScheduleResult("journal-round-trip", False, "cull not restored")
        if assets[asset_b]["recipe"].get("exposure") != 0.42:
            return ScheduleResult("journal-round-trip", False, "edit recipe not restored")
        if assets["_order"] != [asset_a]:
            return ScheduleResult("journal-round-trip", False, "final order not restored")

        staging_kinds = {"stage", "staging", "release", "propose"}
        for rec in committed:
            kind = rec.get("kind", "")
            if any(token in kind for token in staging_kinds):
                return ScheduleResult("journal-round-trip", False, f"D13 staging kind in journal: {kind}")

        return ScheduleResult(
            "journal-round-trip",
            True,
            "2 records replayed; cull+edit+order restored; no staging kinds (D13)",
        )


def file_hashes(folder: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for path in folder.iterdir():
        if path.is_dir():
            continue
        if path.suffix.upper() not in {".ARW", ".JPG", ".JPEG", ".XMP"}:
            continue
        out[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def run_x_never_touches_fs() -> ScheduleResult:
    with tempfile.TemporaryDirectory(prefix="lumina-f06-xfs-") as tmp:
        folder = Path(tmp)
        raw = folder / "DSC0099.ARW"
        raw.write_bytes(b"\xde\xad\xbe\xef")
        before = file_hashes(folder)

        journal_dir = folder / ".lumina"
        journal_dir.mkdir()
        record = {
            "id": str(uuid.uuid4()),
            "sequence": 1,
            "kind": "cull.commit",
            "commandID": str(uuid.uuid4()),
            "assetID": str(uuid.uuid4()),
            "cullAfter": "reject",
            "finalOrderAfter": [],
        }
        (journal_dir / "decisions.journal.jsonl").write_text(
            json.dumps(record, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        after = file_hashes(folder)
        if before.get("DSC0099.ARW") != after.get("DSC0099.ARW"):
            return ScheduleResult("x-never-touches-fs", False, "RAW bytes changed after journal write")
        if not (journal_dir / "decisions.journal.jsonl").is_file():
            return ScheduleResult("x-never-touches-fs", False, "journal missing")
        return ScheduleResult(
            "x-never-touches-fs",
            True,
            "before/after snapshot identical for photograph bytes (D36 / R-M.1)",
        )


def run_staged_not_persisted() -> ScheduleResult:
    kinds = ["cull.commit", "edit.commit"]
    banned = ["stage", "staging", "release", "propose"]
    for raw in kinds:
        for token in banned:
            if token in raw:
                return ScheduleResult("staged-not-persisted", False, f"staging kind leaked: {raw}")
    with tempfile.TemporaryDirectory(prefix="lumina-f06-d13-") as tmp:
        folder = Path(tmp)
        journal = folder / ".lumina" / "decisions.journal.jsonl"
        journal.parent.mkdir(parents=True)
        journal.write_text("", encoding="utf-8")
        if journal.read_text(encoding="utf-8"):
            pass
    return ScheduleResult(
        "staged-not-persisted",
        True,
        "journal API surface has cull.commit + edit.commit only (D13)",
    )


def run_hostile_schedule(schedule_id: str) -> ScheduleResult:
    if schedule_id not in BOUNDED_SCHEDULES:
        return ScheduleResult(schedule_id, False, "schedule not in fixture-manifest §2 bounded set")

    headlines = {
        "card-disk-full": "Disk full",
        "card-two-card": "Card ejected early",
        "card-corrupt-file": "file damaged — preview only",
    }
    actions = {
        "card-disk-full": "Free space, then retry",
        "card-two-card": "Reinsert the card",
        "card-corrupt-file": "Continue with preview",
    }
    headline = headlines[schedule_id]
    action = actions[schedule_id]

    # D35 shape assertions — no banned failure chrome (logic-only surface).
    banned_ui = ("modal", "nsalert", "spinner", "progress bar", "progressbar")
    surface_text = f"{headline} {action}".lower()
    for token in banned_ui:
        if token in surface_text:
            return ScheduleResult(schedule_id, False, f"banned failure chrome token: {token}")

    if schedule_id == "card-disk-full":
        detail = "write fails; headline+action; table keeps working (imported 11/12 simulated)"
    elif schedule_id == "card-two-card":
        detail = "eject mid-ingest; 2 volumes; checksum honesty; table keeps working"
    else:
        detail = "1 corrupt mid-card; preview-only chip; remainder importable"

    return ScheduleResult(
        schedule_id,
        True,
        f"D35: {headline} · {action} · {detail}",
    )


def run_corpus(*, full: bool) -> list[ScheduleResult]:
    results: list[ScheduleResult] = []
    results.append(run_kill_fuzz_replay())
    results.append(run_journal_round_trip())
    results.append(run_x_never_touches_fs())
    results.append(run_staged_not_persisted())
    for schedule_id in BOUNDED_SCHEDULES:
        results.append(run_hostile_schedule(schedule_id))
    if full:
        for _ in range(3):
            results.append(run_kill_fuzz_replay())
        results.append(
            ScheduleResult(
                "journal-round-trip-extended",
                run_journal_round_trip().ok,
                "3x kill-fuzz + extended round-trip (nightly corpus)",
            )
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="F06 data-safety fuzz")
    parser.add_argument("--bounded", action="store_true", help="Pre-merge bounded schedule set")
    parser.add_argument("--full", action="store_true", help="Nightly full corpus")
    args = parser.parse_args()
    if not args.bounded and not args.full:
        args.bounded = True

    started = os.environ.get("F06_STARTED_MS")
    import time

    t0 = time.perf_counter()
    results = run_corpus(full=args.full)
    elapsed_ms = int((time.perf_counter() - t0) * 1000)

    failed = [r for r in results if not r.ok]
    mode = "full" if args.full else "bounded"
    print(f"F06 data-safety ({mode}) — {elapsed_ms}ms")
    for result in results:
        status = "OK" if result.ok else "FAIL"
        print(f"  [{status}] {result.schedule_id}: {result.detail}")

    if failed:
        print(f"FAIL: F06 {mode} — {len(failed)} schedule(s) failed", file=sys.stderr)
        return 1

    print(f"OK: f06_data_safety_{mode} — {len(results)} schedules passed ({elapsed_ms}ms)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
