#!/bin/bash
# Developer compile rot-guard — collect every xcodebuild error in one pass.
# macOS + Xcode only. Continues after errors so one file does not hide the rest.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec python3 "$ROOT/Scripts/harness/lint/xcode_compile.py" "$@"
