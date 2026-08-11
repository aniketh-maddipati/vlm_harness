#!/bin/bash
# Lumina regression runner — lint (anywhere) + build/test/E2E (macOS only)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RAW="${1:-/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS}"
JPG="${2:-/Users/aniketh/jeevana_mehendi_2026}"

echo "=== Lumina regression ==="
echo "Repo: $ROOT"
echo ""

echo "--- Phase 1: static lint (runs anywhere) ---"
bash "$ROOT/Scripts/lint/banned_words.sh"
bash "$ROOT/Scripts/lint/copy_contract_diff.sh"
bash "$ROOT/Scripts/lint/contract_structure.sh"
bash "$ROOT/Scripts/lint/contract_v6_presence.sh"
bash "$ROOT/Scripts/lint/agent_rules_contract.sh"
bash -n "$ROOT/Scripts/run_p0_ui_tests.sh"

validate_json() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq . "$file" >/dev/null
  else
    echo "NOTE: jq unavailable — skipping JSON validation for $file (install jq on CI runners)"
    return 0
  fi
}

for plan in P0Fast P0Stress P0Visual; do
  validate_json "$ROOT/TestPlans/$plan.xctestplan"
  echo "  test plan $plan: valid JSON"
done

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$ROOT/Lumina.xcodeproj/xcshareddata/xcschemes/Lumina.xcscheme"
  echo "  shared scheme Lumina.xcscheme: well-formed XML"
else
  grep -q '<Scheme' "$ROOT/Lumina.xcodeproj/xcshareddata/xcschemes/Lumina.xcscheme"
  echo "  shared scheme Lumina.xcscheme: present (xmllint unavailable)"
fi
echo "Phase 1 lint: OK"
echo ""

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "NOTE: xcodebuild unavailable (non-macOS) — skipping build, XCTest, and E2E audit."
  echo "      Run full regression on a Mac with Xcode 15+."
  exit 0
fi

echo "--- Phase 2: build + logic tests (macOS) ---"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData build 2>&1 | tail -5
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData -destination 'platform=macOS' build-for-testing 2>&1 | tail -3
echo "Build: OK"
echo ""

xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData -destination 'platform=macOS' \
  -only-testing:LuminaLogicTests test-without-building 2>&1 | grep -E "Executed .* test|failed" | tail -3
echo "Logic tests: OK"
echo ""

if [[ -x "$ROOT/Scripts/run_p0_ui_tests.sh" ]]; then
  echo "(Optional) macOS UI automation: bash Scripts/run_p0_ui_tests.sh fast"
fi
echo ""

echo "--- Phase 3: headless E2E audit (macOS + RAW fixtures) ---"
if [[ ! -d "$RAW" ]]; then
  echo "WARN: RAW folder missing ($RAW) — skipping media audit"
  exit 0
fi
swift "$ROOT/Scripts/e2e_audit.swift" "$RAW" "$JPG"

REPORT="$ROOT/DerivedData/e2e/report.json"
if [[ -f "$REPORT" ]]; then
  echo ""
  echo "--- Summary ---"
  if command -v jq >/dev/null 2>&1; then
    BUGS=$(jq '[.findings[] | select(.severity=="bug")] | length' "$REPORT")
    FRICTION=$(jq '[.findings[] | select(.severity=="friction")] | length' "$REPORT")
    PASS=$(jq '[.findings[] | select(.severity=="pass")] | length' "$REPORT")
    CACHE_P95=$(jq -r '.metrics.cacheDecodeP95ms // 0' "$REPORT")
    echo "Pass: $PASS · Friction: $FRICTION · Bugs: $BUGS · Cache p95: ${CACHE_P95}ms"
    if [[ "$BUGS" -gt 0 ]]; then
      echo "FAILED — $BUGS bug(s) reported"
      exit 1
    fi
    P95=$(jq -r '.metrics.cacheDecodeP95ms // empty' "$REPORT")
    if [[ -n "$P95" ]] && awk "BEGIN { exit !($P95 > 50) }"; then
      echo "FAILED — cache decode p95 exceeds 50ms SLA"
      exit 1
    fi
  else
    echo "Raw report (jq unavailable — install jq for summary):"
    cat "$REPORT"
  fi
  echo "PASSED"
fi
