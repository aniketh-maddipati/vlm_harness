#!/usr/bin/env bash
# The ingest prototype's dev app: "Lumina Ingest", beside "Lumina Dev" and "Lumina Skim". Hot: a page edit
# shows in the running app in under a second. Debug only; not what ships.
#
#   bash Scripts/dev-ingest.sh            build this checkout and show Lumina Ingest
#   bash Scripts/dev-ingest.sh --watch    the same, then keep following it until Ctrl-C
#   bash Scripts/dev-ingest.sh --quit     quit Lumina Ingest
#
# Edit the page in design/handoff/lumina-ingest/. --watch copies each change to Lumina/Sets/Web and into
# the running app's Resources, where SetsHotReload sees it. The page shows on Skim's side
# (`LUMINA_PAGE=ingest`, SetsPage.file): no plumbing, no Edit canvas, no card watcher.
#
# Its own bundle id (com.lumina.app.ingest), sandbox container, build folder and lock
# (~/Library/Caches/com.lumina.ingest), so it runs at the same time as dev.sh and dev-skim.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LUMINA_DEV_ID=com.lumina.app.ingest
export LUMINA_DEV_NAME="Lumina Ingest"
export LUMINA_DEV_CACHE="$HOME/Library/Caches/com.lumina.ingest"
export LUMINA_PAGE=ingest

FROM="$ROOT/design/handoff/lumina-ingest"
TO="$ROOT/Lumina/Sets/Web"
RES="$LUMINA_DEV_CACHE/DD/Build/Products/Debug/Lumina.app/Contents/Resources"
FILES=("Lumina Ingest v1.html" "lumina-ingest-clocks.js")

put() { cp "$1" "$2/.$3.part" && mv -f "$2/.$3.part" "$2/$3"; }
mirror() {
  local f
  for f in "${FILES[@]}"; do
    [[ -f "$FROM/$f" ]] || continue
    if ! cmp -s "$FROM/$f" "$TO/$f"; then put "$FROM/$f" "$TO" "$f"; echo "↻ $f"; fi
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
