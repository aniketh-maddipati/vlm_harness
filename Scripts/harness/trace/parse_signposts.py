#!/usr/bin/env python3
"""Parse os_signpost-style region lines into a committed numbers ledger."""
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

# Example line:
# signpost begin lumina.accept.crossfade id=1
# signpost end   lumina.accept.crossfade id=1 duration_ms=120 layout_passes=0 overshoot_pct=0.0
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


def evaluate(events: list[dict], spec: dict | None = None) -> dict:
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
            "samples": len(samples),
            "pass": False,
            "detail": "",
        }
        if not samples:
            entry["detail"] = "no samples"
            # Missing samples are soft-fail for HEAVY/FULL when app didn't run;
            # caller decides severity via require_samples.
            entry["pass"] = False
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
            # Allow ±1ms measurement jitter.
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
        "ok": ok,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "results": results,
    }


def write_ledger(report: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="Trace log path")
    parser.add_argument(
        "--ledger",
        type=Path,
        default=None,
        help="Ledger output path (default artifacts/harness/ledgers/<stamp>.json)",
    )
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Do not fail when signposts are absent (orchestration dry-run)",
    )
    args = parser.parse_args(argv)
    text = args.trace.read_text(encoding="utf-8")
    report = evaluate(parse_trace(text))
    ledger = args.ledger or LEDGER_DIR / "latest.json"
    write_ledger(report, ledger)
    print(json.dumps(report, indent=2))
    if args.allow_missing and all(r["detail"] == "no samples" for r in report["results"]):
        return 0
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
