#!/bin/bash
# The kill switch: stops every test and probe process on this Mac and detaches the probe's disk
# images. Safe to run any time; touches nothing else (not the Claude app, not real drives).
#
#   bash Tests/runner/stop.sh            stop everything, say what was stopped
#   bash Tests/runner/stop.sh --check    only say what is running
QUIET=0; KEEP_LOCK=0; CHECK=0
for a in "$@"; do case "$a" in --quiet) QUIET=1;; --keep-lock) KEEP_LOCK=1;; --check) CHECK=1;; esac; done
say() { [ "$QUIET" = 1 ] || echo "$@"; }

# Drivers first (they respawn what they run), then what they run.
PATTERNS="life_kill.py q2drive.sh final.sh quiet.sh Scripts/probe.sh lumina-probe Tests/web/parity.mjs Tests/web/webkit.py plumbing-harness.mjs xcodebuild.*test LuminaUITests-Runner XCTRunner xctest swift-test LuminaKitPackageTests"
found=0
for p in $PATTERNS; do
  pids="$(pgrep -f "$p" | grep -v "^$$\$")"
  [ -z "$pids" ] && continue
  found=1
  if [ "$CHECK" = 1 ]; then say "running: $p ($(echo $pids))"; else say "stopping: $p ($(echo $pids))"; kill -TERM $pids 2>/dev/null; fi
done
# The app a test launched (a Debug build from DerivedData / DD, or the one the probe drives).
apps="$(pgrep -f '/(DD|DerivedData)/.*/Lumina.app/Contents/MacOS/Lumina')"
if [ -n "$apps" ]; then found=1; [ "$CHECK" = 1 ] && say "running: test Lumina.app ($(echo $apps))" || { say "stopping: test Lumina.app"; kill -TERM $apps 2>/dev/null; }; fi
[ "$CHECK" = 1 ] || { sleep 1; for p in $PATTERNS; do pkill -KILL -f "$p" 2>/dev/null; done; [ -n "$apps" ] && kill -KILL $apps 2>/dev/null; }

# The probe's disk images (image files under LuminaEvidence or named lumina*), nothing else.
hdiutil info 2>/dev/null | awk '/^image-path/ {img=$0} /^\/dev\/disk[0-9]+[ \t]/ { if (tolower(img) ~ /luminaevidence|lumina/) print $1 }' | sort -u | while read -r dev; do
  found=1
  if [ "$CHECK" = 1 ]; then say "attached probe image: $dev"; else say "detaching probe image: $dev"; hdiutil detach "$dev" -force >/dev/null 2>&1; fi
done

[ "$KEEP_LOCK" = 1 ] || [ "$CHECK" = 1 ] || rm -rf "$HOME/LuminaEvidence/runner/lock"
[ "$found" = 0 ] && say "nothing running"
exit 0
