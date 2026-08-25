#!/usr/bin/env bash
# One-shot Mac setup for running Lumina from this repo. Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }
note() { echo "-> $*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Lumina is a Mac app. Run this on an Apple Silicon Mac with macOS 14+."
fi

if [[ ! -d /Applications/Xcode.app ]]; then
  fail "Install Xcode from the App Store, open it once, then re-run this script."
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild is not on PATH. Run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVELOPER_DIR" != "/Applications/Xcode.app/Contents/Developer" ]]; then
  note "xcode-select is pointed at: ${DEVELOPER_DIR:-none}"
  note "Fix with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  note "Xcode still needs first-launch setup. Open Xcode.app, accept the license, install extra components, then re-run."
fi
ok "Xcode is present ($(xcodebuild -version | head -1))"

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is missing. Install it, then re-run:

  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"

  On Apple Silicon, then:

  echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile
  eval \"\$(/opt/homebrew/bin/brew shellenv)\""
fi
ok "Homebrew is present ($(brew --prefix))"

# The app probes these absolute paths. Xcode-launched processes do not use your shell PATH.
EXIF_CANDIDATES=(
  /opt/homebrew/bin/exiftool
  /usr/local/bin/exiftool
  /usr/bin/exiftool
)

exif_found=""
for p in "${EXIF_CANDIDATES[@]}"; do
  if [[ -x "$p" ]]; then
    exif_found="$p"
    break
  fi
done

if [[ -z "$exif_found" ]]; then
  note "Installing exiftool via Homebrew..."
  brew install exiftool
  for p in "${EXIF_CANDIDATES[@]}"; do
    if [[ -x "$p" ]]; then
      exif_found="$p"
      break
    fi
  done
fi

if [[ -z "$exif_found" ]]; then
  fail "exiftool is not at a path Lumina checks:
  /opt/homebrew/bin/exiftool
  /usr/local/bin/exiftool
  /usr/bin/exiftool
The app launched from Xcode does not use your shell PATH."
fi
ok "exiftool is at $exif_found ($("$exif_found" -ver))"

echo ""
echo "Setup is good. Next:"
echo ""
echo "  open \"$ROOT/Lumina.xcodeproj\""
echo ""
echo "In Xcode: scheme Lumina, then Command-R."
echo "When it launches: Choose a folder, drop photos, or pick the SD card (usually DCIM on the volume)."
echo "Do not copy shoots into this repo."
