#!/usr/bin/env python3
"""Lumina harness runner — FAST / FULL / HEAVY lanes.

F1 vacuous-green: each lane declares a test inventory; shortfall or zero
app-coupled tests when any are expected → FAIL/INCOMPLETE, never PASS.

F3 platform: FULL/HEAVY are macOS-Apple-Silicon-only. On other hosts they
report PLATFORM-UNAVAILABLE (not PASS).

F4 ledger: orchestration hosts write UNMEASURED acceptance numbers; gates
activate only on a measured macOS run.
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
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "Scripts" / "harness"
ARTIFACTS = ROOT / "artifacts" / "harness" / "runs"

sys.path.insert(0, str(HARNESS))
from lanes.inventory import (  # noqa: E402
    evaluate_inventory,
    format_lane_summary,
    load_manifest,
)
from lanes.host_platform import check_lane_platform  # noqa: E402
from lanes.budget_breach import emit_budget_breach  # noqa: E402


def _post_dashboard(event: dict) -> None:
    url = os.environ.get("LUMINA_HARNESS_DASHBOARD", "http://127.0.0.1:8765/event")
    data = json.dumps(event).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=0.3)
    except (urllib.error.URLError, TimeoutError, ConnectionError):
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
        "message": (
            proc.stdout.strip().splitlines()[-1]
            if proc.stdout.strip()
            else proc.stderr.strip()[:200]
        ),
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


def _write_orchestration_ledger() -> Path:
    """F4: record UNMEASURED acceptance numbers on orchestration-only hosts."""
    py = sys.executable
    ledger = ROOT / "artifacts" / "harness" / "ledgers" / "orchestration-only.json"
    ledger.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [
            py,
            str(HARNESS / "trace" / "parse_signposts.py"),
            "--orchestration-only",
            "--ledger",
            str(ledger),
        ],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"orchestration ledger failed: {proc.stderr}")
    # Also refresh latest.json for local dashboards.
    latest = ROOT / "artifacts" / "harness" / "ledgers" / "latest.json"
    latest.write_text(ledger.read_text(encoding="utf-8"), encoding="utf-8")
    return ledger


def lane_fast() -> tuple[list[dict], list[str]]:
    """FAST: orchestration-only on any platform (lint/codegen/schema/unit)."""
    py = sys.executable
    steps = [
        ("token_lint", [py, str(HARNESS / "lint" / "token_lint.py")]),
        ("copy_table_lint", [py, str(HARNESS / "lint" / "copy_table_lint.py")]),
        ("banned_patterns", ["bash", str(HARNESS / "lint" / "banned_patterns.sh")]),
        ("magic_numbers", ["bash", str(HARNESS / "lint" / "magic_numbers.sh")]),
        ("banned_words", ["bash", str(HARNESS / "lint" / "banned_words.sh")]),
        ("copy_contract_diff", ["bash", str(HARNESS / "lint" / "copy_contract_diff.sh")]),
        ("contract_structure", ["bash", str(HARNESS / "lint" / "contract_structure.sh")]),
        ("contract_v6_presence", ["bash", str(HARNESS / "lint" / "contract_v6_presence.sh")]),
        ("agent_rules_contract", ["bash", str(HARNESS / "lint" / "agent_rules_contract.sh")]),
        ("unit_codegen", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "codegen"), "-p", "test_*.py"]),
        ("unit_golden", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "golden"), "-p", "test_*.py"]),
        ("unit_trace", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "trace"), "-p", "test_*.py"]),
        ("unit_invariants", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "tests"), "-p", "test_*.py"]),
        (
            "spring_physics_f07",
            [py, str(HARNESS / "tests" / "test_f07_spring_physics.py")],
        ),
        (
            "cp2_journal_kill_fuzz",
            [py, str(HARNESS / "cp2" / "journal_kill_fuzz.py")],
        ),
        (
            "cp2_lr_round_trip",
            [py, str(HARNESS / "cp2" / "lr_round_trip.py")],
        ),
        ("unit_lane_guards", [py, "-m", "unittest", "discover", "-s", str(HARNESS / "lanes"), "-p", "test_*.py"]),
        ("seed_script_schema", [py, str(HARNESS / "probe" / "run_scripts.py"), "--schema-only"]),
        # STUB grammar oracle — orchestration unit only; not app-coupled (F2).
        ("grammar_oracle_unit", [py, str(HARNESS / "probe" / "run_scripts.py"), "--oracle"]),
        ("grammar_oracle_parity", [py, str(HARNESS / "probe" / "run_scripts.py"), "--parity"]),
        ("probe_growth", [py, str(HARNESS / "lint" / "probe_growth.py")]),
        ("probe_mirror", [py, str(HARNESS / "lint" / "probe_mirror.py")]),
        ("leaf_only_ids", [py, str(HARNESS / "lint" / "leaf_only_ids.py")]),
        (
            "constitution_coverage",
            [py, str(HARNESS / "coverage" / "generate_constitution_coverage.py"), "--check"],
        ),
        ("registry_staleness", [py, str(HARNESS / "lint" / "registry_staleness.py")]),
        ("no_sleeps", [py, str(HARNESS / "lint" / "no_sleeps.py")]),
        ("flake_policy", [py, str(HARNESS / "lint" / "flake_policy.py")]),
        ("wait_budgets", [py, str(HARNESS / "lint" / "wait_budgets.py")]),
        ("allowlist_ratchet", [py, str(HARNESS / "lint" / "allowlist_ratchet.py")]),
        ("f11_no_licensing", [py, str(HARNESS / "release" / "f11_no_licensing.py")]),
        ("f11_a7_expiry", [py, str(HARNESS / "release" / "f11_a7_expiry.py")]),
        ("unit_f11_release", [py, str(HARNESS / "tests" / "test_f11_release.py")]),
    ]
    results = [_run(name, argv, "FAST") for name, argv in steps]
    executed = [r["step"] for r in results if r["ok"]]
    return results, executed


def lane_full_macos() -> tuple[list[dict], list[str]]:
    """FULL app-coupled suite — only invoked after macos-apple-silicon check."""
    sys.path.insert(0, str(HARNESS))
    from worktree_runner import cleanup_snapshot, create_snapshot

    snap = create_snapshot(ROOT)
    print(f"[FULL] snapshot worktree: {snap}")
    py = sys.executable
    results: list[dict] = []
    executed: list[str] = []
    try:
        # Orchestration bookkeeping first.
        results.append(_run("worktree_snapshot", [py, "-c", "print('snapshot ok')"], "FULL", snap))
        if results[-1]["ok"]:
            executed.append("worktree_snapshot")
        try:
            _write_orchestration_ledger()
            # On macOS the live signpost step replaces UNMEASURED; until emitters
            # are wired into product paths this records orchestration honesty.
            results.append(
                {
                    "lane": "FULL",
                    "step": "ledger_orchestration_write",
                    "ok": True,
                    "ms": 0,
                    "message": "orchestration-only ledger written (gates inactive until measured)",
                    "returncode": 0,
                }
            )
            executed.append("ledger_orchestration_write")
            print("[FULL] ledger_orchestration_write: OK (0ms)")
        except RuntimeError as exc:
            results.append(
                {
                    "lane": "FULL",
                    "step": "ledger_orchestration_write",
                    "ok": False,
                    "ms": 0,
                    "message": str(exc),
                    "returncode": 1,
                }
            )
            print(f"[FULL] ledger_orchestration_write: FAIL — {exc}", file=sys.stderr)

        # App-coupled steps — Swift-on-macOS required (F2). These invoke the
        # live driver when present; missing driver → step FAIL (not silent skip).
        app_steps = [
            ("grammar_scripts_live", [py, str(HARNESS / "probe" / "run_live_scripts.py")]),
            ("probe_v2_mid_script", [py, str(HARNESS / "probe" / "run_live_probe.py")]),
            (
                "signpost_acceptance_measured",
                [py, str(HARNESS / "trace" / "run_live_signposts.py")],
            ),
            ("one_cmd_z_per_gesture", [py, str(HARNESS / "probe" / "run_live_undo.py")]),
            ("count_invariants_live", [py, str(HARNESS / "probe" / "run_live_invariants.py")]),
            ("golden_chrome_strict", [py, str(HARNESS / "golden" / "run_chrome_diff.py"), "--live"]),
            (
                "parallel_headless_instances",
                [py, str(HARNESS / "parallel_instances.py"), "--n", "2"],
            ),
        ]
        for name, argv in app_steps:
            results.append(_run(name, argv, "FULL", snap))
            if results[-1]["ok"]:
                executed.append(name)
        return results, executed
    finally:
        cleanup_snapshot(snap)


def lane_heavy_macos() -> tuple[list[dict], list[str]]:
    py = sys.executable
    results: list[dict] = []
    executed: list[str] = []
    orch = [
        ("zero_egress_audit", ["bash", str(HARNESS / "lint" / "banned_patterns.sh")]),
        ("heavy_job_registry", [py, str(HARNESS / "heavy_placeholders.py")]),
        (
            "release_integrity_f11",
            [py, str(HARNESS / "release" / "run_f11_release.py"), "--app", str(ROOT / "build" / "Release" / "Lumina.app")],
        ),
    ]
    for name, argv in orch:
        results.append(_run(name, argv, "HEAVY"))
        if results[-1]["ok"]:
            executed.append(name)
    app_steps = [
        ("ingest_timing", [py, str(HARNESS / "heavy" / "run_job.py"), "ingest_timing"]),
        ("kill_fuzz_replay", [py, str(HARNESS / "heavy" / "run_job.py"), "kill_fuzz_replay"]),
        ("eject_fault_injection", [py, str(HARNESS / "heavy" / "run_job.py"), "eject_fault_injection"]),
        ("ram_tier_runs", [py, str(HARNESS / "heavy" / "run_job.py"), "ram_tier_runs"]),
        ("lr_round_trip", [py, str(HARNESS / "heavy" / "run_job.py"), "lr_round_trip"]),
        (
            "grammar_stability_rerun_live",
            [py, str(HARNESS / "probe" / "run_live_scripts.py"), "--all-prior"],
        ),
    ]
    for name, argv in app_steps:
        results.append(_run(name, argv, "HEAVY"))
        if results[-1]["ok"]:
            executed.append(name)
    return results, executed


def write_report(
    lane: str,
    results: list[dict],
    elapsed_ms: int,
    *,
    status: str,
    inventory: dict,
    platform_reason: str | None = None,
) -> Path:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    path = ARTIFACTS / f"{lane.lower()}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
    body = {
        "lane": lane,
        "elapsed_ms": elapsed_ms,
        "status": status,
        "ok": status == "PASS",
        "inventory": inventory,
        "platform_reason": platform_reason,
        "results": results,
        "summary": format_lane_summary(lane, status, elapsed_ms, inventory),
    }
    path.write_text(json.dumps(body, indent=2) + "\n", encoding="utf-8")
    latest = ARTIFACTS / f"{lane.lower()}-latest.json"
    latest.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return path


def run_lane(lane: str) -> tuple[str, int]:
    """Execute one lane. Returns (status, exit_code_contribution).

    exit_code_contribution: 0 PASS, 1 FAIL/INCOMPLETE, 2 PLATFORM-UNAVAILABLE
    """
    manifest = load_manifest()
    lane_def = manifest["lanes"][lane]
    requirement = lane_def["platform"]
    plat_status, plat_reason = check_lane_platform(requirement)

    started = time.perf_counter()

    if plat_status == "platform-unavailable":
        # Still write an honest orchestration ledger for FULL/HEAVY requests.
        if lane in {"full", "heavy"}:
            try:
                _write_orchestration_ledger()
            except RuntimeError as exc:
                print(f"[{lane.upper()}] ledger write failed: {exc}", file=sys.stderr)
        elapsed = int((time.perf_counter() - started) * 1000)
        inventory = evaluate_inventory(lane, [])  # zero executed
        # Force vacuous fields for the summary line.
        inventory["executed_app_coupled"] = 0
        inventory["executed_orchestration"] = 0
        inventory["executed_count"] = 0
        status = "PLATFORM-UNAVAILABLE"
        path = write_report(
            lane.upper(),
            [],
            elapsed,
            status=status,
            inventory=inventory,
            platform_reason=plat_reason,
        )
        print(format_lane_summary(lane, status, elapsed, inventory))
        print(f"    reason: {plat_reason}")
        print(f"    report={path}")
        _post_dashboard(
            {
                "lane": lane.upper(),
                "step": "platform_gate",
                "ok": False,
                "ms": elapsed,
                "message": f"PLATFORM-UNAVAILABLE ({inventory['executed_app_coupled']} app tests)",
            }
        )
        return status, 2

    if lane == "fast":
        results, executed = lane_fast()
    elif lane == "full":
        results, executed = lane_full_macos()
    else:
        results, executed = lane_heavy_macos()

    elapsed = int((time.perf_counter() - started) * 1000)
    inventory = evaluate_inventory(lane, executed)
    step_ok = all(r["ok"] for r in results) if results else False
    budget = int(lane_def["budgetMs"])
    if inventory["verdict"] != "PASS":
        status = inventory["verdict"]  # FAIL or INCOMPLETE
        code = 1
    elif not step_ok:
        status = "FAIL"
        code = 1
    else:
        status = "PASS"
        code = 0

    if elapsed > budget:
        emit_budget_breach(lane, elapsed, budget, results)
        status = "FAIL"
        code = 1

    path = write_report(
        lane.upper(),
        results,
        elapsed,
        status=status,
        inventory=inventory,
        platform_reason=plat_reason,
    )
    print(format_lane_summary(lane, status, elapsed, inventory))
    if inventory["reasons"]:
        for reason in inventory["reasons"]:
            print(f"    inventory: {reason}", file=sys.stderr)
    print(f"    report={path}")
    return status, code


def watch_loop() -> int:
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
            status, _code = run_lane("fast")
            _post_dashboard(
                {
                    "lane": "FAST",
                    "step": "watch_cycle",
                    "ok": status == "PASS",
                    "message": status,
                }
            )
        time.sleep(1.0)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lane", choices=["fast", "full", "heavy", "watch", "all"])
    args = parser.parse_args(argv)

    if args.lane == "watch":
        return watch_loop()

    lanes = ["fast", "full", "heavy"] if args.lane == "all" else [args.lane]
    codes = []
    for lane in lanes:
        _status, code = run_lane(lane)
        codes.append(code)
    # Prefer FAIL (1) over PLATFORM-UNAVAILABLE (2) over PASS (0).
    if any(c == 1 for c in codes):
        return 1
    if any(c == 2 for c in codes):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
