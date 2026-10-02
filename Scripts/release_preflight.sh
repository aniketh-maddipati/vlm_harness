#!/usr/bin/env bash
# Checks a built Lumina.app against what a release must be, without launching it. Reads only.
#
#   bash Scripts/release_preflight.sh <Lumina.app> [local|dmg|store] [--notarised] [--strict]
#
# FAIL: the build must not ship. WARN: a known open item (docs/release/TASKS.md names the task);
# --strict turns every WARN into a FAIL, which is how the final release candidate is checked.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/page_files.sh"

APP="${1:-}"; MODE=local; NOTARISED=0; STRICT=0
shift || true
for a in "$@"; do
  case "$a" in
    local|dmg|store) MODE="$a" ;;
    --notarised) NOTARISED=1 ;;
    --strict) STRICT=1 ;;
    *) echo "unknown option $a" >&2; exit 64 ;;
  esac
done
[[ -d "$APP/Contents" ]] || { echo "usage: release_preflight.sh <Lumina.app> [local|dmg|store] [--notarised] [--strict]" >&2; exit 64; }

FAILS=0; WARNS=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
warn() { if (( STRICT )); then fail "$*"; else printf '  WARN  %s\n' "$*"; WARNS=$((WARNS + 1)); fi; }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else fail "$what"; fi; }

PLIST="$APP/Contents/Info.plist"
RES="$APP/Contents/Resources"
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

echo "preflight · $APP · $MODE"

echo "signature"
check "signature verifies (deep, strict)" codesign --verify --deep --strict "$APP"
SIG="$(codesign -dvv "$APP" 2>&1)"
grep -q 'flags=.*runtime' <<<"$SIG" && ok "hardened runtime" || fail "hardened runtime is off"
AUTHORITY="$(sed -n 's/^Authority=//p' <<<"$SIG" | head -1)"
case "$MODE" in
  local) ok "signed ad hoc (this Mac only)" ;;
  dmg)   [[ "$AUTHORITY" == "Developer ID Application:"* ]] && ok "$AUTHORITY" || fail "not signed with Developer ID (${AUTHORITY:-ad hoc})" ;;
  store) [[ "$AUTHORITY" == "Apple Distribution:"* || "$AUTHORITY" == "3rd Party Mac Developer Application:"* ]] && ok "$AUTHORITY" || fail "not signed for the App Store (${AUTHORITY:-ad hoc})"
         [[ -f "$APP/Contents/embedded.provisionprofile" ]] && ok "provisioning profile embedded" || fail "no embedded.provisionprofile (TestFlight needs one)" ;;
esac
if [[ "$MODE" != local ]]; then
  grep -q '^Timestamp=' <<<"$SIG" && ok "secure timestamp" || fail "no secure timestamp"
fi
if (( NOTARISED )); then
  check "notarisation ticket stapled" xcrun stapler validate "$APP"
  check "Gatekeeper accepts it" spctl --assess --type execute "$APP"
fi

