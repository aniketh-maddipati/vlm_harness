#!/usr/bin/env python3
"""Validate input-script schema and (optionally) run the Python grammar oracle.

STUB NOTE (F2): The Python ProbeSimulator is an orchestration oracle for schema /
assert shape — NOT the app-coupled event driver. Live grammar execution is
Swift-on-macOS via run_live_scripts.py (owned-by-CP4). Unowned stubs are forbidden.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / "Scripts" / "harness" / "scripts" / "seed"
SCRIPT_SCHEMA = ROOT / "Scripts" / "harness" / "scripts" / "schema.json"
PROBE_SCHEMA = ROOT / "Scripts" / "harness" / "probe" / "schema.json"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grammar_machine import GrammarMachine  # noqa: E402
from grammar_probe import extract_grammar, grammar_diff  # noqa: E402
from simulator import ProbeSimulator, load_script  # noqa: E402


def _validate_basic_script(script: dict, *, filename: str) -> list[str]:
    errs: list[str] = []
    for key in ("schemaVersion", "id", "title", "fixture", "events", "asserts"):
        if key not in script:
            errs.append(f"{filename}: missing required field {key}")
    version = script.get("schemaVersion")
    if version != 2:
        if version == 1:
            errs.append(
                f"{filename}: schemaVersion 1 rejected — input-script schema requires schemaVersion 2"
            )
        elif "schemaVersion" in script:
            errs.append(f"{filename}: schemaVersion must be 2 (got {version!r})")

    prev_t: int | None = None
    for i, event in enumerate(script.get("events") or []):
        if "op" not in event:
            errs.append(f"{filename}: events[{i}] missing op")
            continue
        if "tMs" not in event:
            errs.append(f"{filename}: events[{i}] missing required field tMs")
            continue
        if version != 2:
            continue
        t_ms = int(event["tMs"])
        if prev_t is not None and t_ms < prev_t:
            errs.append(
                f"{filename}: events[{i}] tMs {t_ms} regresses from events[{i - 1}] tMs {prev_t}"
            )
        if event["op"] == "wait":
            delta = int(event.get("ms") or 0)
            if prev_t is not None and t_ms != prev_t + delta:
                errs.append(
                    f"{filename}: events[{i}] wait tMs {t_ms} must equal prior tMs {prev_t} + ms {delta}"
                )
        prev_t = t_ms
        for banned in ("x", "y", "cgPoint", "screenX", "screenY"):
            if banned in event:
                errs.append(f"{filename}: events[{i}] contains banned coordinate field '{banned}'")
    return errs


def _validate_state_shape(state: dict) -> list[str]:
    errs = []
    required = [
        "schemaVersion",
        "tsMs",
        "generation",
        "records",
        "marks",
        "staging",
        "focus",
        "residentRungByFrame",
    ]
    for key in required:
        if key not in state:
            errs.append(f"state missing {key}")
    if state.get("schemaVersion") != 2:
        errs.append("state.schemaVersion must be 2")
    return errs


def run_schema_only(seed_dir: Path = SEED) -> int:
    scripts = sorted(seed_dir.glob("*.json"))
    if len(scripts) < 5:
        print(f"FAIL: expected ≥5 seed scripts, found {len(scripts)}", file=sys.stderr)
        return 1
    if not SCRIPT_SCHEMA.is_file() or not PROBE_SCHEMA.is_file():
        print("FAIL: missing script/probe schema", file=sys.stderr)
        return 1
    fail = 0
    for path in scripts:
        script = load_script(path)
        errs = _validate_basic_script(script, filename=path.name)
        if errs:
            for err in errs:
                print(f"FAIL: {err}", file=sys.stderr)
            fail = 1
        else:
            print(f"  schema {path.name}: OK")
    if fail:
        return 1
    print("run_scripts.py --schema-only: OK")
    return 0


def run_oracle(seed_dir: Path = SEED) -> int:
    """STUB (F2): Python grammar oracle — orchestration unit, not app-coupled."""
    print("STUB: ProbeSimulator grammar oracle (owned-by-CP4 for live Swift driver)")
    scripts = sorted(seed_dir.glob("*.json"))
    fail = 0
    for path in scripts:
        script = load_script(path)
        errs = _validate_basic_script(script, filename=path.name)
        if errs:
            for err in errs:
                print(f"FAIL: {err}", file=sys.stderr)
            fail = 1
            continue
        sim = ProbeSimulator.from_script(script)
        result = sim.run(script)
        shape_errs = _validate_state_shape(result["state"])
        if shape_errs:
            print(f"FAIL: {path.name} probe shape: {shape_errs}", file=sys.stderr)
            fail = 1
        if not result["ok"]:
            print(f"FAIL: {path.name} asserts: {result['failures']}", file=sys.stderr)
            fail = 1
        else:
            print(f"  oracle {path.name}: OK")
    if fail:
        return 1
    print("run_scripts.py --oracle: OK")
    return 0


def run_parity(seed_dir: Path = SEED) -> int:
    """F02.5: replay v2 seeds through oracle + Swift-machine mirror; divergence is FAIL."""
    print(
        "grammar_oracle_parity: ProbeSimulator vs CullGrammarMachine mirror "
        "(orchestration only — never app-coupled PASS)"
    )
    scripts = sorted(seed_dir.glob("*.json"))
    fail = 0
    for path in scripts:
        script = load_script(path)
        errs = _validate_basic_script(script, filename=path.name)
        if errs:
            for err in errs:
                print(f"FAIL: {err}", file=sys.stderr)
            fail = 1
            continue

        sim = ProbeSimulator.from_script(script)
        for event in script["events"]:
            sim.apply_event(event)
        oracle = extract_grammar(sim.state)

        machine = GrammarMachine.from_script(script)
        machine.replay_script(script)
        swift = machine.grammar_snapshot()

        diffs = grammar_diff(oracle, swift)
        if diffs:
            fail = 1
            print(f"FAIL: {path.name} oracle ↔ Swift-machine divergence:", file=sys.stderr)
            for line in diffs:
                print(line, file=sys.stderr)
            print(f"  oracle reading:  {oracle!r}", file=sys.stderr)
            print(f"  machine reading: {swift!r}", file=sys.stderr)
        else:
            print(f"  parity {path.name}: OK")
    if fail:
        return 1
    print("run_scripts.py --parity: OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--schema-only",
        action="store_true",
        help="Validate seed script schemas only (FAST orchestration)",
    )
    parser.add_argument(
        "--oracle",
        action="store_true",
        help="Run Python STUB grammar oracle (not app-coupled)",
    )
    parser.add_argument(
        "--parity",
        action="store_true",
        help="Oracle ↔ Swift-machine parity on v2 seed replays (FAST orchestration)",
    )
    args = parser.parse_args(argv)
    if args.schema_only:
        return run_schema_only()
    if args.oracle:
        return run_oracle()
    if args.parity:
        return run_parity()
    # Default: schema + oracle (legacy entry for local debugging).
    code = run_schema_only()
    if code != 0:
        return code
    return run_oracle()


if __name__ == "__main__":
    raise SystemExit(main())
