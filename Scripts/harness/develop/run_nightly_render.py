#!/usr/bin/env python3
"""HEAVY gate: fixed-hardware RAW/render stress and rolling regression policy."""
from __future__ import annotations

import json
import os
import platform
import subprocess
import sys
from pathlib import Path

from render_gate_common import read_report, thresholds, write_json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def run(command: list[str], env: dict[str, str] | None = None) -> None:
    proc = subprocess.run(command, cwd=str(ROOT), env=env)
    if proc.returncode != 0:
        raise RuntimeError(f"{' '.join(command)} exited {proc.returncode}")


def compare_with_baseline(metrics: dict[str, float]) -> None:
    baseline_value = os.environ.get("LUMINA_RENDER_BASELINE")
    if not baseline_value:
        print("render nightly: no LUMINA_RENDER_BASELINE; recording measurements only")
        return
    baseline = read_report(Path(baseline_value))
    expected = baseline.get("metrics")
    if not isinstance(expected, dict):
        raise RuntimeError("nightly baseline has no metrics object")

    policy = thresholds("nightly")
    fraction = float(policy["relativeRegressionFraction"])
    required = int(policy["consecutiveRegressionsToFail"])
    state_value = (
        os.environ.get("LUMINA_RENDER_STATE_PATH")
        or "~/Library/Caches/Lumina/render-regression-state.json"
    )
    state_path = Path(state_value).expanduser()
    state = read_report(state_path) if state_path.is_file() else {"counts": {}}
    counts = state.setdefault("counts", {})
    failed: list[str] = []
    for key, current in metrics.items():
        prior = expected.get(key)
        if not isinstance(prior, (int, float)) or prior <= 0:
            continue
        regressed = current > float(prior) * (1 + fraction)
        counts[key] = int(counts.get(key, 0)) + 1 if regressed else 0
        if counts[key] >= required:
            failed.append(
                f"{key}={current:.2f} > baseline {float(prior):.2f} "
                f"by >{fraction:.0%} for {counts[key]} runs"
            )
    write_json(state_path, state)
    if failed:
        raise RuntimeError("; ".join(failed))


def main() -> int:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        print("render nightly: PLATFORM-UNAVAILABLE (requires Apple Silicon macOS)", file=sys.stderr)
        return 2
    fixture_value = os.environ.get("LUMINA_RAW_FIXTURE_ROOT")
    if not fixture_value:
        print("FAIL: render nightly: BLOCKED — LUMINA_RAW_FIXTURE_ROOT missing", file=sys.stderr)
        return 1
    fixture = Path(fixture_value).expanduser().resolve()
    try:
        run(
            [
                sys.executable,
                str(ROOT / "Scripts" / "fixtures" / "verify_raw_fixture_bundle.py"),
                "--root",
                str(fixture),
                "--tier",
                "full",
            ]
        )
        run(
            [
                sys.executable,
                str(ROOT / "Scripts" / "harness" / "build_cache.py"),
                "--ensure-build-for-testing",
            ]
        )
        derived = subprocess.check_output(
            [
                sys.executable,
                str(ROOT / "Scripts" / "harness" / "build_cache.py"),
                "--derived-data-path",
            ],
            cwd=str(ROOT),
            text=True,
        ).strip()
        run(
            [
                sys.executable,
                str(HERE / "run_live_raw_render.py"),
                "--project-root",
                str(ROOT),
                "--derived-data",
                derived,
                "--fixture-root",
                str(fixture),
                "--fixture-tier",
                "full",
            ]
        )
        stress_env = os.environ.copy()
        stress_env["LUMINA_RENDER_STRESS_SECONDS"] = "60"
        stress_env["LUMINA_RENDER_NAVIGATION_COUNT"] = "500"
        run(
            [
                sys.executable,
                str(HERE / "run_live_progressive_focus.py"),
                "--project-root",
                str(ROOT),
                "--derived-data",
                derived,
                "--fixture-root",
                str(fixture),
                "--fixture-tier",
                "full",
            ],
            env=stress_env,
        )

        executable = Path(derived) / "Build" / "Products" / "Debug" / "Lumina.app" / "Contents" / "MacOS" / "Lumina"
        benchmark = ROOT / "artifacts" / "harness" / "runs" / "raw-backend-benchmark.json"
        benchmark.parent.mkdir(parents=True, exist_ok=True)
        backend_env = os.environ.copy()
        backend_env["LUMINA_DEVELOP_RAW_DIR"] = str(fixture)
        run(
            [str(executable), "--raw-backend-benchmark", str(benchmark)],
            env=backend_env,
        )

        raw = read_report(
            ROOT / "artifacts" / "harness" / "ledgers" / "render-raw-measured.json"
        )["metrics"]
        focus = read_report(
            ROOT / "artifacts" / "harness" / "ledgers" / "render-focus-measured.json"
        )["metrics"]
        current = {
            "interactiveColdMs": float(raw["interactiveColdMs"]),
            "interactiveScrubP95Ms": float(raw["interactiveScrubP95Ms"]),
            "settledMs": float(raw["settledMs"]),
            "drawP95Ms": float(focus["drawP95Ms"]),
            "navigationP95Ms": float(focus["navigationP95Ms"]),
        }
        compare_with_baseline(current)
        write_json(
            ROOT / "artifacts" / "harness" / "ledgers" / "render-nightly-measured.json",
            {
                "schemaVersion": 1,
                "mode": "measured",
                "gates_active": True,
                "fixtureTier": "full",
                "host": {
                    "machine": platform.machine(),
                    "model": subprocess.check_output(
                        ["sysctl", "-n", "hw.model"], text=True
                    ).strip(),
                    "macOS": platform.mac_ver()[0],
                },
                "metrics": current,
            },
        )
        print("progressive_render_stability: OK")
        return 0
    except (RuntimeError, KeyError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: progressive_render_stability: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
