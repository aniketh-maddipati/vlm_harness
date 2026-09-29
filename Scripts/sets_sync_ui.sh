#!/usr/bin/env bash
# Copy the design's page files and the vendored runtime into the app bundle's resources, unchanged.
# The design folder is the authority; SetsPageBytesTests fails if these copies ever drift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/page_files.sh"
DST="$ROOT/Lumina/Sets/Web"
# Page files from an earlier handoff (renamed since) must not linger in the bundle.
for f in "$DST"/*.dc.html "$DST"/lumina-*.js; do
  [[ -e $f ]] || continue
  keep=0; for p in "${PAGE_FILES[@]}"; do [[ $(basename "$f") == "$p" ]] && keep=1; done
  [[ $keep == 1 ]] || { rm "$f"; echo "removed stale $(basename "$f")"; }
done
for f in "${PAGE_FILES[@]}"; do cp "$ROOT/design/handoff/lumina-cull/$f" "$DST/"; done
cp "$ROOT"/design/handoff/vendor/*.js "$DST/"
echo "synced page + vendor into $DST"
