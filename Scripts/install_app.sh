#!/usr/bin/env bash
# Build Lumina from this checkout and make it THE Lumina on this Mac: /Applications/Lumina.app,
# the one the Dock, Spotlight and Launchpad open. Old copies (earlier builds in Xcode's
# DerivedData, an older /Applications copy) are removed from Launch Services so macOS stops
# offering them.
#
#   bash Scripts/install_app.sh            build Release, install to /Applications, forget old copies
#   bash Scripts/install_app.sh --list     only list every Lumina.app macOS knows about
#
# Run it after every `git pull` you want to use day to day. Xcode's own Run (⌘R) always builds
# the checkout that's open in Xcode; see the note printed at the end.
#
# The app is sandboxed (the project signs Debug and Release with Config/Lumina-Sets.entitlements,
# TASKS R3), so the installed copy is the one the probe and CI test. A sandboxed app keeps its data
# in ~/Library/Containers/com.lumina.app/, not ~/Library/Application Support/Lumina: sessions saved
# by an earlier, unsandboxed build are not seen by this one (moving them over is TASKS R1e, not
# this script).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source Scripts/page_files.sh
ID=com.lumina.app
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

copies() { mdfind "kMDItemCFBundleIdentifier == '$ID'" 2>/dev/null | grep '\.app$' || true; }
page_of() { ls "$1/Contents/Resources" 2>/dev/null | grep -m1 '^Lumina Sets .*\.dc\.html$' || echo "no page"; }

echo "Lumina.app copies macOS knows about:"
copies | while read -r a; do echo "  $a  ($(page_of "$a"))"; done
[[ "${1:-}" == --list ]] && exit 0

echo "→ building Release from $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
rm -rf DD-install
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Release -derivedDataPath DD-install \
  -destination 'platform=macOS,arch=arm64' build -quiet
NEW=DD-install/Build/Products/Release/Lumina.app
[[ -f "$NEW/Contents/Resources/$PAGE" ]] || { echo "built app doesn't contain $PAGE — not installing" >&2; exit 1; }
codesign -d --entitlements - --xml "$NEW" 2>/dev/null | grep -q com.apple.security.app-sandbox \
  || { echo "built app is not sandboxed (CODE_SIGN_ENTITLEMENTS in the project?) — not installing" >&2; exit 1; }

echo "→ quitting Lumina"
osascript -e 'tell application id "'"$ID"'" to quit' >/dev/null 2>&1 || true
sleep 1; pkill -x Lumina 2>/dev/null || true

echo "→ installing /Applications/Lumina.app"
rm -rf /Applications/Lumina.app
ditto "$NEW" /Applications/Lumina.app
rm -rf DD-install

echo "→ forgetting old copies"
copies | while read -r a; do
  [[ "$a" == /Applications/Lumina.app ]] && continue
  "$LSREG" -u "$a" 2>/dev/null || true
  case "$a" in
    "$HOME/Library/Developer/Xcode/DerivedData/"*|"$ROOT/DD"*) rm -rf "$a"; echo "  removed $a" ;;   # build output only
    *) echo "  unregistered (left on disk): $a" ;;
  esac
done
"$LSREG" -f /Applications/Lumina.app

echo "✓ /Applications/Lumina.app = $(git rev-parse --short HEAD), page $(page_of /Applications/Lumina.app), sandboxed"
echo "  Data: ~/Library/Containers/$ID/ (sandbox). Sessions from an earlier unsandboxed build stay in"
echo "        ~/Library/Application Support/Lumina and are not seen by this one (TASKS R1e)."
echo "  Dock: remove any old Lumina icon, then open /Applications/Lumina.app and choose Options ▸ Keep in Dock."
echo "  Xcode: ⌘R runs the checkout open in Xcode. Check File ▸ Open Recent points at $ROOT/Lumina.xcodeproj,"
echo "         then Product ▸ Clean Build Folder (⇧⌘K) once."
open /Applications/Lumina.app
