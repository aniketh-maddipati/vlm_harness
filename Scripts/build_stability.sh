#!/bin/bash
# Deterministic clean-build loop for supported Apple Silicon development Macs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "build_stability: PLATFORM-UNAVAILABLE (need Apple Silicon macOS + Xcode)" >&2
  exit 2
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "build_stability: PLATFORM-UNAVAILABLE (need arm64; found $(uname -m))" >&2
  exit 2
fi

DERIVED="${BUILD_STABILITY_DERIVED_DATA:-${TMPDIR:-/tmp}/lumina-build-stability}"
LOG_DIR="$ROOT/artifacts/harness/runs/build-stability"
mkdir -p "$LOG_DIR"

assert_clean() {
  local dirty
  dirty="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$dirty" ]]; then
    echo "build_stability: FAIL — working tree is not clean" >&2
    echo "$dirty" >&2
    return 1
  fi
}

run_release_check() {
  local label="$1"
  shift
  set +e
  "$@"
  local code=$?
  set -e
  case "$code" in
    0) ;;
    2) echo "build_stability: BLOCKED — $label reported PLATFORM-UNAVAILABLE" ;;
    *) echo "build_stability: FAIL — $label exited $code" >&2; return "$code" ;;
  esac
}

echo "=== Lumina build stability ==="
echo "commit=$(git rev-parse HEAD)"
sw_vers
xcodebuild -version
xcrun swift --version
echo "architecture=$(uname -m)"
echo "derivedData=$DERIVED"

assert_clean

for round in 1 2; do
  echo ""
  echo "=== Round $round of 2 ==="
  rm -rf "$DERIVED"

  python3 Scripts/harness/run.py fast

  xcodebuild -project Lumina.xcodeproj -scheme Lumina \
    -configuration Debug -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS,arch=arm64' clean build

  xcodebuild -project Lumina.xcodeproj -scheme Lumina \
    -configuration Debug -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS,arch=arm64' build-for-testing

  set -o pipefail
  xcodebuild -project Lumina.xcodeproj -scheme Lumina \
    -configuration Debug -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:LuminaLogicTests test-without-building \
    2>&1 | tee "$LOG_DIR/logic-round-$round.log"

  bash Scripts/compile_check.sh \
    --project-root "$ROOT" \
    --derived-data "$DERIVED"

  xcodebuild -project Lumina.xcodeproj -scheme Lumina \
    -configuration Release -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS,arch=arm64' build

  # The playground shares the source tree. Its Release configuration must not
  # expose a fence mismatch hidden by the scheme's Debug-only Archive action.
  python3 Scripts/harness/lint/xcode_compile.py \
    --project-root "$ROOT" \
    --derived-data "$DERIVED-playground" \
    --scheme LuminaPlayground \
    --configuration Release \
    --action build

  RELEASE_APP="$DERIVED/Build/Products/Release/Lumina.app"
  python3 Scripts/harness/release/f11_hooks_absent.py --app "$RELEASE_APP"
  run_release_check "F11.2 zero-network" \
    python3 Scripts/harness/release/f11_zero_network.py --app "$RELEASE_APP"

  assert_clean
done

echo ""
echo "build_stability: PASS — two clean rounds completed"