echo "entitlements"
ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')"
ent() { /usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$ENT" "$1"; }
[[ "$(ent com.apple.security.app-sandbox)" == True ]] && ok "App Sandbox" || fail "App Sandbox is off"
[[ "$(ent com.apple.security.files.user-selected.read-write)" == True ]] && ok "user-selected read-write" || fail "no user-selected read-write: Save cannot write sidecars"
[[ "$(ent com.apple.security.files.bookmarks.app-scope)" == True ]] && ok "app-scope bookmarks" || fail "no app-scope bookmarks: Open Recent cannot reopen"
[[ "$(ent com.apple.security.get-task-allow)" == True ]] && fail "get-task-allow: another process may debug it" || ok "not debuggable (no get-task-allow)"
# Anything beyond the allowlist is a decision, not a default (THREAT-MODEL.md).
ALLOWED='com.apple.security.app-sandbox com.apple.security.files.user-selected.read-write com.apple.security.files.bookmarks.app-scope com.apple.application-identifier com.apple.developer.team-identifier'
EXTRA="$(/usr/bin/python3 -c 'import json,sys; a=set(sys.argv[2].split()); print(" ".join(sorted(k for k,v in json.loads(sys.argv[1]).items() if k not in a and v not in (False,))))' "$ENT" "$ALLOWED")"
if [[ "$EXTRA" == com.apple.security.network.client ]]; then
  warn "network.client: WebKit needs it in a sandbox, so the system no longer keeps photos on the Mac; the app must (TASKS S1, D2)"
elif [[ -z "$EXTRA" ]]; then ok "no other entitlement (no network, no JIT, no library-validation exception)"
else fail "entitlements outside the allowlist: $EXTRA"; fi

echo "Info.plist"
ID="$(plist CFBundleIdentifier)"; VER="$(plist CFBundleShortVersionString)"; BUILD="$(plist CFBundleVersion)"
[[ -n "$ID" ]] && ok "bundle id $ID" || fail "no bundle id"
[[ "$MODE" == local || "$ID" != *sandbox-check* ]] || fail "bundle id is the local check's"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "version $VER" || fail "version '$VER' is not x.y.z"
[[ "$BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && ok "build $BUILD" || fail "build '$BUILD' is not a number"
[[ "$(plist LSApplicationCategoryType)" == public.app-category.photography ]] && ok "category photography" || fail "LSApplicationCategoryType missing"
[[ -n "$(plist NSHumanReadableCopyright)" ]] && ok "copyright" || fail "NSHumanReadableCopyright is empty"
[[ "$(plist ITSAppUsesNonExemptEncryption)" == false ]] && ok "export compliance answered (exempt)" || fail "ITSAppUsesNonExemptEncryption is not false"
MIN="$(plist LSMinimumSystemVersion)"
[[ "${MIN%%.*}" -ge 12 ]] 2>/dev/null && ok "minimum macOS $MIN" || fail "LSMinimumSystemVersion '$MIN' (arm64-only needs 12 or later)"
[[ -n "$(plist CFBundleIconName)$(plist CFBundleIconFile)" && -f "$RES/Assets.car" ]] && ok "app icon" || fail "no app icon"

echo "binary"
ARCHS="$(lipo -archs "$BIN" 2>/dev/null)"
[[ "$ARCHS" == arm64 ]] && ok "arm64" || fail "architectures '$ARCHS' (expected arm64 only)"
[[ ! -d "$APP/Contents/Frameworks" ]] && ok "no embedded frameworks" || fail "embedded frameworks: $(ls "$APP/Contents/Frameworks" | tr '\n' ' ')"
[[ ! -d "$APP/Contents/PlugIns" ]] && ok "no plug-ins" || fail "plug-ins in the bundle: $(ls "$APP/Contents/PlugIns" | tr '\n' ' ')"
# Test switches read from the environment (AGENTS.md: "never set in the app") should not be in a release binary.
HOOKS="$(strings - "$BIN" 2>/dev/null | grep -oE 'LUMINA_[A-Z_]{3,}' | sort -u | tr '\n' ' ')"
[[ -z "$HOOKS" ]] && ok "no test switches in the binary" || warn "test switches compiled in (TASKS S4): $HOOKS"
otool -L "$BIN" 2>/dev/null | grep -qiE 'inject|xctest' && fail "links a test or injection library" || ok "links no test or injection library"

echo "resources"
for f in "${PAGE_FILES[@]}"; do
  cmp -s "$ROOT/design/handoff/lumina-cull/$f" "$RES/$f" && ok "$f = the design, byte for byte" || fail "$f differs from design/handoff/lumina-cull"
done
cmp -s "$ROOT/Lumina/Sets/Web/plumbing.js" "$RES/plumbing.js" && ok "plumbing.js" || fail "plumbing.js differs from Lumina/Sets/Web"
for f in react.production.min.js react-dom.production.min.js babel.min.js; do
  cmp -s "$ROOT/design/handoff/vendor/$f" "$RES/$f" && ok "$f = the pinned vendor file" || fail "$f differs from design/handoff/vendor"
done
[[ -f "$RES/rules-v1.json" ]] && ok "rules-v1.json" || fail "rules-v1.json missing: no Edit look"
if [[ -f "$RES/PrivacyInfo.xcprivacy" ]] && plutil -lint "$RES/PrivacyInfo.xcprivacy" >/dev/null; then ok "privacy manifest"; else fail "PrivacyInfo.xcprivacy missing or invalid"; fi
if [[ -f "$RES/LuminaBuild.json" ]]; then
  MSHA="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("git_sha",""), d.get("configuration",""))' "$RES/LuminaBuild.json")"
  [[ "$MSHA" == "$(git -C "$ROOT" rev-parse HEAD) Release" ]] && ok "build manifest: this commit, Release" || warn "build manifest says '$MSHA' (not HEAD / Release)"
else fail "LuminaBuild.json missing"; fi
[[ -f "$RES/lumina-selftest.js" ]] && warn "the design's self-test ships in the bundle; it loads only with ?selftest (TASKS S4)"
JUNK="$(find "$APP" \( -name .DS_Store -o -name '*.xctest' -o -name '*.dSYM' -o -name '*.swiftmodule' -o -name '*.map' -o -name '*.bundle' \) 2>/dev/null | head -5)"
[[ -z "$JUNK" ]] && ok "no stray files" || fail "stray files: $JUNK"
THIRD="$(find "$RES" -iname '*licen*' -o -iname '*acknowledg*' -o -iname '*notice*' 2>/dev/null | head -1)"
[[ -n "$THIRD" ]] && ok "third-party notices" || warn "no third-party notices for React and Babel (MIT asks for the licence text; TASKS R6)"

SIZE="$(du -sh "$APP" | cut -f1)"
echo "size $SIZE"
echo
if (( FAILS )); then echo "preflight: $FAILS failed, $WARNS warned"; exit 1; fi
echo "preflight: passed, $WARNS warned"
