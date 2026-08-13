#!/bin/bash
# HEAVY — RAM tier gate: peak resident footprint across fixture tiers (W6).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LEDGER="${1:-$ROOT/artifacts/harness/ledgers/ram-tiers.json}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "PLATFORM-UNAVAILABLE: ram_tier_runs requires macOS Apple Silicon" >&2
  exit 2
fi

mkdir -p "$(dirname "$LEDGER")"

APP="${LUMINA_RAM_HARNESS_APP:-}"
if [[ -z "$APP" ]]; then
  xcodebuild -project "$ROOT/Lumina.xcodeproj" -scheme Lumina -configuration Debug \
    -destination 'platform=macOS' build >/tmp/lumina-ram-build.log 2>&1
  APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/Lumina.app' -print -quit 2>/dev/null || true)"
fi

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "FAIL: Lumina.app not found — set LUMINA_RAM_HARNESS_APP or build Debug first" >&2
  exit 1
fi

"$APP/Contents/MacOS/Lumina" --ram-harness "$LEDGER"
exit $?
