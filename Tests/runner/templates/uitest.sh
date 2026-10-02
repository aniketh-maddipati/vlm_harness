#!/bin/bash
# about: ONE XCUITest (owns the screen for its duration). Arg: Suite/test_name, e.g. LayoutAndSizingTests/test_R43_resizeWhileZoomed_photoStaysVisible. A whole suite is refused; list the tests you need one per run.
# limit: 240
cd "$ROOT" || exit 2
case "${1:-}" in */test_*) ;; *) echo "uitest takes one test: Suite/test_name (got '${1:-}')"; exit 2;; esac
# Each test may take at most 90 s, enforced by XCTest itself as well as by the runner.
xcodebuild test -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 \
  -only-testing:"LuminaUITests/$1"
