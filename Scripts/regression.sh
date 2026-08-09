#!/bin/bash
# Lumina regression runner — build + headless e2e audit + summary
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RAW="${1:-/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS}"
JPG="${2:-/Users/aniketh/jeevana_mehendi_2026}"

echo "=== Lumina regression ==="
echo "Repo: $ROOT"
echo ""

echo "--- 0/7 Command chord tests ---"
swift "$ROOT/Scripts/CommandChordTests.swift"
echo "Command chord tests: OK"
echo ""

echo "--- 1/7 Develop engine unit tests ---"
python3 "$ROOT/Scripts/develop_engine_test.py"
echo "Develop unit tests: OK"
echo ""

echo "--- 2/7 P0 state / migration tests ---"
swift "$ROOT/Scripts/p0_state_test.swift"
echo "P0 state tests: OK"
echo ""

echo "--- 3/7 P0 contact-sheet tests ---"
swift "$ROOT/Scripts/p0_contact_sheet_test.swift"
echo "P0 contact-sheet tests: OK"
echo ""

echo "--- 4/7 P0 cull grammar tests ---"
swift "$ROOT/Scripts/p0_cull_test.swift"
echo "P0 cull tests: OK"
echo ""

echo "--- 4c/7 Prompt-9 hi-fi contract audit ---"
python3 "$ROOT/Scripts/prompt_9_audit.py"
echo "Prompt-9 audit: OK"
echo ""

echo "--- 4d/7 A1 staged-copy invariant ---"
python3 "$ROOT/Scripts/a1_invariant_test.py"
echo "A1 invariant test: OK"
echo ""

echo "--- 4b/7 UI-automation manifest checks (portable; runs on Linux too) ---"
# Static validation of the XCUITest harness plumbing. These do NOT run any macOS UI tests — they
# only confirm the runner script, test plans, and shared scheme are well-formed, so a Linux cloud
# agent can catch harness breakage without ever claiming it executed macOS automation.
bash -n "$ROOT/Scripts/run_p0_ui_tests.sh"
for plan in P0Fast P0Stress P0Visual; do
  python3 -c "import json,sys; json.load(open('$ROOT/TestPlans/$plan.xctestplan'))"
  echo "  test plan $plan: valid JSON"
done
python3 - "$ROOT/Lumina.xcodeproj/xcshareddata/xcschemes/Lumina.xcscheme" <<'PY'
import sys, xml.dom.minidom
xml.dom.minidom.parse(sys.argv[1])
print("  shared scheme Lumina.xcscheme: well-formed XML")
PY
echo "UI-automation manifests: OK"
echo ""

# Everything below requires macOS + Xcode. On Linux the script has already done what it can.
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "NOTE: xcodebuild unavailable (non-macOS) — skipping build, XCTest, and E2E audit."
  echo "      Run 'bash Scripts/run_p0_ui_tests.sh fast' on a Mac for macOS UI automation."
  exit 0
fi

echo "--- 5/7 Build (app + test targets) ---"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData build 2>&1 | tail -5
# Compile the UI + logic test targets so harness breakage fails the gate (does not run UI tests).
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData -destination 'platform=macOS' build-for-testing 2>&1 | tail -3
echo "Build: OK"
echo ""

echo "--- 5b/7 Native logic tests (XCTest, deterministic, no UI) ---"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData -destination 'platform=macOS' \
  -only-testing:LuminaLogicTests test-without-building 2>&1 | grep -E "Executed .* test|failed" | tail -3
echo "Logic tests: OK  (full macOS UI suites: bash Scripts/run_p0_ui_tests.sh fast|stress|visual)"
echo ""

echo "--- 6/7 Headless E2E audit ---"
if [[ ! -d "$RAW" ]]; then
  echo "WARN: RAW folder missing ($RAW) — skipping media audit"
  exit 0
fi
swift "$ROOT/Scripts/e2e_audit.swift" "$RAW" "$JPG"

REPORT="$ROOT/DerivedData/e2e/report.json"
if [[ -f "$REPORT" ]]; then
  echo ""
  echo "--- Summary ---"
  BUGS=$(python3 -c "import json; d=json.load(open('$REPORT')); print(sum(1 for f in d['findings'] if f['severity']=='bug'))")
  FRICTION=$(python3 -c "import json; d=json.load(open('$REPORT')); print(sum(1 for f in d['findings'] if f['severity']=='friction'))")
  PASS=$(python3 -c "import json; d=json.load(open('$REPORT')); print(sum(1 for f in d['findings'] if f['severity']=='pass'))")
  CACHE_P95=$(python3 -c "import json; d=json.load(open('$REPORT')); print(d.get('metrics',{}).get('cacheDecodeP95ms') or 0)")
  echo "Pass: $PASS · Friction: $FRICTION · Bugs: $BUGS · Cache p95: ${CACHE_P95}ms"
  if [[ "$BUGS" -gt 0 ]]; then
    echo "FAILED — $BUGS bug(s) reported"
    exit 1
  fi
  if python3 -c "import json; d=json.load(open('$REPORT')); p=d.get('metrics',{}).get('cacheDecodeP95ms'); exit(0 if p is None or p <= 50 else 1)"; then
    :
  else
    echo "FAILED — cache decode p95 exceeds 50ms SLA"
    exit 1
  fi
  echo "PASSED"
fi
