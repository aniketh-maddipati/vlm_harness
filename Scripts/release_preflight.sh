#!/usr/bin/env bash
# Checks a built Lumina.app against what a release must be, without launching it. Reads only.
#
#   bash Scripts/release_preflight.sh <Lumina.app> [local|dmg|store] [--notarised] [--strict] [--allow=D2,S4,…]
#
# FAIL: the build must not ship. WARN: a known open item, tagged with the task or decision that
# closes it (docs/release/TASKS.md, APP-STORE.md); --strict turns every WARN into a FAIL, which is
# how the final release candidate is checked.
# --allow=<tags> (or PREFLIGHT_ALLOW=<tags>, which passes through Scripts/release.sh) keeps the
# WARNs of those open items as WARNs under --strict: CI runs strict with the items still open, so
# any new WARN fails it. An item is allowed until its task lands, then its tag comes off the list
# (an allowed tag with no WARN left is printed as stale). Never for a release candidate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/page_files.sh"

APP="${1:-}"; MODE=local; NOTARISED=0; STRICT=0; ALLOW=",${PREFLIGHT_ALLOW:-},"; SEEN=","
shift || true
for a in "$@"; do
  case "$a" in
    local|dmg|store) MODE="$a" ;;
    --notarised) NOTARISED=1 ;;
    --strict) STRICT=1 ;;
    --allow=*) ALLOW="$ALLOW${a#--allow=}," ;;
    *) echo "unknown option $a" >&2; exit 64 ;;
  esac
done
[[ -d "$APP/Contents" ]] || { echo "usage: release_preflight.sh <Lumina.app> [local|dmg|store] [--notarised] [--strict]" >&2; exit 64; }

FAILS=0; WARNS=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
# warn <tag> <what>: the tag is the task or decision that closes the item.
warn() {
  local tag="$1"; shift; SEEN="$SEEN$tag,"
  if (( STRICT )) && [[ "$ALLOW" != *",$tag,"* ]]; then fail "$* [$tag]"
  else printf '  WARN  %s [%s%s]\n' "$*" "$tag" "$( (( STRICT )) && echo ', allowed')"; WARNS=$((WARNS + 1)); fi
}
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
# Notarisation asks for a secure timestamp. A store export has none (App Store Connect signs again).
if [[ "$MODE" == dmg ]]; then
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
  warn D2 "network.client: WebKit needs it in a sandbox, so the system no longer keeps photos on the Mac; the app must (TASKS S1, D2)"
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
# Test switches read from the environment (AGENTS.md: "never set in the app") must not be in a
# release binary: in the sources they sit under `#if DEBUG || LUMINA_TOOLS` (Debug builds, the probe
# and lumina-render), which the app's Release build does not define. Two checks, because the first
# cannot see every name: Swift keeps a literal of 15 bytes or fewer in the code itself, not as text
# (LUMINA_CANVAS and LUMINA_RULES never showed here). The second is the read itself: the app has no
# other use for the process environment, so a Release binary does not name -[NSProcessInfo environment].
TEXT="$(strings - "$BIN" 2>/dev/null)"
HOOKS="$(grep -oE 'LUMINA_[A-Z_]{3,}' <<<"$TEXT" | sort -u | tr '\n' ' ')"
[[ -z "$HOOKS" ]] && ok "no test switch named in the binary" || warn S4 "test switches compiled in (TASKS S4): $HOOKS"
grep -qx 'environment' <<<"$TEXT" && warn S4 "the binary reads the process environment: a switch outside #if DEBUG || LUMINA_TOOLS? (TASKS S4)" || ok "the binary does not read the process environment (no switch can be set from outside)"
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
# Each "required reason" API the binary names needs its category in the manifest, or App Store
# Connect answers the upload with ITMS-91053. Selectors and imported symbols show as text.
if [[ -f "$RES/PrivacyInfo.xcprivacy" ]]; then
  SYMS="$TEXT"$'\n'"$(nm -u "$BIN" 2>/dev/null)"
  MANIFEST="$(plutil -convert xml1 -o - "$RES/PrivacyInfo.xcprivacy" 2>/dev/null)"
  for pair in 'SystemBootTime:systemUptime|mach_absolute_time' \
              'DiskSpace:volumeAvailableCapacity|NSFileSystemFreeSize|statfs' \
              'UserDefaults:NSUserDefaults|standardUserDefaults' \
              'FileTimestamp:NSFileModificationDate|NSFileCreationDate|contentModificationDate|creationDate|_stat$|_lstat$|_fstat$'; do
    cat="${pair%%:*}"; pat="${pair#*:}"
    if grep -qE "$pat" <<<"$SYMS"; then
      grep -q "NSPrivacyAccessedAPICategory$cat" <<<"$MANIFEST" && ok "privacy manifest declares $cat" || fail "the binary uses a $cat API but PrivacyInfo.xcprivacy gives no reason for it"
    fi
  done
