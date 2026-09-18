#!/usr/bin/env python3
"""FULL gate: stable focus identity and progressive Metal presentation."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from render_gate_common import (
    measured_ledger,
    read_report,
    resolve_app,
    thresholds,
    write_json,
)
from run_live_raw_render import verify_fixture


def validate(report: dict, expected_extensions: set[str] | None = None) -> dict:
    limits = thresholds("hosted")
    failures: list[str] = []
    if report.get("status") != "passed" or int(report.get("failures", 1)) != 0:
        failures.append(
            f"runner status={report.get('status')!r} failures={report.get('failures')!r}"
        )

    scrub = report.get("rapidScrub")
    if not isinstance(scrub, dict):
        failures.append("missing rapidScrub")
        scrub = {}
    if scrub.get("blankSeen") is not False:
        failures.append("blank frame observed during scrub")
    draw = scrub.get("draw3Seconds")
    if not isinstance(draw, dict):
        failures.append("missing draw3Seconds")
        draw = {}
    samples = int(draw.get("sampleCount", 0))
    draw_p95 = float(draw.get("p95Ms", float("inf")))
    if samples <= 0:
        failures.append("draw3Seconds has no GPU-completion samples")
    draw_ceiling = float(limits["drawP95Ms"])
    if draw_p95 > draw_ceiling:
        failures.append(
            f"draw p95 {draw_p95:.1f}ms > hosted ceiling {draw_ceiling:.1f}ms"
        )

    navigation = report.get("navigation")
    if not isinstance(navigation, dict):
        failures.append("missing navigation")
        navigation = {}
    if navigation.get("blankAfterWait") is not False:
        failures.append("focused photo blank after navigation wait")

    stability = report.get("focusStability")
    if not isinstance(stability, dict):
        failures.append("missing focusStability")
        stability = {}
    required_true = (
        "identityStable",
        "fidelityMonotonic",
        "geometryStable",
        "authoritativeReachedDrawable",
    )
    for key in required_true:
        if stability.get(key) is not True:
            failures.append(f"{key} is not true")

    measured_extensions = {
        str(value).upper() for value in report.get("formatExtensions", [])
    }
    if expected_extensions:
        missing_extensions = sorted(expected_extensions - measured_extensions)
        if missing_extensions:
            failures.append(
                "progressive focus did not open " + ", ".join(missing_extensions)
            )

    if failures:
        raise RuntimeError("; ".join(failures))
    return {
        "drawP95Ms": draw_p95,
        "drawSampleCount": samples,
        "drawWindow": draw.get("window"),
        "navigationP95Ms": float(navigation.get("p95Ms", 0)),
        "formatExtensions": sorted(measured_extensions),
        **{key: True for key in required_true},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--derived-data", default="DD")
    parser.add_argument("--fixture-root")
    parser.add_argument("--fixture-tier", choices=("hosted", "full"), default="hosted")
    parser.add_argument("--output-dir")
    parser.add_argument("--parse-report")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    fixture_value = (
        args.fixture_root
        or os.environ.get("LUMINA_RAW_FIXTURE_ROOT")
        or os.environ.get("LUMINA_DEVELOP_RAW_DIR")
    )
    fixture = Path(fixture_value).expanduser() if fixture_value else None
    try:
        if args.parse_report:
            report_path = Path(args.parse_report)
        else:
            if fixture is None:
                raise RuntimeError(
                    "BLOCKED: set LUMINA_RAW_FIXTURE_ROOT to a verified RAW bundle"
                )
            verify_fixture(project_root, fixture, args.fixture_tier)
            derived = Path(args.derived_data)
            if not derived.is_absolute():
                derived = project_root / derived
            executable = resolve_app(project_root, derived)
            output = Path(args.output_dir) if args.output_dir else (
                project_root / "artifacts" / "harness" / "runs" / "progressive-focus-live"
            )
            output.mkdir(parents=True, exist_ok=True)
            proc = subprocess.run(
                [
                    str(executable),
                    "--p0-edit-live",
                    str(output),
                    "--p0-open",
                    str(fixture),
                ],
                cwd=str(project_root),
                timeout=360,
            )
            if proc.returncode != 0:
                raise RuntimeError(f"P0EditLiveRunner exited {proc.returncode}")
            report_path = output / "p0_edit_live_report.json"

        expected_extensions = None
        if not args.parse_report:
            expected_extensions = (
                {"ARW", "CR3", "DNG"}
                if args.fixture_tier == "hosted"
                else {"ARW", "CR3", "NEF", "RAF", "DNG", "HEIC"}
            )
        metrics = validate(
            read_report(report_path),
            expected_extensions=expected_extensions,
        )
        ledger = (
            project_root
            / "artifacts"
            / "harness"
            / "ledgers"
            / "render-focus-measured.json"
        )
        write_json(
            ledger,
            measured_ledger(
                "progressive_focus_live",
                fixture or Path("parse-report"),
                metrics,
            ),
        )
        print(
            "progressive_focus_live: OK "
            f"(draw p95 {metrics['drawP95Ms']:.1f}ms, n={metrics['drawSampleCount']})"
        )
        return 0
    except (RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
        print(f"FAIL: progressive_focus_live: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
