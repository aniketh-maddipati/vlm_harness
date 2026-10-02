#!/bin/bash
# about: launch the native UI for N seconds (default 20, at most 60), screenshot it, quit. Arg: [seconds]. Sends no keys. Needs a build (run.sh build).
# limit: 90
cd "$ROOT" || exit 2
APP="$ROOT/DD/Build/Products/Debug/Lumina.app"
[ -d "$APP" ] || { echo "no build at $APP: run.sh build first"; exit 2; }
SECS="${1:-20}"; [ "$SECS" -gt 60 ] && SECS=60
"$APP/Contents/MacOS/Lumina" -LuminaNative YES -ApplePersistenceIgnoreState YES &
APID=$!
sleep 4
sleep 2
screencapture -x "$RUN/screen.png" && echo "screenshot: $RUN/screen.png"
sleep "$SECS"
kill -TERM "$APID" 2>/dev/null; sleep 1; kill -KILL "$APID" 2>/dev/null
exit 0
