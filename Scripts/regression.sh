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

echo "--- 0/3 Develop engine unit tests ---"
python3 "$ROOT/Scripts/develop_engine_test.py"
echo "Develop unit tests: OK"
echo ""

echo "--- 1/3 Build ---"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath ./DerivedData build 2>&1 | tail -5
echo "Build: OK"
echo ""

echo "--- 2/3 Headless E2E audit ---"
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
