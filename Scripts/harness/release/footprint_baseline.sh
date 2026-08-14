#!/usr/bin/env bash
# macOS Release footprint baseline — app size, linked frameworks, symbol weight.
# Writes artifacts/harness/footprint/latest.json for CI ratchet on a Mac runner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "footprint_baseline: PLATFORM-UNAVAILABLE (macOS + Xcode required)" >&2
  exit 2
fi

DERIVED="${DERIVED_DATA_PATH:-$ROOT/artifacts/harness/build-cache/footprint}"
CONFIG="${CONFIGURATION:-Release}"

python3 "$ROOT/Scripts/harness/build_cache.py" --ensure-build-for-testing >/dev/null

xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' build >/tmp/lumina-footprint-build.log 2>&1

APP="$DERIVED/Build/Products/$CONFIG/Lumina.app"
BIN="$APP/Contents/MacOS/Lumina"
OUT="$ROOT/artifacts/harness/footprint"
mkdir -p "$OUT"

APP_BYTES=$(du -sk "$APP" | awk '{print $1 * 1024}')
BIN_BYTES=$(stat -f%z "$BIN")
LINKED=$(otool -L "$BIN" | tail -n +2 | wc -l | tr -d ' ')
TEXT_BYTES=$(size -m "$BIN" 2>/dev/null | awk '/__TEXT/ {print $1}' || echo 0)

python3 - <<PY
import json, datetime, pathlib
payload = {
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "configuration": "$CONFIG",
    "app_bytes": int("$APP_BYTES"),
    "executable_bytes": int("$BIN_BYTES"),
    "linked_dylibs": int("$LINKED"),
    "text_segment_kb": int("$TEXT_BYTES") if "$TEXT_BYTES".isdigit() else 0,
}
path = pathlib.Path("$OUT/latest.json")
path.write_text(json.dumps(payload, indent=2) + "\\n", encoding="utf-8")
print(f"footprint_baseline: OK app={payload['app_bytes']} exec={payload['executable_bytes']} linked={payload['linked_dylibs']}")
print(f"    report={path}")
PY
