#!/usr/bin/env python3
"""Prompt-9 contract audit — delegates to hi-fi audit gate v2 (H8)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    script = ROOT / "Scripts" / "audit_hifi.py"
    result = subprocess.run([sys.executable, str(script)], cwd=ROOT)
    if result.returncode == 0:
        print("Prompt-9 audit: all checks passed")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
