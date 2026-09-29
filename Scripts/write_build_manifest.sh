#!/bin/sh
# Xcode "Embed Build Manifest" phase: records what a build contains, including which design page
# it ships, as LuminaBuild.json in the app's Resources.
set -eu
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PAGE="$ROOT/design/handoff/lumina-cull/Lumina Sets v3.dc.html"
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
GIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
DEST="${TARGET_BUILD_DIR:-$ROOT/build}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
mkdir -p "$DEST"
cat > "$DEST/LuminaBuild.json" <<EOF
{
  "version": "${MARKETING_VERSION:-}",
  "build": "${CURRENT_PROJECT_VERSION:-}",
  "configuration": "${CONFIGURATION:-}",
  "git_sha": "$GIT_SHA",
  "design_page_sha256": "$(sha "$PAGE")",
  "lumina_core_sha256": "$(sha "$ROOT/design/handoff/lumina-cull/lumina-core.js")",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
