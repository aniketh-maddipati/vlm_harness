#!/usr/bin/env bash
# Builds the Lumina other people install. Everything a release build adds to the project lives in
# Config/Release.xcconfig (sandbox, hardened runtime, arm64, the store's Info.plist keys); this
# script only archives with it, exports, checks the result and hands it on. It never commits and
# never holds a secret: credentials come from the keychain or from files outside the repo.
#
#   bash Scripts/release.sh local              sandboxed, signed ad hoc: what the sandbox does to the app, on this Mac only
#   bash Scripts/release.sh dmg                Developer ID → Lumina-<version>.dmg, notarised and stapled when NOTARY_PROFILE is set
#   bash Scripts/release.sh store              Apple Distribution → Lumina.pkg for App Store Connect / TestFlight
#   bash Scripts/release.sh store --validate   … and ask App Store Connect whether it would accept it
#   bash Scripts/release.sh store --upload     … and upload it (asks first)
#   bash Scripts/release.sh preflight <Lumina.app> [local|dmg|store] [--strict]
#
# Credentials (docs/release/APP-STORE.md, "Once"):
#   NOTARY_PROFILE=<name>     a profile made with `xcrun notarytool store-credentials <name>`   (dmg)
#   ASC_KEY_ID, ASC_ISSUER_ID an App Store Connect API key; the .p8 in ~/.appstoreconnect/private_keys  (store)
#
# LUMINA_UI=sets (default: the design page in a WKWebView, needs the network.client entitlement to
# start in a sandbox) or LUMINA_UI=native (the SwiftUI app: no network entitlement at all).
#
# Output: build/release/<version>-<build>/ (ignored by git). VERSION=1.0.1 overrides the xcconfig.
# A notarised dmg is also copied, with its checksum and archive, to ~/Desktop/Lumina Releases/<version>-<build>/
# (LUMINA_RELEASES_DIR=<folder> changes where, LUMINA_RELEASES_DIR= turns it off).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-}"; shift || true
case "$MODE" in
  preflight) exec bash Scripts/release_preflight.sh "$@" ;;
  local|dmg|store) ;;
  *) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
VALIDATE=0; UPLOAD=0; STRICT=()
for a in "$@"; do
  case "$a" in
    --validate) VALIDATE=1 ;;
    --upload) VALIDATE=1; UPLOAD=1 ;;
    --strict) STRICT=(--strict) ;;
    *) echo "unknown option $a" >&2; exit 64 ;;
  esac
done

say() { printf '\n→ %s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# A release is a commit: the build manifest names it, and the build number counts commits.
SHA="$(git rev-parse --short HEAD)"
BUILD="$(git rev-list --count HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  [[ "$MODE" == local ]] && echo "note: uncommitted changes (fine for local)" || die "uncommitted changes: a release is built from a commit"
fi
VERSION="${VERSION:-$(sed -n 's/^MARKETING_VERSION *= *//p' Config/Release.xcconfig | head -1)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '$VERSION' is not x.y.z"

OUT="build/release/$VERSION-$BUILD"
ARCHIVE="$OUT/Lumina.xcarchive"
RELEASES="${LUMINA_RELEASES_DIR-$HOME/Desktop/Lumina Releases}"
rm -rf "$OUT"; mkdir -p "$OUT"

# The overrides go in a generated xcconfig that includes Config/Release.xcconfig: a setting given
# on xcodebuild's command line loses to one in a -xcconfig file, a later line in the file wins.
UI="${LUMINA_UI:-sets}"
case "$UI" in
  sets) ENTITLEMENTS=Config/Lumina-Sets.entitlements ;;
  native) ENTITLEMENTS=Config/Lumina.entitlements ;;
  *) die "LUMINA_UI is sets or native" ;;
esac
SETTINGS=("MARKETING_VERSION = $VERSION" "CURRENT_PROJECT_VERSION = $BUILD" "CODE_SIGN_ENTITLEMENTS = $ENTITLEMENTS")
AUTH=()
case "$MODE" in
  local)
    # Ad hoc: no certificate, no profile. The sandbox and the hardened runtime still apply. Its own
    # bundle id, so its sandbox container is not the real app's.
    SETTINGS+=("CODE_SIGN_STYLE = Manual" "CODE_SIGN_IDENTITY = -" "DEVELOPMENT_TEAM =" "PRODUCT_BUNDLE_IDENTIFIER = ${LOCAL_BUNDLE_ID:-com.lumina.app.sandbox-check}") ;;
  dmg)
    security find-identity -v -p codesigning | grep -q "Developer ID Application" || die "no Developer ID Application certificate in the keychain"
    SETTINGS+=("CODE_SIGN_STYLE = Manual" "CODE_SIGN_IDENTITY = Developer ID Application" "OTHER_CODE_SIGN_FLAGS = --timestamp") ;;
  store)
    SETTINGS+=("CODE_SIGN_STYLE = Automatic")
    if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
      KEY="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
      [[ -f "$KEY" ]] || die "no API key at $KEY"
      AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    else
      echo "note: no ASC_KEY_ID / ASC_ISSUER_ID: signing uses the account Xcode is signed in to"
      AUTH=(-allowProvisioningUpdates)
    fi ;;