fi
if [[ -f "$RES/LuminaBuild.json" ]]; then
  MSHA="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("git_sha",""), d.get("configuration",""))' "$RES/LuminaBuild.json")"
  [[ "$MSHA" == "$(git -C "$ROOT" rev-parse HEAD) Release" ]] && ok "build manifest: this commit, Release" || warn manifest "build manifest says '$MSHA' (not HEAD / Release)"
else fail "LuminaBuild.json missing"; fi
# The design's self-test is one of the page files, which ship byte for byte (checked above), so the
# file is in the bundle. What a release must not do is serve it: SetsSchemeHandler's list of served
# page files leaves it out unless DEBUG or LUMINA_TOOLS is defined, and then the binary has no name
# for it (18 bytes: it would show as text). `?selftest` then gets "not served".
if grep -q 'lumina-selftest' <<<"$TEXT"; then
  warn S4 "the binary serves the design's self-test with ?selftest (TASKS S4)"
elif [[ -f "$RES/lumina-selftest.js" ]]; then
  ok "the design's self-test is not served (in the bundle as a page file; the binary has no name for it)"
else
  ok "the design's self-test is not served (not in the bundle)"
fi
JUNK="$(find "$APP" \( -name .DS_Store -o -name '*.xctest' -o -name '*.dSYM' -o -name '*.swiftmodule' -o -name '*.map' -o -name '*.bundle' \) 2>/dev/null | head -5)"
[[ -z "$JUNK" ]] && ok "no stray files" || fail "stray files: $JUNK"
THIRD="$(find "$RES" -iname '*licen*' -o -iname '*acknowledg*' -o -iname '*notice*' 2>/dev/null | head -1)"
[[ -n "$THIRD" ]] && ok "third-party notices" || warn R6 "no third-party notices for React and Babel (MIT asks for the licence text; TASKS R6)"

