#!/bin/bash
# about: LuminaKit headless tests (no window, no sound). Arg: an XCTest filter, e.g. WP2ImportTests or WP2ImportTests/test_R19_relaunch_reopensTheFolder_decisionsKept; none = all.
# limit: 240
cd "$ROOT/LuminaKit" || exit 2
swift build || exit 1
if [ -n "${1:-}" ]; then swift test --filter "$1"; else swift test; fi
