#!/usr/bin/env python3
"""Chrome-strict golden compare (photograph regions masked).

Without --live: orchestration bookkeeping (tokens-hash store + metrics fixture).
With --live: STUB (F2) — pixel capture against running app is Swift-on-macOS
REQUIRED (owned-by-CP1).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import service as golden  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "chrome_metrics.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--live",
        action="store_true",
        help="App-coupled pixel/chrome capture (Swift-on-macOS; STUB until CP1)",
    )
    args = parser.parse_args(argv)
    if args.live:
        print(
            "STUB: run_chrome_diff.py --live — app-coupled chrome capture not wired yet "
            "(owned-by-CP1). Refusing vacuous PASS.",
            file=sys.stderr,
        )
        return 1
    if not FIXTURE.is_file():
        print(f"FAIL: missing {FIXTURE}", file=sys.stderr)
        return 1
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert "mask" in payload and "chrome" in payload
    digest = golden.tokens_hash()
    ref = golden.GoldenRef("chrome_metrics", digest)
    if not ref.approved_path.is_file():
        golden.propose("chrome_metrics", payload, digest=digest)
        golden.approve("chrome_metrics", digest=digest)
        print("run_chrome_diff.py: seeded approved chrome_metrics golden")
    result = golden.compare("chrome_metrics", payload, digest=digest)
    if not result["ok"]:
        print(f"FAIL: chrome golden {result}", file=sys.stderr)
        return 1
    print("run_chrome_diff.py: OK (orchestration bookkeeping)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
