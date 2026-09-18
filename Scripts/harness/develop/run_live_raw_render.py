#!/usr/bin/env python3
"""FULL gate: real RAW cache, fidelity, and resolution measurements."""
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


def validate(report: dict, expected_extensions: set[str] | None = None) -> dict:
    limits = thresholds("hosted")
    failures: list[str] = []

    def validate_fidelity(item: dict, label: str) -> dict:
        fidelity = item.get("fidelity")
        if not isinstance(fidelity, dict) or fidelity.get("status") != "measured":
            failures.append(f"{label}: fidelity not measured")
            return {}
        checks = (
            ("deltaE2000Mean", "<=", float(limits["fidelityDeltaEMeanMax"])),
            ("deltaE2000P95", "<=", float(limits["fidelityDeltaEP95Max"])),
            ("ssimLuma", ">=", float(limits["fidelitySSIMMin"])),
            ("maeR_8bit", "<=", float(limits["fidelityChannelMAEMax"])),
            ("maeG_8bit", "<=", float(limits["fidelityChannelMAEMax"])),
            ("maeB_8bit", "<=", float(limits["fidelityChannelMAEMax"])),
        )
        for key, comparison, bound in checks:
            value = fidelity.get(key)
            if not isinstance(value, (int, float)):
                failures.append(f"{label}: missing fidelity {key}")
            elif comparison == "<=" and float(value) > bound:
                failures.append(f"{label}: {key} {value} > {bound}")
            elif comparison == ">=" and float(value) < bound:
                failures.append(f"{label}: {key} {value} < {bound}")
        preview_clip = fidelity.get("clippedFractionPreview")
        export_clip = fidelity.get("clippedFractionExport")
        if not isinstance(preview_clip, (int, float)) or not isinstance(
            export_clip, (int, float)
        ):
            failures.append(f"{label}: clipping fractions missing")
        elif abs(float(preview_clip) - float(export_clip)) > float(
            limits["fidelityClippedFractionDeltaMax"]
        ):
            failures.append(f"{label}: clipping fraction drift too large")
        return fidelity
    if int(report.get("failures", 1)) != 0:
        failures.append(f"runner failures={report.get('failures')!r}")
    live = report.get("live")
    if not isinstance(live, dict):
        failures.append("missing live object")
        live = {}
    if live.get("status") == "blocked":
        failures.append(f"blocked: {live.get('reason', 'unknown')}")
    primary_fidelity = validate_fidelity(live, "primary")

    scrub = live.get("interactiveScrub")
    if not isinstance(scrub, dict):
        failures.append("missing interactiveScrub")
        scrub = {}
    count = int(scrub.get("count", 0))
    hits = int(scrub.get("rawStageCacheHits", 0))
    p95 = float(scrub.get("p95Ms", float("inf")))
    minimum_samples = int(limits["minimumRawStageSamples"])
    minimum_hits = int(limits["minimumRawStageHits"])
    if count < minimum_samples or hits < minimum_hits:
        failures.append(
            f"RAW-stage reuse {hits}/{count}; "
            f"require >={minimum_hits}/{minimum_samples}"
        )
    scrub_ceiling = float(limits["interactiveScrubP95Ms"])
    if p95 > scrub_ceiling:
        failures.append(
            f"interactive scrub p95 {p95:.1f}ms > hosted ceiling {scrub_ceiling:.1f}ms"
        )

    required_true = (
        "interactiveExposureReusesRawStage",
        "interactiveWBReusesRawStage",
        "interactiveNRInvalidates",
        "settledRawIntentInvalidates",
        "interactiveStageMaterialized",
        "authoritativeStageStayedLazy",
    )
    for key in required_true:
        if live.get(key) is not True:
            failures.append(f"{key} is not true")

    cold = float(live.get("interactiveColdMs", float("inf")))
    settled = float(live.get("settledMs", float("inf")))
    cold_ceiling = float(limits["interactiveColdMs"])
    settled_ceiling = float(limits["settledMs"])
    if cold > cold_ceiling:
        failures.append(
            f"interactive cold {cold:.1f}ms > hosted ceiling {cold_ceiling:.1f}ms"
        )
    if settled > settled_ceiling:
        failures.append(
            f"settled {settled:.1f}ms > hosted ceiling {settled_ceiling:.1f}ms"
        )

    fleet = report.get("fleet")
    if not isinstance(fleet, list) or not fleet:
        raise RuntimeError("missing non-empty fleet measurements")
    for index, entry in enumerate(fleet):
        item = entry.get("live") if isinstance(entry, dict) else None
        if not isinstance(item, dict) or item.get("interactiveStageMaterialized") is not True:
            raise RuntimeError("fleet entry missing interactive texture materialization")
        validate_fidelity(item, f"fleet[{index}]")
    measured_extensions = {
        Path(str(entry.get("fixture", ""))).suffix.upper()
        for entry in fleet
        if isinstance(entry, dict)
    }
    if expected_extensions:
        missing_extensions = sorted(expected_extensions - measured_extensions)
        if missing_extensions:
            raise RuntimeError(
                "fleet measurements missing " + ", ".join(missing_extensions)
            )
    if failures:
        raise RuntimeError("; ".join(failures))
    return {
        "interactiveColdMs": cold,
        "interactiveScrubP95Ms": p95,
        "rawStageCacheHits": hits,
        "rawStageSampleCount": count,
        "settledMs": settled,
        "interactiveStageMaterialized": True,
        "fleetCount": len(fleet),
        "fleetExtensions": sorted(measured_extensions),
        "fidelityDeltaEMean": primary_fidelity.get("deltaE2000Mean"),
        "fidelityDeltaEP95": primary_fidelity.get("deltaE2000P95"),
        "fidelitySSIM": primary_fidelity.get("ssimLuma"),
    }


