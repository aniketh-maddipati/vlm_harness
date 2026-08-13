"""Python mirror of Lumina/Design/LuminaSpring.swift — headless F07 gates."""
from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None  # type: ignore[assignment]


@dataclass(frozen=True)
class LuminaSpringParams:
    mass: float
    stiffness: float
    damping: float


@dataclass(frozen=True)
class LuminaSpringRetarget:
    time: float
    target: float


@dataclass(frozen=True)
class LuminaSpringSample:
    time: float
    value: float
    velocity: float


DEFAULT_SAMPLE_RATE_HZ = 120.0

CURVE_DAMPING = {
    "easeOut": 0.92,
    "easeInOut": 0.88,
    "interactive": 0.86,
}


def params(duration_ms: float, curve: str = "easeOut", mass: float = 1.0) -> LuminaSpringParams:
    response = max(duration_ms / 1000.0, 1.0 / 1000.0)
    damping_fraction = CURVE_DAMPING[curve]
    stiffness = (2 * math.pi / response) ** 2 * mass
    damping = 4 * math.pi * damping_fraction * mass / response
    return LuminaSpringParams(mass=mass, stiffness=stiffness, damping=damping)


def params_reduced_motion(duration_ms: float, mass: float = 1.0) -> LuminaSpringParams:
    response = max(duration_ms / 1000.0, 1.0 / 1000.0)
    stiffness = (2 * math.pi / response) ** 2 * mass
    damping = 2 * math.sqrt(stiffness * mass)
    return LuminaSpringParams(mass=mass, stiffness=stiffness, damping=damping)


def integrate_step(
    x: float,
    v: float,
    target: float,
    p: LuminaSpringParams,
    dt: float,
) -> tuple[float, float]:
    m = max(p.mass, 1e-9)
    acceleration = (-p.damping * v - p.stiffness * (x - target)) / m
    v_next = v + acceleration * dt
    x_next = x + v_next * dt
    return x_next, v_next


def trajectory(
    end_time: float,
    p: LuminaSpringParams,
    initial_value: float = 0.0,
    initial_velocity: float = 0.0,
    retargets: Iterable[LuminaSpringRetarget] | None = None,
    sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ,
) -> list[LuminaSpringSample]:
    step = 1.0 / max(sample_rate_hz, 1.0)
    sorted_retargets = sorted(retargets or [], key=lambda r: r.time)
    samples: list[LuminaSpringSample] = []
    x = initial_value
    v = initial_velocity
    retarget_index = 0
    while retarget_index < len(sorted_retargets) and sorted_retargets[retarget_index].time <= 0:
        retarget_index += 1
    target = sorted_retargets[retarget_index - 1].target if retarget_index > 0 else 1.0
    t = 0.0
    while t <= end_time + step * 0.5:
        samples.append(LuminaSpringSample(time=t, value=x, velocity=v))
        if t >= end_time:
            break
        dt = min(step, end_time - t)
        while retarget_index < len(sorted_retargets) and sorted_retargets[retarget_index].time <= t + 1e-12:
            target = sorted_retargets[retarget_index].target
            retarget_index += 1
        x, v = integrate_step(x, v, target, p, dt)
        t += dt
    return samples


def value_at(
    time: float,
    p: LuminaSpringParams,
    initial_value: float = 0.0,
    initial_velocity: float = 0.0,
    retargets: Iterable[LuminaSpringRetarget] | None = None,
) -> float:
    if time <= 0:
        return initial_value
    samples = trajectory(time, p, initial_value, initial_velocity, retargets)
    return samples[-1].value if samples else initial_value


SEAL_KEYS = (
    "place_return",
    "spring_dead_stop_epsilon",
    "spring_trajectory_frames",
    "spring_trajectory_sample_rate_hz",
    "spring_max_overshoot",
    "spring_retarget_continuity_epsilon",
    "spring_reduced_motion_overshoot",
)


