#!/usr/bin/env bash
# The Skim dev app: the video step's page (design/handoff/lumina-skim) in its own "Lumina Skim" app,
# beside "Lumina Dev" (Scripts/dev.sh). Hot: a page edit shows in the running app in under a second.
#
#   bash Scripts/dev-skim.sh            build this checkout and show Lumina Skim
#   bash Scripts/dev-skim.sh --watch    the same, then keep following it until Ctrl-C:
#                                       an edit to the page reloads it in place (no build wait),
#                                       a Swift edit rebuilds and relaunches
#   bash Scripts/dev-skim.sh --quit     quit Lumina Skim
#
# Edit the page in design/handoff/lumina-skim/ (the design's copy). --watch copies each change to
# Lumina/Sets/Web (what the build bundles; SetsPageBytesTests holds the two equal) and straight into
# the running app's Resources, where SetsHotReload sees it; the build that follows copies the same
# bytes and does not reload again. Open a folder of clips in the page (Choose Folder…, or drop one):
# the clips are read through WebKit's <video>, as in a browser.
#
# Its own bundle id (com.lumina.app.skim), sandbox container, build folder and lock
# (~/Library/Caches/com.lumina.skim), so it runs at the same time as dev.sh. Debug only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LUMINA_DEV_ID=com.lumina.app.skim
export LUMINA_DEV_NAME="Lumina Skim"
export LUMINA_DEV_CACHE="$HOME/Library/Caches/com.lumina.skim"
export LUMINA_PAGE=skim

FROM="$ROOT/design/handoff/lumina-skim"
TO="$ROOT/Lumina/Sets/Web"
RES="$LUMINA_DEV_CACHE/DD/Build/Products/Debug/Lumina.app/Contents/Resources"
FILES=("Lumina Skim v3.dc.html" "lumina-video-data-mvp.js")

# One file into one folder, whole or not at all (a temp name the watchers skip, then a rename).
put() { cp "$1" "$2/.$3.part" && mv -f "$2/.$3.part" "$2/$3"; }
mirror() {
  local f
  for f in "${FILES[@]}"; do
    [[ -f "$FROM/$f" ]] || continue
    if ! cmp -s "$FROM/$f" "$TO/$f"; then put "$FROM/$f" "$TO" "$f"; echo "↻ $f"; fi
    # The running app's own copy: SetsHotReload reloads the page as soon as it differs.
    if [[ -d "$RES" ]] && ! cmp -s "$FROM/$f" "$RES/$f"; then put "$FROM/$f" "$RES" "$f"; fi
  done
}

mirror
WATCH=0; for a in "$@"; do [[ "$a" == --watch ]] && WATCH=1; done
if [[ $WATCH == 1 ]]; then
  ( trap 'exit 0' TERM; while sleep 0.3; do mirror; done ) &
  MIRROR=$!
  trap 'kill $MIRROR 2>/dev/null || true' EXIT
fi
bash "$ROOT/Scripts/dev.sh" "$@"
