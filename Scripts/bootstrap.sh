#!/usr/bin/env bash
# One-shot Mac setup. Safe to re-run.
#   bash Scripts/bootstrap.sh        # deps + Lumina Debug + open the app
#   bash Scripts/bootstrap.sh --dev  # also playground (Inject) + InjectionIII check
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEV=0
for arg in "$@"; do
  case "$arg" in
    --dev) DEV=1 ;;
    -h|--help)
      sed -n '2,5p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "FAIL: unknown flag $arg. Run:
  bash Scripts/bootstrap.sh" >&2
      exit 1
      ;;
  esac
done

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }
note() { echo "-> $*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Lumina is a Mac app. Run this on an Apple Silicon Mac with macOS 14+:
  bash Scripts/bootstrap.sh"
fi

arch="$(uname -m)"
if [[ "$arch" != "arm64" ]]; then
  fail "Apple Silicon required. This Mac is $arch. Run this on an M-series Mac:
  bash Scripts/bootstrap.sh"
fi

os_ver="$(sw_vers -productVersion)"
os_major="${os_ver%%.*}"
if [[ "$os_major" -lt 14 ]]; then
  fail "macOS 14+ required. This Mac is $os_ver."
fi
ok "macOS $os_ver ($arch)"

if [[ ! -d /Applications/Xcode.app ]]; then
  fail "Install Xcode from the App Store, open it once, then:
  bash Scripts/bootstrap.sh"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild is not on PATH. Run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVELOPER_DIR" != "/Applications/Xcode.app/Contents/Developer" ]]; then
  fail "xcode-select is pointed at ${DEVELOPER_DIR:-none}. Run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  fail "Open Xcode.app, accept the license, install extra components, then:
  bash Scripts/bootstrap.sh"
fi

xcode_ver="$(xcodebuild -version | awk '/Xcode/ {print $2; exit}')"
xcode_major="${xcode_ver%%.*}"
if [[ -n "$xcode_major" && "$xcode_major" -lt 15 ]]; then
  fail "Xcode 15+ required. This Mac has Xcode $xcode_ver."
fi
ok "Xcode ${xcode_ver:-unknown}"

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is missing. Install it, then re-run bootstrap:

  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
  echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile
  eval \"\$(/opt/homebrew/bin/brew shellenv)\"
  bash Scripts/bootstrap.sh"
fi
ok "Homebrew $(brew --prefix)"

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
  fail "exiftool is not at a path Lumina checks. Run:
  brew install exiftool"
fi
ok "exiftool $exif_found ($("$exif_found" -ver))"

DERIVED="${LUMINA_DERIVED_DATA:-$ROOT/.derivedData}"
note "Building Lumina Debug (derived data: $DERIVED)"
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -resolvePackageDependencies
xcodebuild \
  -project Lumina.xcodeproj \
  -scheme Lumina \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  build
ok "Lumina Debug build"

APP="$DERIVED/Build/Products/Debug/Lumina.app"
if [[ ! -d "$APP" ]]; then
  fail "Build finished but Lumina.app was not at $APP. Open the project and build from Xcode:
  open \"$ROOT/Lumina.xcodeproj\""
fi

open "$APP"
ok "Opened $APP"

if [[ "$DEV" -eq 1 ]]; then
  note "Resolving LuminaPlayground (Inject)"
  xcodebuild \
    -project Lumina.xcodeproj \
    -scheme LuminaPlayground \
    -resolvePackageDependencies
  xcodebuild \
    -project Lumina.xcodeproj \
    -scheme LuminaPlayground \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    build
  ok "LuminaPlayground Debug build"

  INJECTION="/Applications/InjectionIII.app"
  if [[ -d "$INJECTION" ]]; then
    ok "InjectionIII is at $INJECTION"
  else
    note "InjectionIII is not in /Applications. Hot reload will not work on save."
    note "Install from https://github.com/johnno1962/InjectionIII/releases/latest"
    note "Unzip to /Applications, launch it, File > Open Project, pick $ROOT"
  fi
  echo ""
  echo "Playground next:"
  echo "  bash Scripts/playground.sh"
  echo "Or in Xcode: scheme LuminaPlayground, then Command-R."
fi

echo ""
echo "When it launches: Choose a folder, drop photos, or pick the SD card (usually DCIM on the volume)."
echo "Vision is on-device. No extra model. Keep shoots out of this repo."
