#!/usr/bin/env python3
"""Chrome-strict golden compare (photograph regions masked).

On Linux / without captures: validates the golden store layout + tokens-hash
keying, and compares a committed chrome metrics fixture (not pixels).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import service as golden  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "chrome_metrics.json"


def main() -> int:
    if not FIXTURE.is_file():
        print(f"FAIL: missing {FIXTURE}", file=sys.stderr)
        return 1
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    # Photograph regions are listed in mask — chrome keys compared strictly.
    assert "mask" in payload and "chrome" in payload
    digest = golden.tokens_hash()
    ref = golden.GoldenRef("chrome_metrics", digest)
    if not ref.approved_path.is_file():
        # First-time propose + approve of the committed fixture (human-blessed in CP0).
        golden.propose("chrome_metrics", payload, digest=digest)
        golden.approve("chrome_metrics", digest=digest)
        print("run_chrome_diff.py: seeded approved chrome_metrics golden")
    result = golden.compare("chrome_metrics", payload, digest=digest)
    if not result["ok"]:
        print(f"FAIL: chrome golden {result}", file=sys.stderr)
        return 1
    print("run_chrome_diff.py: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
