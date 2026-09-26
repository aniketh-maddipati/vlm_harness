#!/bin/bash
# F15 — build, sign, notarize, staple and package a Developer ID release.
#
# Closes the last process blocker in docs/release/MACOS_RELEASE_READINESS_AUDIT.md:
# the repo had F11 verification (run_f11_release.py) but nothing that produced an
# artifact for it to verify.
#
# Lane: notarized Developer ID zip/DMG — NOT Mac App Store. See the audit §4.
#
# Usage:
#   Scripts/package_release.sh                 # full run
#   Scripts/package_release.sh --archive-only  # stop before notarization
#   Scripts/package_release.sh --skip-notarize # sign + export, no notary round trip
#
# Required environment (never committed):
#   LUMINA_TEAM_ID        Apple Developer team identifier, e.g. AB12CD34EF
#   LUMINA_SIGN_IDENTITY  e.g. "Developer ID Application: Your Name (AB12CD34EF)"
#   LUMINA_NOTARY_PROFILE notarytool keychain profile name
#
# Create the notary profile once with:
#   xcrun notarytool store-credentials "lumina-notary" \
#     --apple-id you@example.com --team-id AB12CD34EF --password <app-specific-password>
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="Lumina"
CONFIG="Release"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Lumina.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Lumina.app"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.generated.plist"

ARCHIVE_ONLY=0
SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --archive-only)  ARCHIVE_ONLY=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n=== %s ===\n' "$1"; }
die()  { printf '\nFAIL: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
step "Preflight"

[ -d "$ROOT/Lumina.xcodeproj" ] || die "run from the repository root"

if [ "$ARCHIVE_ONLY" -eq 0 ]; then
  : "${LUMINA_TEAM_ID:?set LUMINA_TEAM_ID (Apple Developer team identifier)}"
  : "${LUMINA_SIGN_IDENTITY:?set LUMINA_SIGN_IDENTITY (Developer ID Application: ...)}"

  # Fail early and legibly rather than 20 minutes into an archive.
  if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    die "no 'Developer ID Application' identity in the keychain.
     Enrol at developer.apple.com, then create the certificate in Xcode
     (Settings > Accounts > Manage Certificates > + > Developer ID Application).
     This is blocker F1 and it is the only one that cannot be automated."
  fi
fi

if [ "$SKIP_NOTARIZE" -eq 0 ] && [ "$ARCHIVE_ONLY" -eq 0 ]; then
  : "${LUMINA_NOTARY_PROFILE:?set LUMINA_NOTARY_PROFILE (see xcrun notarytool store-credentials)}"
fi

# F14 — a monotonic, traceable build number. The audit's complaint was that every
# tester reports "0.1.0 (1)", making bug triage impossible. Commit count is
# monotonic on a linear history and maps a report straight back to a commit.
# Passed on the command line so project.pbxproj stays untouched.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
DIRTY=""
if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  DIRTY=" (working tree dirty)"
fi
echo "build number : $BUILD_NUMBER"
echo "commit       : $GIT_SHA$DIRTY"
[ -n "$DIRTY" ] && echo "WARNING: shipping a dirty tree makes the build unreproducible."

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------- archive
step "Archive ($CONFIG)"

ARCHIVE_ARGS=(
  -project Lumina.xcodeproj
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -archivePath "$ARCHIVE"
  -destination 'generic/platform=macOS'
  # Own the DerivedData path. Sharing it with a live Xcode or another checkout
  # has already caused one codesign race in this repo.
  -derivedDataPath "$BUILD_DIR/DerivedData"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)
if [ "$ARCHIVE_ONLY" -eq 0 ]; then
  ARCHIVE_ARGS+=(
    DEVELOPMENT_TEAM="$LUMINA_TEAM_ID"
    CODE_SIGN_IDENTITY="$LUMINA_SIGN_IDENTITY"
    CODE_SIGN_STYLE=Manual
  )
fi

xcodebuild archive "${ARCHIVE_ARGS[@]}" || die "archive failed"

if [ "$ARCHIVE_ONLY" -eq 1 ]; then
  echo "archive at $ARCHIVE - stopping (--archive-only)"
  exit 0
fi

# ---------------------------------------------------------------- export
step "Export (Developer ID)"

# teamID is injected here so it never lands in the committed plist.
python3 - "$ROOT/Scripts/harness/release/ExportOptions.plist" "$EXPORT_PLIST" "$LUMINA_TEAM_ID" <<'PY'
import plistlib, sys
src, dst, team = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "rb") as fh:
    data = plistlib.load(fh)
data["teamID"] = team
with open(dst, "wb") as fh:
    plistlib.dump(data, fh)
print(f"wrote {dst} (teamID injected)")
PY

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" || die "export failed"

[ -d "$APP" ] || die "expected $APP after export"

# ---------------------------------------------------------------- notarize
if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  echo "skipping notarization (--skip-notarize); f11_signature.py will FAIL on the staple check"
else
  step "Notarize + staple"

  # Xcode's developer-id export may already notarize. Staple is idempotent and
  # cheap, so submit only when the ticket is not already attached.
  if xcrun stapler validate "$APP" >/dev/null 2>&1; then
    echo "already stapled by the export step"
  else
    ZIP="$BUILD_DIR/Lumina-notarize.zip"
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" \
      --keychain-profile "$LUMINA_NOTARY_PROFILE" \
      --wait || die "notarization rejected - run: xcrun notarytool log <id> --keychain-profile $LUMINA_NOTARY_PROFILE"
    xcrun stapler staple "$APP" || die "stapling failed"
    rm -f "$ZIP"
  fi
fi

# ---------------------------------------------------------------- verify
step "F11 release integrity"

# The pre-existing harness is the gate: hooks absent, zero network, Developer ID
# signature + staple, embedded manifest, betaDiagnostics null, no licensing.
python3 "$ROOT/Scripts/harness/release/run_f11_release.py" --app "$APP" \
  || die "F11 verification failed - do not distribute this artifact"

# ---------------------------------------------------------------- package
step "Package"

MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAMP="Lumina-${MARKETING}-${BUILD_NUMBER}"
DMG="$BUILD_DIR/${STAMP}.dmg"
ZIP_OUT="$BUILD_DIR/${STAMP}.zip"

rm -f "$DMG" "$ZIP_OUT"

# Zip is the dependency-free path and is what notarytool accepts directly.
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP_OUT"
echo "zip : $ZIP_OUT"

# DMG is friendlier for testers: drag-to-Applications instead of an unzip step.
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/Lumina.app"
ln -s /Applications "$STAGE/Applications"
if hdiutil create -volname "Lumina" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null; then
  # The DMG is a separate artifact from the .app and needs its own ticket,
  # otherwise Gatekeeper prompts on first mount.
  if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$LUMINA_NOTARY_PROFILE" --wait \
      && xcrun stapler staple "$DMG" \
      || echo "WARNING: DMG notarization/staple failed - ship the zip instead"
  fi
  echo "dmg : $DMG"
else
  echo "WARNING: hdiutil failed - zip is still valid"
fi
rm -rf "$STAGE"

step "Done"
echo "app : $APP"
echo "version: $MARKETING ($BUILD_NUMBER)  commit $GIT_SHA"
echo
echo "Promote as the shipped artifact (enables one-copy rollback) with:"
echo "  python3 Scripts/harness/release/retain_shipped_artifact.py promote --app \"$APP\""
