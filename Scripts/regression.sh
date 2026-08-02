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

echo "--- 1/2 Build ---"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData build 2>&1 | tail -5
echo "Build: OK"
echo ""

echo "--- 2/2 Headless E2E audit ---"
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
  echo "Pass: $PASS · Friction: $FRICTION · Bugs: $BUGS"
  if [[ "$BUGS" -gt 0 ]]; then
    echo "FAILED — $BUGS bug(s) reported"
    exit 1
  fi
  echo "PASSED"
fi
