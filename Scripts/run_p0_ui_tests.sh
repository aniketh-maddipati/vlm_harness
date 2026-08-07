#!/bin/bash
# Lumina P0 UI-automation runner (XCUITest).
#
# Usage:
#   bash Scripts/run_p0_ui_tests.sh fast            # P0Fast plan (deterministic flows + short explorer + logic)
#   bash Scripts/run_p0_ui_tests.sh stress          # P0Stress plan (mixed-200, long explorer, relaunch, resize)
#   bash Scripts/run_p0_ui_tests.sh visual          # P0Visual plan (pinned 1280x800 capture + semantic layout)
#   bash Scripts/run_p0_ui_tests.sh logic           # native logic tests only (fast, no UI)
#   bash Scripts/run_p0_ui_tests.sh seed 84721 [N]  # replay one explorer seed (N steps, default 200)
#
# Env overrides honored by the tests (forwarded to the test runner):
#   LUMINA_UI_TEST_SEED, LUMINA_UI_TEST_STEPS
#
# Guarantees: macOS + Xcode required; explicit macOS destination; result bundle + diagnostics under
# a documented artifact directory; nonzero exit on failure; isolated, safely-scoped temp state;
# failure artifacts preserved (never deletes broad/unresolved paths).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-fast}"

# --- Host validation -------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macOS UI automation requires a Mac. Host is $(uname -s)." >&2
  echo "       On Linux, run 'bash Scripts/regression.sh' for the static/syntax gate instead." >&2
  exit 2
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild not found. Install Xcode 15+ and run 'xcode-select --switch'." >&2
  exit 2
fi

SCHEME="Lumina"
DESTINATION="platform=macOS"
DERIVED="$ROOT/DerivedData"

# --- Artifact directory (documented, per-run) ------------------------------
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="$ROOT/artifacts/ui-automation/${MODE}-${STAMP}"
mkdir -p "$ARTIFACT_DIR"
RESULT_BUNDLE="$ARTIFACT_DIR/result.xcresult"
STATE_ROOT="$ARTIFACT_DIR/state"     # isolated temp state; failure snapshots preserved here
mkdir -p "$STATE_ROOT"
LOG="$ARTIFACT_DIR/xcodebuild.log"

# --- Forward test-side env to the test runner process ----------------------
# xcodebuild passes TEST_RUNNER_<NAME> into the test bundle's process environment as <NAME>.
RUNNER_ENV=( "TEST_RUNNER_LUMINA_UI_TEST_STATE_ROOT=$STATE_ROOT" )
if [[ -n "${LUMINA_UI_TEST_SEED:-}" ]]; then
  RUNNER_ENV+=( "TEST_RUNNER_LUMINA_UI_TEST_SEED=$LUMINA_UI_TEST_SEED" )
fi
if [[ -n "${LUMINA_UI_TEST_STEPS:-}" ]]; then
  RUNNER_ENV+=( "TEST_RUNNER_LUMINA_UI_TEST_STEPS=$LUMINA_UI_TEST_STEPS" )
fi

XC_ARGS=(
  -project "Lumina.xcodeproj"
  -scheme "$SCHEME"
  -configuration Debug
  -derivedDataPath "$DERIVED"
  -destination "$DESTINATION"
  -resultBundlePath "$RESULT_BUNDLE"
)

run_plan() {
  local plan="$1"; shift || true
  echo "=== Lumina P0 UI automation: $MODE (test plan $plan) ==="
  echo "Artifacts: $ARTIFACT_DIR"
  set +e
  xcodebuild "${XC_ARGS[@]}" -testPlan "$plan" "$@" \
    "${RUNNER_ENV[@]}" test 2>&1 | tee "$LOG"
  local status=${PIPESTATUS[0]}
  set -e
  finish "$status"
}

finish() {
  local status="$1"
  echo ""
  echo "Result bundle: $RESULT_BUNDLE"
  echo "Log:           $LOG"
  echo "State root:    $STATE_ROOT (failure snapshots preserved here)"
  if [[ "$status" -ne 0 ]]; then
    echo "RESULT: FAILED (exit $status). Failure artifacts preserved under $ARTIFACT_DIR" >&2
  else
    echo "RESULT: PASSED"
  fi
  exit "$status"
}

case "$MODE" in
  fast)   run_plan "P0Fast" ;;
  stress) run_plan "P0Stress" ;;
  visual) run_plan "P0Visual" ;;
  logic)
    echo "=== Lumina logic tests only ==="
    set +e
    xcodebuild "${XC_ARGS[@]}" -only-testing:LuminaLogicTests test 2>&1 | tee "$LOG"
    status=${PIPESTATUS[0]}
    set -e
    finish "$status"
    ;;
  seed)
    SEED="${2:-84721}"
    STEPS="${3:-200}"
    echo "=== Explorer seed replay: seed=$SEED steps=$STEPS ==="
    echo "Artifacts: $ARTIFACT_DIR"
    set +e
    # Run within the P0Stress plan so the long-run execution-time allowance applies (a seeded
    # mixed-200 walk can legitimately exceed the default 3-minute per-test budget).
    xcodebuild "${XC_ARGS[@]}" \
      -testPlan P0Stress \
      -only-testing:LuminaUITests/ExplorerStressTests \
      "TEST_RUNNER_LUMINA_UI_TEST_STATE_ROOT=$STATE_ROOT" \
      "TEST_RUNNER_LUMINA_UI_TEST_SEED=$SEED" \
      "TEST_RUNNER_LUMINA_UI_TEST_STEPS=$STEPS" \
      test 2>&1 | tee "$LOG"
    status=${PIPESTATUS[0]}
    set -e
    finish "$status"
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: bash Scripts/run_p0_ui_tests.sh [fast|stress|visual|logic|seed <N> [steps]]" >&2
    exit 2
    ;;
esac
