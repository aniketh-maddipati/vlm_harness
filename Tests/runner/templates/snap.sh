#!/bin/bash
# about: offscreen screenshots with lumina-snap (no window on screen, no keys). Args passed to lumina-snap; see its --help.
# limit: 180
cd "$ROOT/LuminaKit" || exit 2
swift run lumina-snap --out "$RUN/snap.png" "$@"
