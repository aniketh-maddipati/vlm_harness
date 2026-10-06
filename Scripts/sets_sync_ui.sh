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
# support.js fetches Babel (3 MB) only to compile an <x-import> of a .jsx/.tsx file. No page file has
# one, so the app ships React alone. A handoff that adds one needs Babel back in the bundle, the
# scheme handler's vendorFiles and SetsPageBytesTests: stop here rather than ship a page that can't load.
if grep -lE '<x-import[^>]*\.(jsx|tsx)' "${PAGE_FILES[@]/#/$ROOT/design/handoff/lumina-cull/}" 2>/dev/null; then
  echo "a page file x-imports .jsx/.tsx: it needs Babel, which the app no longer bundles" >&2; exit 1
fi
cp "$ROOT"/design/handoff/vendor/react.production.min.js "$ROOT"/design/handoff/vendor/react-dom.production.min.js "$DST/"
rm -f "$DST/babel.min.js"
echo "synced page + vendor into $DST"