def verify_fixture(project_root: Path, root: Path, tier: str) -> None:
    verifier = project_root / "Scripts" / "fixtures" / "verify_raw_fixture_bundle.py"
    proc = subprocess.run(
        [sys.executable, str(verifier), "--root", str(root), "--tier", tier],
        cwd=str(project_root),
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout).strip())


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
                project_root / "artifacts" / "harness" / "runs" / "raw-render-live"
            )
            output.mkdir(parents=True, exist_ok=True)
            env = os.environ.copy()
            env["LUMINA_DEVELOP_RAW_DIR"] = str(fixture)
            env["LUMINA_RAW_HARNESS_LIMIT"] = (
                "3" if args.fixture_tier == "hosted" else "5"
            )
            proc = subprocess.run(
                [str(executable), "--raw-harness", str(output)],
                cwd=str(project_root),
                env=env,
                timeout=240,
            )
            if proc.returncode != 0:
                raise RuntimeError(f"RawHarnessRunner exited {proc.returncode}")
            report_path = output / "raw_harness_report.json"

        expected_extensions = None
        if not args.parse_report:
            expected_extensions = (
                {".ARW", ".CR3", ".DNG"}
                if args.fixture_tier == "hosted"
                else {".ARW", ".CR3", ".NEF", ".RAF", ".DNG"}
            )
        metrics = validate(
            read_report(report_path),
            expected_extensions=expected_extensions,
        )
        ledger = project_root / "artifacts" / "harness" / "ledgers" / "render-raw-measured.json"
        write_json(
            ledger,
            measured_ledger("raw_render_live", fixture or Path("parse-report"), metrics),
        )
        print(
            "raw_render_live: OK "
            f"(scrub p95 {metrics['interactiveScrubP95Ms']:.1f}ms, "
            f"hits {metrics['rawStageCacheHits']}/{metrics['rawStageSampleCount']})"
        )
        return 0
    except (RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
        print(f"FAIL: raw_render_live: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