esac
XCCONFIG="$OUT/build.xcconfig"
{ echo "#include \"$ROOT/Config/Release.xcconfig\""; printf '%s\n' "${SETTINGS[@]}"; } > "$XCCONFIG"

say "archiving $VERSION ($BUILD) from $SHA · $MODE · ui $UI"
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Release \
  -xcconfig "$XCCONFIG" -derivedDataPath "$OUT/DD" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  ${AUTH[@]+"${AUTH[@]}"} archive -quiet \
  || die "archive failed (log above)"
APP="$ARCHIVE/Products/Applications/Lumina.app"
[[ -d "$APP" ]] || die "the archive holds no Lumina.app"
rm -rf "$OUT/DD"

case "$MODE" in
  local)
    ditto "$APP" "$OUT/Lumina.app"
    bash Scripts/release_preflight.sh "$OUT/Lumina.app" local ${STRICT[@]+"${STRICT[@]}"}
    say "built $OUT/Lumina.app (sandboxed, ad hoc). Open it with: open -n '$OUT/Lumina.app'"
    ;;

  dmg)
    say "exporting with Developer ID"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
      -exportOptionsPlist Config/ExportOptions-DeveloperID.plist -quiet || die "export failed"
    APP="$OUT/export/Lumina.app"
    DMG="$OUT/Lumina-$VERSION.dmg"
    STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
    ditto "$APP" "$STAGE/Lumina.app"
    ln -s /Applications "$STAGE/Applications"
    say "making $(basename "$DMG")"
    hdiutil create -volname "Lumina $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov -quiet "$DMG"
    codesign --sign "Developer ID Application" --timestamp "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
      say "notarising (a few minutes)"
      xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$OUT/notary.log"
      grep -q "status: Accepted" "$OUT/notary.log" || die "notarisation was not accepted: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
      xcrun stapler staple "$DMG"
      xcrun stapler staple "$APP"
      bash Scripts/release_preflight.sh "$APP" dmg --notarised ${STRICT[@]+"${STRICT[@]}"}
      spctl --assess --type open --context context:primary-signature -v "$DMG"
    else
      echo "note: NOTARY_PROFILE is not set: the dmg is signed but NOT notarised. Gatekeeper refuses it on other Macs."
      bash Scripts/release_preflight.sh "$APP" dmg ${STRICT[@]+"${STRICT[@]}"}
    fi
    shasum -a 256 "$DMG" | tee "$OUT/SHA256.txt"
    # A notarised dmg is one to send: keep it, its checksum and the archive (the dSYMs for its crash
    # reports) where Finder shows them, outside a checkout that may be removed.
    if [[ -n "${NOTARY_PROFILE:-}" && -n "$RELEASES" ]]; then
      KEEP="$RELEASES/$VERSION-$BUILD"
      rm -rf "$KEEP"; mkdir -p "$KEEP"
      ditto "$DMG" "$KEEP/$(basename "$DMG")"
      ditto "$OUT/SHA256.txt" "$KEEP/SHA256.txt"
      ditto "$ARCHIVE" "$KEEP/Lumina.xcarchive"
      say "copied to $KEEP"
    fi
    say "done: $DMG"
    ;;

  store)
    say "exporting for App Store Connect"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
      -exportOptionsPlist Config/ExportOptions-AppStore.plist ${AUTH[@]+"${AUTH[@]}"} -quiet || die "export failed"
    PKG="$(ls "$OUT"/export/*.pkg 2>/dev/null | head -1)"
    [[ -f "$PKG" ]] || die "the export holds no .pkg"
    # The export signs again for distribution: the app App Store Connect gets is the one in the
    # pkg, not the archive's (signed for development under automatic signing).
    pkgutil --check-signature "$PKG" | grep -q "Mac Developer Installer" || die "the pkg is not signed with the Mac Installer Distribution certificate"
    UNPACKED="$(mktemp -d)"; trap 'rm -rf "$UNPACKED"' EXIT
    pkgutil --expand-full "$PKG" "$UNPACKED/pkg" || die "the pkg does not unpack"
    APP="$(find "$UNPACKED/pkg" -maxdepth 3 -name Lumina.app | head -1)"
    [[ -d "$APP" ]] || die "the pkg holds no Lumina.app"
    bash Scripts/release_preflight.sh "$APP" store ${STRICT[@]+"${STRICT[@]}"}
    if (( VALIDATE )); then
      [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || die "--validate and --upload need ASC_KEY_ID and ASC_ISSUER_ID"
      say "validating with App Store Connect"
      xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" || die "App Store Connect refused the package"
    fi
    if (( UPLOAD )); then
      read -r -p "Upload Lumina $VERSION ($BUILD) to App Store Connect? [y/N] " yes
      [[ "$yes" == y || "$yes" == Y ]] || { echo "not uploaded: $PKG"; exit 0; }
      xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" || die "upload failed"
      say "uploaded. It shows in App Store Connect ▸ TestFlight after processing (10–30 min)."
    else
      say "done: $PKG"
    fi
    ;;
esac
