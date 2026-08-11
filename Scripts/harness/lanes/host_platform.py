#!/usr/bin/env python3
"""Platform requirements for harness lanes (F3).

FULL and HEAVY require macOS on Apple Silicon (design/mvp-test-plan.md fleet:
AS / macOS 14+). Linux may run FAST orchestration only.
"""
from __future__ import annotations

import os
import platform
import subprocess
from typing import Literal

PlatformStatus = Literal["ok", "platform-unavailable"]


def is_darwin() -> bool:
    return platform.system() == "Darwin"


def is_apple_silicon() -> bool:
    if not is_darwin():
        return False
    machine = platform.machine().lower()
    if machine in {"arm64", "aarch64"}:
        return True
    # Rosetta: uname -m may report x86_64; sysctl still sees Apple silicon.
    try:
        out = subprocess.check_output(
            ["sysctl", "-n", "hw.optional.arm64"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        return out == "1"
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return False


def macos_version_ok() -> bool:
    if not is_darwin():
        return False
    # macOS 14+ (Sonoma). platform.mac_ver() → e.g. ('14.5', …)
    ver = platform.mac_ver()[0]
    if not ver:
        return False
    major = int(ver.split(".")[0])
    return major >= 14


def check_lane_platform(requirement: str) -> tuple[PlatformStatus, str]:
    """Return (status, reason). requirement: 'any' | 'macos-apple-silicon'."""
    if requirement == "any":
        return "ok", "any platform"
    if requirement == "macos-apple-silicon":
        # Override for local forced testing of the unavailable path.
        if os.environ.get("LUMINA_HARNESS_FORCE_PLATFORM_UNAVAILABLE") == "1":
            return "platform-unavailable", "forced by LUMINA_HARNESS_FORCE_PLATFORM_UNAVAILABLE=1"
        if not is_darwin():
            return (
                "platform-unavailable",
                "FULL/HEAVY require macOS Apple Silicon (design/mvp-test-plan.md); this host is not Darwin",
            )
        if not is_apple_silicon():
            return (
                "platform-unavailable",
                "FULL/HEAVY require Apple Silicon; Intel Macs are out of fleet (D65 / A1)",
            )
        if not macos_version_ok():
            return (
                "platform-unavailable",
                "FULL/HEAVY require macOS 14+ (mvp-test-plan floor)",
            )
        return "ok", "macos-apple-silicon"
    return "platform-unavailable", f"unknown platform requirement: {requirement}"
