#!/usr/bin/env bash
# Live photographic bridge gate for Phase 1 — macOS + Xcode required.
# Per AGENTS.md this cannot run on Linux cloud agents.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: live bridge test requires macOS (see AGENTS.md)."
  echo "On a Mac with Xcode and Mehendi ARWs, run:"
  echo "  bash Scripts/live_bridge_session.sh [RAW_FOLDER]"
  exit 0
fi

RAW="${1:-/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS}"
if [[ ! -d "$RAW" ]]; then
  echo "RAW folder missing: $RAW"
  exit 1
fi

COUNT=$(find "$RAW" -iname '*.arw' | wc -l | tr -d ' ')
echo "=== Lumina live bridge session ==="
echo "Shoot: $RAW"
echo "ARWs found: $COUNT"
if [[ "$COUNT" -lt 200 ]]; then
  echo "WARN: fewer than 200 ARWs — still useful, but not the full gate."
fi

echo ""
echo "Building…"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS' build

APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Lumina*/Build/Products/Debug/Lumina.app' -type d 2>/dev/null | head -1)
if [[ -z "${APP:-}" ]]; then
  echo "Could not locate Lumina.app"
  exit 1
fi

echo ""
echo "Launching $APP"
echo "Manual gate checklist (10+ minutes):"
cat <<'EOF'
  1. Open ≥200 mixed-orientation ARWs from this shoot
  2. Navigate rapidly for 60 seconds (←→↑↓ / F/D)
  3. Switch Attempts/Light twenty times (1/2)
  4. Mark Keep/Cut/Needs me/Anchor repeatedly (K/X/M/A)
  5. Resize while scrolling
  6. Enter and leave Focus repeatedly (Space / Esc)
  7. Quit and resume
  8. Watch for: stretching, blank frames, wrong thumbnails,
     selection loss, controls moving, Esc dumping to Home

Record a short screen capture while doing steps 2–6.
Visual judgment matters more than the regression count.
EOF

open "$APP"
