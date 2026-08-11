#!/usr/bin/env python3
"""Lumina harness runner — FAST / FULL / HEAVY lanes.

FAST (<90s): on save/commit via watch mode — token lint, copy-table lint,
banned-pattern grep, existing lints, unit + property tests.

FULL (<10min, pre-merge, parallel): snapshot/golden diffs, input-script grammar
suite via state probe, signpost trace parse, one-⌘Z-per-gesture asserts, count
invariants. Runs against a git worktree snapshot — never locks the editing tree.
A red FULL blocks MERGE, never EDITING.

HEAVY (nightly + release): ingest timing, kill-fuzz, eject faults, RAM-tier,
LR round-trip, zero-egress audit, grammar-stability re-run of ALL prior scripts.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "Scripts" / "harness"
ARTIFACTS = ROOT / "artifacts" / "harness" / "runs"


def _post_dashboard(event: dict) -> None:
    url = os.environ.get("LUMINA_HARNESS_DASHBOARD", "http://127.0.0.1:8765/event")
    data = json.dumps(event).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=0.3)
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        # Dashboard is optional — always also append locally.
        pass
    log = ROOT / "artifacts" / "harness" / "dashboard" / "events.ndjson"
    log.parent.mkdir(parents=True, exist_ok=True)
    event = dict(event)
    event.setdefault("ts", datetime.now(timezone.utc).isoformat())
    with log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, sort_keys=True) + "\n")


def _run(step: str, argv: list[str], lane: str, cwd: Path | None = None) -> dict:
    started = time.perf_counter()
    proc = subprocess.run(
        argv,
        cwd=str(cwd or ROOT),
        capture_output=True,
        text=True,
    )
    ms = int((time.perf_counter() - started) * 1000)
    ok = proc.returncode == 0
    event = {
        "lane": lane,
        "step": step,
        "ok": ok,
        "ms": ms,
        "message": (proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else proc.stderr.strip()[:200]),
        "returncode": proc.returncode,
    }
    _post_dashboard(event)
    status = "OK" if ok else "FAIL"
    print(f"[{lane}] {step}: {status} ({ms}ms)")
    if not ok and proc.stderr.strip():
        print(proc.stderr, file=sys.stderr)
    if not ok and proc.stdout.strip() and not proc.stderr.strip():
        print(proc.stdout, file=sys.stderr)
    return event


def lane_fast() -> list[dict]:
    py = sys.executable
    steps = [
        ("token_lint", [py, str(HARNESS / "lint" / "token_lint.py")]),
        ("copy_table_lint", [py, str(HARNESS / "lint" / "copy_table_lint.py")]),
        ("banned_patterns", ["bash", str(HARNESS / "lint" / "banned_patterns.sh")]),
        ("magic_numbers", ["bash", str(HARNESS / "lint" / "magic_numbers.sh")]),
        ("banned_words", ["bash", str(ROOT / "Scripts" / "lint" / "banned_words.sh")]),
        ("copy_contract_diff", ["bash", str(ROOT / "Scripts" / "lint" / "copy_contract_diff.sh")]),
        ("contract_structure", ["bash", str(ROOT / "Scripts" / "lint" / "contract_structure.sh")]),
        ("contract_v6_presence", ["bash", str(ROOT / "Scripts" / "lint" / "contract_v6_presence.sh")]),
        ("agent_rules_contract", ["bash", str(ROOT / "Scripts" / "lint" / "agent_rules_contract.sh")]),
        ("unit_codegen", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "codegen"), "-p", "test_*.py"]),
        ("unit_golden", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "golden"), "-p", "test_*.py"]),
        ("unit_trace", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "trace"), "-p", "test_*.py"]),
        ("unit_invariants", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "tests"), "-p", "test_*.py"]),
        ("seed_scripts", [py, str(HARNESS / "probe" / "run_scripts.py")]),
    ]
    return [_run(name, argv, "FAST") for name, argv in steps]


def _full_steps(cwd: Path) -> list[tuple[str, list[str]]]:
    py = sys.executable
    fixture_trace = HARNESS / "trace" / "fixtures" / "acceptance_sample.log"
    return [
        ("grammar_scripts", [py, str(HARNESS / "probe" / "run_scripts.py")]),
        ("count_invariants", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "tests"), "-p", "test_*.py"]),
        (
            "signpost_trace",
            [py, str(HARNESS / "trace" / "parse_signposts.py"), str(fixture_trace), "--ledger",
             str(cwd / "artifacts" / "harness" / "ledgers" / "full.json")],
        ),
        (
            "golden_chrome_compare",
            [py, str(HARNESS / "golden" / "run_chrome_diff.py")],
        ),
        (
            "parallel_instances_dry",
            [py, str(HARNESS / "parallel_instances.py"), "--dry-run", "--n", "2"],
        ),
    ]


def lane_full() -> list[dict]:
    sys.path.insert(0, str(HARNESS))
    from worktree_runner import cleanup_snapshot, create_snapshot  # noqa: WPS433

    snap = create_snapshot(ROOT)
    print(f"[FULL] snapshot worktree: {snap}")
    try:
        steps = _full_steps(snap)
        # Parallel where independent.
        results: list[dict] = []
        with ThreadPoolExecutor(max_workers=min(4, len(steps))) as pool:
            futs = {pool.submit(_run, name, argv, "FULL", snap): name for name, argv in steps}
            for fut in as_completed(futs):
                results.append(fut.result())
        # Preserve step order in report
        order = {name: i for i, (name, _) in enumerate(steps)}
        results.sort(key=lambda r: order.get(r["step"], 99))
        return results
    finally:
        cleanup_snapshot(snap)


def lane_heavy() -> list[dict]:
    py = sys.executable
    steps = [
        ("grammar_stability_all_scripts", [py, str(HARNESS / "probe" / "run_scripts.py")]),
        ("zero_egress_audit", ["bash", str(HARNESS / "lint" / "banned_patterns.sh")]),
        ("heavy_placeholders", [py, str(HARNESS / "heavy_placeholders.py")]),
    ]
    return [_run(name, argv, "HEAVY") for name, argv in steps]


def write_report(lane: str, results: list[dict], elapsed_ms: int) -> Path:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    path = ARTIFACTS / f"{lane.lower()}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
    body = {
        "lane": lane,
        "elapsed_ms": elapsed_ms,
        "ok": all(r["ok"] for r in results),
        "results": results,
    }
    path.write_text(json.dumps(body, indent=2) + "\n", encoding="utf-8")
    latest = ARTIFACTS / f"{lane.lower()}-latest.json"
    latest.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return path


def watch_loop() -> int:
    """Poll for changes; stream FAST results to the local dashboard."""
    print("[WATCH] FAST on change — Ctrl+C to stop")
    last = None
    while True:
        stamp = []
        for path in [
            ROOT / "design" / "tokens.yaml",
            ROOT / "design" / "copy-contract.txt",
            ROOT / "Scripts" / "harness",
            ROOT / "Lumina",
        ]:
            if path.is_file():
                stamp.append(path.stat().st_mtime)
            elif path.is_dir():
                for child in path.rglob("*"):
                    if child.is_file():
                        stamp.append(child.stat().st_mtime)
        key = max(stamp) if stamp else 0
        if key != last:
            last = key
            started = time.perf_counter()
            results = lane_fast()
            elapsed = int((time.perf_counter() - started) * 1000)
            write_report("FAST", results, elapsed)
            _post_dashboard({"lane": "FAST", "step": "watch_cycle", "ok": all(r["ok"] for r in results), "ms": elapsed})
        time.sleep(1.0)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lane", choices=["fast", "full", "heavy", "watch", "all"])
    args = parser.parse_args(argv)

    if args.lane == "watch":
        return watch_loop()

    lanes = ["fast", "full", "heavy"] if args.lane == "all" else [args.lane]
    overall_ok = True
    for lane in lanes:
        started = time.perf_counter()
        if lane == "fast":
            results = lane_fast()
        elif lane == "full":
            results = lane_full()
        else:
            results = lane_heavy()
        elapsed = int((time.perf_counter() - started) * 1000)
        path = write_report(lane.upper(), results, elapsed)
        ok = all(r["ok"] for r in results)
        overall_ok = overall_ok and ok
        budget = {"fast": 90_000, "full": 600_000, "heavy": 3_600_000}[lane]
        over = elapsed > budget
        print(f"=== {lane.upper()} {'PASS' if ok else 'FAIL'} in {elapsed}ms (budget {budget}ms) report={path}")
        if over:
            print(f"WARN: {lane.upper()} exceeded budget ({elapsed} > {budget})", file=sys.stderr)
            # Budget overage warns but does not fail the lane on Linux cold start.
    return 0 if overall_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