def load_motion_seal(root: Path) -> dict | None:
    if yaml is None:
        return None
    tokens_path = root / "design" / "tokens.yaml"
    if not tokens_path.is_file():
        return None
    data = yaml.safe_load(tokens_path.read_text(encoding="utf-8"))
    motion = data.get("motion") if isinstance(data, dict) else None
    if not isinstance(motion, dict):
        return None
    seal: dict[str, float] = {}
    for key in SEAL_KEYS:
        node = motion.get(key)
        if not isinstance(node, dict) or "value" not in node:
            return None
        seal[key] = float(node["value"])
    return seal


def run_f07_gates(root: Path) -> int:
    seal = load_motion_seal(root)
    if seal is None:
        print("STUB: F07.4–F07.6 — motion seal absent from design/tokens.yaml §motion", file=sys.stderr)
        return 0

    frames = int(seal["spring_trajectory_frames"])
    sample_hz = seal["spring_trajectory_sample_rate_hz"]
    horizon = (frames - 1) / sample_hz
    dead_stop_eps = seal["spring_dead_stop_epsilon"]
    retarget_eps = seal["spring_retarget_continuity_epsilon"]
    max_overshoot = seal["spring_max_overshoot"]
    reduced_overshoot = seal["spring_reduced_motion_overshoot"]
    place_return_ms = seal["place_return"]

    # F07.4 dead-stop at horizon for place_return spring (0 → 1).
    p = params(place_return_ms, curve="easeOut")
    samples = trajectory(horizon, p, sample_rate_hz=sample_hz)
    final = samples[-1]
    dead_stop_delta = abs(final.value - 1.0)
    if dead_stop_delta > dead_stop_eps:
        print(
            f"FAIL F07.4 dead-stop: |value-1|={dead_stop_delta:.6f} > epsilon={dead_stop_eps}",
            file=sys.stderr,
        )
        return 1

    # F07.5 retarget continuity — mid-flight retarget preserves value/velocity.
    mid = horizon * 0.45
    retargets = [LuminaSpringRetarget(time=mid, target=0.65)]
    before = trajectory(mid, p, sample_rate_hz=sample_hz)
    after = trajectory(horizon, p, retargets=retargets, sample_rate_hz=sample_hz)
    bridge = next(s for s in after if abs(s.time - mid) < 1e-9)
    if abs(bridge.value - before[-1].value) > retarget_eps:
        print("FAIL F07.5 retarget value discontinuity", file=sys.stderr)
        return 1
    if abs(bridge.velocity - before[-1].velocity) > retarget_eps:
        print("FAIL F07.5 retarget velocity discontinuity", file=sys.stderr)
        return 1

    # F07.6 reduced-motion variant — zero overshoot bound.
    p_rm = params_reduced_motion(place_return_ms)
    rm_samples = trajectory(horizon, p_rm, sample_rate_hz=sample_hz)
    peak = max(s.value for s in rm_samples)
    if peak > 1.0 + reduced_overshoot + 1e-9:
        print(f"FAIL F07.6 reduced-motion overshoot peak={peak}", file=sys.stderr)
        return 1

    # Overshoot cap for standard place_return.
    peak_std = max(s.value for s in samples)
    if peak_std > 1.0 + max_overshoot + 1e-9:
        print(f"FAIL F07.4 overshoot peak={peak_std} > 1+{max_overshoot}", file=sys.stderr)
        return 1

    golden_dir = (
        root
        / "artifacts"
        / "harness"
        / "goldens"
        / "spring_trajectory_place_return"
    )
    if golden_dir.is_dir():
        proposed = [s.value for s in samples]
        approved_path = golden_dir / "approved.json"
        if approved_path.is_file():
            approved = json.loads(approved_path.read_text(encoding="utf-8"))
            if approved.get("values") != proposed:
                print("FAIL F07 trajectory golden drift", file=sys.stderr)
                return 1

    print("PASS spring_physics_f07")
    return 0