# The rule is "the app makes no network request" (THREAT-MODEL B4), not "no URL in the bundle":
# since v7 the page files name URLs (the three contact links, support.js's CDN names that
# SetsSchemeHandler maps to lumina://vendor, Edit's browser-only photo fallback, XML namespaces).
# The page is held offline by the content rule and the navigation policy, plus the three hand-offs
# in SetsExternalLinks.swift. So a URL string is listed with its file and line, never failed;
# whatever could reach the network on its own (a networking API in the binary, an ATS exception,
# an unreviewed script, a network call in plumbing.js, the content rule gone) fails.
echo "network"
IMPORTS="$(nm -u "$BIN" 2>/dev/null)"
NETSYM="$(grep -oE 'NSURLSession|URLSession|NSURLConnection|NSURLDownload|NWConnection|NWListener|NWBrowser|NWPathMonitor|^_nw_[a-z_]+|CFSocket[A-Za-z]*|CFStreamCreatePairWithSocket[A-Za-z]*|CFHTTP[A-Za-z]*|^_(socket|connect|getaddrinfo|gethostbyname|sendto|bind|listen)$' <<<"$IMPORTS" | sort -u | tr '\n' ' ')"
[[ -z "$NETSYM" ]] && ok "the binary imports no networking API (URLSession, Network, CFNetwork sockets, BSD sockets)" || fail "the binary imports networking APIs: $NETSYM"
otool -L "$BIN" 2>/dev/null | grep -qE '/(Network|CFNetwork)\.framework/' && fail "links Network.framework or CFNetwork directly" || ok "links neither Network.framework nor CFNetwork"
ATS="$(for k in NSAllowsArbitraryLoads NSAllowsArbitraryLoadsInWebContent NSAllowsArbitraryLoadsForMedia NSAllowsLocalNetworking; do [[ "$(plist "NSAppTransportSecurity:$k")" == true ]] && printf '%s ' "$k"; done; plist NSAppTransportSecurity:NSExceptionDomains >/dev/null && printf 'NSExceptionDomains')"
[[ -z "$ATS" ]] && ok "no App Transport Security exception" || fail "App Transport Security exceptions in Info.plist: ${ATS% }"
grep -E '"url-filter"' <<<"$TEXT" | grep -q '"block"' && ok "the page's offline content rule is compiled in" || fail "no content rule blocking the page's network loads in the binary (SetsWebView.make)"
KNOWN=" ${PAGE_FILES[*]} plumbing.js react.production.min.js react-dom.production.min.js babel.min.js "
UNKNOWN="$(cd "$RES" && find . -type f \( -iname '*.js' -o -iname '*.mjs' -o -iname '*.cjs' -o -iname '*.html' -o -iname '*.htm' -o -iname '*.xhtml' -o -iname '*.svg' -o -iname '*.wasm' \) | sed 's|^\./||' | while IFS= read -r f; do [[ "$KNOWN" == *" $f "* ]] || printf '%s; ' "$f"; done)"
[[ -z "$UNKNOWN" ]] && ok "every script or page in the bundle is a page file, plumbing.js or a pinned vendor file" || fail "unreviewed scripts or pages in the bundle: ${UNKNOWN%; }"
PNET="$(grep -nE '(https?|wss?|ftp)://|\b(WebSocket|EventSource|XMLHttpRequest|RTCPeerConnection|importScripts)\b|sendBeacon' "$RES/plumbing.js" 2>/dev/null | cut -c1-120 | head -5)"
[[ -z "$PNET" ]] && ok "plumbing.js names no network URL or socket API (its fetches are lumina://)" || fail "plumbing.js reaches for the network: $PNET"
# The report. Allowlisted = the hand-offs SetsExternalLinks.swift names (the menu's "Contact on X" is the same URL).
/usr/bin/python3 - "$RES" "$BIN" "$ROOT/Lumina/Sets/Core/SetsExternalLinks.swift" "${PAGE_FILES[@]}" <<'PY' || fail "the URL report did not run"
import re, subprocess, sys
res, binary, links, files = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
src = open(links, encoding="utf-8").read() if links else ""
allowed = set(re.findall(r'URL\(string:\s*"([^"]+)"\)', src))
recipients = set(re.findall(r'bugReportRecipient\s*=\s*"([^"]+)"', src))
url_re = re.compile(r'(?:https?|wss?|ftp)://[^\s"\'`<>)\\]+|mailto:[^\s"\'`<>)\\]+')
namespace = ("http://www.w3.org/", "http://ns.adobe.com/", "http://www.apple.com/DTDs/")
bin_text = subprocess.run(["strings", "-", binary], capture_output=True).stdout.decode("utf-8", "replace")
def kind(u):
    if u.startswith(namespace): return "namespace, not fetched"
    if u.startswith("mailto:"):
        to = u[7:].split("?")[0]
        return "allowlisted hand-off" if to in recipients else "mailto the app refuses (not in SetsExternalLinks)"
    if u in allowed or u.rstrip("/") in {a.rstrip("/") for a in allowed}: return "allowlisted hand-off"
    if u in bin_text: return "mapped to lumina:// by the app"
    return "blocked in the app (content rule); browser-only"
seen = 0
for f in files:
    try: lines = open(f"{res}/{f}", encoding="utf-8", errors="replace").read().split("\n")
    except OSError: continue
    for n, line in enumerate(lines, 1):
        for u in dict.fromkeys(url_re.findall(line)):
            u = u.replace("&amp;", "&")
            print(f"  url   {f}:{n}  {u[:90]}{'…' if len(u) > 90 else ''}  ({kind(u)})"); seen += 1
for u in sorted(set(url_re.findall(bin_text))):
    k = kind(u)
    if k.startswith("blocked"): k = "a string, not a request"
    if any(u.startswith(m) for m in ("https://unpkg.com/", "https://picsum.photos/")): k = "names a page URL the app maps or rewrites to lumina://"
    print(f"  url   binary  {u[:90]}  ({k})"); seen += 1
print(f"  ok    {seen} URL strings listed (reported, not failed: the rule is no request, not no URL)")
PY

SIZE="$(du -sh "$APP" | cut -f1)"
echo "size $SIZE"
for t in ${ALLOW//,/ }; do [[ "$SEEN" == *",$t,"* ]] || echo "note: --allow=$t, but nothing is open under $t any more: take it off the list"; done
echo
if (( FAILS )); then echo "preflight: $FAILS failed, $WARNS warned"; exit 1; fi
echo "preflight: passed, $WARNS warned"
