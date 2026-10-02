#!/usr/bin/env bash
# The native UI's tests, each run bounded and cleaned up (AGENTS.md, "Running tests without
# disturbing the Mac"). Every run goes through Scripts/test_guard.py: a wall-clock limit, one
# screen-owning run at a time on this Mac, and nothing left running afterwards.
#
#   bash Scripts/test.sh kit [swift test args…]   LuminaKit's headless tests (no window, no screen lock). Limit 600 s
#                                                 (LUMINA_KIT_LIMIT)
#   bash Scripts/test.sh ui                       the UI smoke: one XCUITest (launch, cull, edit, resize while zoomed).
#                                                 Limit 180 s after the build
#   bash Scripts/test.sh ui Class[/test]…         those suites or tests (LuminaUITests/ is added). Limit 900 s (LUMINA_UI_LIMIT)
#   LUMINA_LONG=1 bash Scripts/test.sh ui all     every suite, every window shape, Load and Soak (SOAK_ROUNDS, default 25).
#                                                 Limit 3 h. Only on purpose: it owns the screen and keyboard throughout
#
# A UI test takes over the screen and the keyboard and quits a running Lumina: it refuses to start
# while Lumina from /Applications is open or another test run holds the screen (exit 75).
# Each test has its own limit in the code (LuminaTestCase.limit, 120 s unless the suite says otherwise;
# LUMINA_TEST_LIMIT=<s> sets it for a run). bash Scripts/stop_tests.sh stops everything.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GUARD=(python3 "$ROOT/Scripts/test_guard.py" run)
DD="${LUMINA_DD:-$ROOT/DD}"
XC=(xcodebuild -project Lumina.xcodeproj -scheme Lumina-UITest -configuration Debug -derivedDataPath "$DD" -destination 'platform=macOS,arch=arm64')
SMOKE=LayoutAndSizingTests/test_R43_resizeWhileZoomed_photoStaysVisible

mode="${1:-}"; shift || true
case "$mode" in
  kit)
    cd LuminaKit
    # One at a time on this Mac: the tests share fixture folders in the temp folder, removed afterwards.
    exec "${GUARD[@]}" --name "kit test" --limit "${LUMINA_KIT_LIMIT:-600}" --sweep-under "$ROOT/LuminaKit/.build" \
      --remove-temp lumina-fixtures --remove-temp 'lumina-wp2-*' --remove-temp 'lumina-wp8-*' --remove-temp 'wp3-prefs-*' --remove-temp 'wp6-intro-*' \
      -- swift test "$@" ;;
  ui)
    tests=("$@"); limit="${LUMINA_UI_LIMIT:-900}"; allowance=300
    [[ ${#tests[@]} -eq 0 ]] && { tests=("$SMOKE"); limit="${LUMINA_UI_LIMIT:-180}"; }
    only=()
    if [[ ${tests[0]} == all ]]; then
      [[ ${LUMINA_LONG:-} == 1 ]] || { echo "ui all owns the screen for up to 3 hours and is only started on purpose: LUMINA_LONG=1 bash Scripts/test.sh ui all" >&2; exit 2; }
      limit="${LUMINA_UI_LIMIT:-10800}"; only=(-only-testing:LuminaUITests)
    else
      for t in "${tests[@]}"; do only+=("-only-testing:LuminaUITests/${t#LuminaUITests/}"); done
    fi
    [[ ${LUMINA_LONG:-} == 1 ]] && allowance=14400
    # The build is not the test: its own limit, no screen.
    "${GUARD[@]}" --quiet --name "ui build $ROOT" --limit "${LUMINA_BUILD_LIMIT:-1500}" -- "${XC[@]}" build-for-testing -quiet \
      || { echo "UI test build failed" >&2; exit 2; }
    # TEST_RUNNER_<NAME> reaches the test runner as <NAME>. The runner is told the screen is held (by this guard).
    exec "${GUARD[@]}" --name ui --limit "$limit" --screen --sweep-under "$DD" --remove-temp 'lumina-store-*' --remove-temp lumina-fixtures -- env \
      TEST_RUNNER_LUMINA_SCREEN_LOCK_HELD=1 TEST_RUNNER_LUMINA_LONG="${LUMINA_LONG:-0}" TEST_RUNNER_SOAK_ROUNDS="${SOAK_ROUNDS:-25}" \
      ${LUMINA_TEST_LIMIT:+TEST_RUNNER_LUMINA_TEST_LIMIT="$LUMINA_TEST_LIMIT"} \
      "${XC[@]}" test-without-building "${only[@]}" \
      -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance "$allowance" ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
