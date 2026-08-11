#!/usr/bin/env python3
"""Parse os_signpost-style region lines into a committed numbers ledger.

F4 ledger honesty:
- Orchestration-only runs write every acceptance number as UNMEASURED.
- Acceptance gates activate only when a macOS measured run populates samples.
- Fixture sample logs may unit-test the parser; they must not bless a lane PASS.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
NUMBERS = Path(__file__).resolve().parent / "acceptance_numbers.json"
LEDGER_DIR = ROOT / "artifacts" / "harness" / "ledgers"

END_RE = re.compile(
    r"signpost\s+end\s+(?P<name>lumina\.accept\.\S+)\s+"
    r"id=(?P<id>\S+)\s+duration_ms=(?P<ms>[0-9.]+)"
    r"(?:\s+layout_passes=(?P<layout>\d+))?"
    r"(?:\s+overshoot_pct=(?P<overshoot>[0-9.]+))?"
)


def load_spec() -> dict:
    return json.loads(NUMBERS.read_text(encoding="utf-8"))


def parse_trace(text: str) -> list[dict]:
    events = []
    for line in text.splitlines():
        m = END_RE.search(line)
        if not m:
            continue
        events.append(
            {
                "name": m.group("name"),
                "id": m.group("id"),
                "duration_ms": float(m.group("ms")),
                "layout_passes": int(m.group("layout")) if m.group("layout") is not None else None,
                "overshoot_pct": float(m.group("overshoot")) if m.group("overshoot") is not None else None,
            }
        )
    return events


def orchestration_ledger(spec: dict | None = None) -> dict:
    """F4: honest ledger when no acceptance numbers were measured."""
    spec = spec or load_spec()
    results = []
    for item in spec["numbers"]:
        results.append(
            {
                "name": item["name"],
                "signpost": item["signpost"],
                "status": "UNMEASURED",
                "samples": 0,
                "pass": None,
                "detail": "orchestration-only — acceptance gate inactive until macOS measured run",
                "notes": item.get("notes"),
            }
        )
    return {
        "mode": "orchestration-only",
        "gates_active": False,
        "ok": None,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "results": results,
    }


def evaluate(events: list[dict], spec: dict | None = None) -> dict:
    """Evaluate a *measured* trace. Empty samples → fail (not UNMEASURED).

    Callers that have not measured must use orchestration_ledger() instead.
    """
    spec = spec or load_spec()
    by_name: dict[str, list[dict]] = {}
    for ev in events:
        by_name.setdefault(ev["name"], []).append(ev)
    results = []
    ok = True
    for item in spec["numbers"]:
        signpost = item["signpost"]
        samples = by_name.get(signpost) or []
        entry = {
            "name": item["name"],
            "signpost": signpost,
            "status": "MEASURED" if samples else "MISSING",
            "samples": len(samples),
            "pass": False,
            "detail": "",
        }
        if not samples:
            entry["detail"] = "no samples in measured trace"
            results.append(entry)
            ok = False
            continue
        durations = [s["duration_ms"] for s in samples]
        p95 = sorted(durations)[max(0, int(len(durations) * 0.95) - 1)]
        entry["p95_ms"] = p95
        failures = []
        if "maxMs" in item and p95 > float(item["maxMs"]):
            failures.append(f"p95 {p95} > max {item['maxMs']}")
        if "exactMs" in item:
            if any(abs(d - float(item["exactMs"])) > 1.0 for d in durations):
                failures.append(f"duration not {item['exactMs']}±1ms: {durations}")
        if item.get("zeroLayoutPasses"):
            if any((s.get("layout_passes") or 0) != 0 for s in samples):
                failures.append("layout_passes != 0")
        if "maxOvershootPct" in item:
            if any((s.get("overshoot_pct") or 0) > float(item["maxOvershootPct"]) for s in samples):
                failures.append("overshoot")
        entry["pass"] = not failures
        entry["detail"] = "ok" if entry["pass"] else "; ".join(failures)
        if not entry["pass"]:
            ok = False
        results.append(entry)
    return {
        "mode": "measured",
        "gates_active": True,
        "ok": ok,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "results": results,
    }


def write_ledger(report: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "trace",
        type=Path,
        nargs="?",
        default=None,
        help="Measured trace log path (omit with --orchestration-only)",
    )
    parser.add_argument(
        "--ledger",
        type=Path,
        default=None,
        help="Ledger output path",
    )
    parser.add_argument(
        "--orchestration-only",
        action="store_true",
        help="Write UNMEASURED ledger; do not activate acceptance gates",
    )
    args = parser.parse_args(argv)

    if args.orchestration_only:
        report = orchestration_ledger()
        ledger = args.ledger or LEDGER_DIR / "orchestration-only.json"
        write_ledger(report, ledger)
        print(json.dumps(report, indent=2))
        # Orchestration-only is an honest bookkeeping success (gates inactive).
        return 0

    if args.trace is None:
        print("FAIL: trace path required unless --orchestration-only", file=sys.stderr)
        return 1
    text = args.trace.read_text(encoding="utf-8")
    report = evaluate(parse_trace(text))
    ledger = args.ledger or LEDGER_DIR / "latest.json"
    write_ledger(report, ledger)
    print(json.dumps(report, indent=2))
    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
