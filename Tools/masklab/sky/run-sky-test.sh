#!/usr/bin/env bash
# The sky mask on a card's photos (Tools/masklab/README.md, "Sky"). Mac only. Reads the card, never writes to it.
#
#   bash Tools/masklab/sky/run-sky-test.sh [folder]      # default /Volumes/Untitled
#
# Builds masklab-sky from the app's own finder (Lumina/Sets/Look/LookMasks.swift, Lumina/Sets/Core/SetsMasks.swift),
# lists the folder's photos (JPEG, HEIC and RAW; their embedded previews are read, never a RAW decode), takes
# SKY_N of them spread evenly through the card (default 240), and writes overlays, contact sheets and report.json to
# ~/LuminaEvidence/skymask/<date-time>/ (runs/latest points at it). Under Scripts/test_guard.py: bounded
# (SKY_LIMIT, 1800 s), one at a time, refused while ~/LuminaEvidence/.tests-off exists.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
if [ "${1:-}" != "--guarded" ]; then
  exec python3 "$ROOT/Scripts/test_guard.py" run --name skymask --limit "${SKY_LIMIT:-1800}" -- bash "$0" --guarded "${1:-/Volumes/Untitled}"
fi
DIR="$2"; N="${SKY_N:-240}"; EVID="$HOME/LuminaEvidence/skymask"; RUN="$EVID/$(date +%Y%m%d-%H%M%S)"
[ -d "$DIR" ] || { echo "skymask: no folder $DIR" >&2; exit 3; }
mkdir -p "$RUN" "$EVID/build"
BIN="$EVID/build/masklab-sky"
swiftc -O -swift-version 5 -o "$BIN" "$ROOT/Lumina/Sets/Look/LookMasks.swift" "$ROOT/Lumina/Sets/Core/SetsMasks.swift" "$HERE/Stub.swift" "$HERE/main.swift"
find "$DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.arw' -o -iname '*.dng' -o -iname '*.cr3' -o -iname '*.nef' -o -iname '*.raf' \) \
  -not -name '._*' | sort > "$RUN/all.txt"
TOTAL=$(wc -l < "$RUN/all.txt" | tr -d ' ')
[ "$TOTAL" -gt 0 ] || { echo "skymask: no photos in $DIR" >&2; exit 3; }
awk -v n="$N" -v t="$TOTAL" 't <= n || int(NR * n / t) != int((NR - 1) * n / t)' "$RUN/all.txt" > "$RUN/picked.txt"
echo "skymask: $TOTAL photos in $DIR, $(wc -l < "$RUN/picked.txt" | tr -d ' ') picked → $RUN"
"$BIN" "$RUN" "@$RUN/picked.txt" | tee "$RUN/log.txt"
ln -sfn "$RUN" "$EVID/latest"
