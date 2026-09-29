#!/usr/bin/env bash
# Copy the design's page files and the vendored runtime into the app bundle's resources, unchanged.
# The design folder is the authority; SetsPageBytesTests fails if these copies ever drift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST="$ROOT/Lumina/Sets/Web"
cp "$ROOT/design/handoff/lumina-cull/Lumina Sets v3.dc.html" "$ROOT/design/handoff/lumina-cull/support.js" \
   "$ROOT/design/handoff/lumina-cull/lumina-core.js" "$DST/"
cp "$ROOT"/design/handoff/vendor/*.js "$DST/"
echo "synced page + vendor into $DST"
