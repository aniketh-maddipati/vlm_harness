#!/usr/bin/env bash
# Makes the DMGs the owner sends to people by hand (Lumina, Lumina Skim, or both), checks each one the
# way a recipient's Mac will, and leaves them in ~/LuminaEvidence/release/<date>/. It uploads nothing
# and sends nothing: the owner does that.
#
#   bash Scripts/publish_dmg.sh [lumina|skim|both] [--ref <git ref>] [--no-launch]
#
#   --ref        what to build (default origin/main, fetched first), in a detached worktree of its own
#                (~/LuminaEvidence/release-build), so no checkout's work is touched
#   --no-launch  skip opening the quarantined copy (the other checks still run)
#
# Needs: the "Developer ID Application" certificate in the keychain and a notarytool keychain profile
# (NOTARY_PROFILE, default lumina-notary; docs/release/APP-STORE.md "Once"). No secret is read or printed.
#
# Per app, into ~/LuminaEvidence/release/<date>/ (LUMINA_RELEASE_OUT=<dir> changes it):
#   <App>-<version>.dmg, SHA256-<kind>.txt, <kind>.xcarchive (dSYMs), <kind>-build.log,
#   <kind>-verify.txt (every Gatekeeper answer), <kind>-changes.txt (commits since the last DMG of it)
# and ~/LuminaEvidence/release/last-<kind>.sha records the commit, so the next changes list starts there.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WHICH="both"; REF="origin/main"; LAUNCH=1
while (( $# )); do
  case "$1" in
    lumina|skim|both) WHICH="$1" ;;
    --ref) REF="${2:?--ref needs a value}"; shift ;;
    --no-launch) LAUNCH=0 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument $1" >&2; exit 64 ;;
  esac
  shift
done
case "$WHICH" in both) KINDS=(lumina skim) ;; *) KINDS=("$WHICH") ;; esac

say() { printf '\n→ %s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

export NOTARY_PROFILE="${NOTARY_PROFILE:-lumina-notary}"
security find-identity -v -p codesigning | grep -q "Developer ID Application" || die "no Developer ID Application certificate in the keychain"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notary profile '$NOTARY_PROFILE' does not answer. The owner runs once, in Terminal:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <developer Apple ID> --team-id QHB498M84T
  (it asks for an app-specific password from account.apple.com)"

EVID="$HOME/LuminaEvidence/release"
OUTDIR="${LUMINA_RELEASE_OUT:-$EVID/$(date +%F)}"
mkdir -p "$OUTDIR"

# A clean, detached worktree at the ref: release.sh refuses uncommitted changes, and a release is a commit.
cd "$ROOT"
[[ "$REF" == origin/* ]] && git fetch -q origin "${REF#origin/}"
SRC="$EVID/../release-build"
git worktree remove --force "$SRC" 2>/dev/null || rm -rf "$SRC"
git worktree prune
git worktree add -q --detach "$SRC" "$REF"
SRC="$(cd "$SRC" && pwd)"
SHA="$(git -C "$SRC" rev-parse HEAD)"
say "building ${KINDS[*]} from $REF ($(git -C "$SRC" log --oneline -1))"

verify() {  # verify <kind> <dmg> <app name>  → appends to <kind>-verify.txt, fails on any refusal
  local kind="$1" dmg="$2" name="$3" log="$OUTDIR/$1-verify.txt" mnt tmp ok=1
  : > "$log"
  run() { echo "\$ $*" >> "$log"; "$@" >> "$log" 2>&1 || { echo "  ✗ failed" >> "$log"; ok=0; }; }
  run spctl -a -vv -t open --context context:primary-signature "$dmg"
  run xcrun stapler validate "$dmg"
  mnt="$(mktemp -d)"; tmp="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "$mnt" "$dmg" || die "$kind: the dmg does not mount"
  run spctl -a -vv "$mnt/$name.app"
  run xcrun stapler validate "$mnt/$name.app"
  run codesign --verify --deep --strict "$mnt/$name.app"
  # A downloaded copy: the quarantine flag a browser sets, then Gatekeeper's first-launch question.
  ditto "$mnt/$name.app" "$tmp/$name.app"
  hdiutil detach -quiet "$mnt" || hdiutil detach -force -quiet "$mnt"
  xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;" "$tmp/$name.app"
  run spctl -a -vv -t exec "$tmp/$name.app"
  if (( LAUNCH )); then
    # Opened hidden and in the background. A refused app never starts, so a running process is the pass.
    echo "\$ open -n -g -j <quarantined copy>" >> "$log"
    open -n -g -j "$tmp/$name.app" >> "$log" 2>&1 || true
    local pid=""
    for _ in $(seq 1 20); do pid="$(pgrep -f "$tmp/$name.app/Contents/MacOS/" | head -1 || true)"; [[ -z "$pid" ]] && pid="$(pgrep -f "AppTranslocation/.*/$name.app/Contents/MacOS/" | head -1 || true)"; [[ -n "$pid" ]] && break; sleep 0.5; done
    if [[ -n "$pid" ]]; then echo "  launched from quarantine (pid $pid), no Gatekeeper refusal" >> "$log"; kill "$pid" 2>/dev/null || true
    else echo "  ✗ did not launch from quarantine within 10 s" >> "$log"; ok=0; fi
  fi
  rm -rf "$tmp"; rmdir "$mnt" 2>/dev/null || true
  (( ok )) || { cat "$log"; die "$kind: a Gatekeeper check failed ($log)"; }
}

for kind in "${KINDS[@]}"; do
  case "$kind" in lumina) NAME="Lumina"; PREFIX="" ;; skim) NAME="Lumina Skim"; PREFIX="skim-" ;; esac
  say "$NAME: archive, Developer ID, notarise, staple (first notarisation can take 20 min)"
  ( cd "$SRC" && LUMINA_APP="$kind" PREFLIGHT_ALLOW="${PREFLIGHT_ALLOW:-D2}" LUMINA_RELEASES_DIR= \
      bash Scripts/release.sh dmg --strict ) > "$OUTDIR/$kind-build.log" 2>&1 \
    || { tail -30 "$OUTDIR/$kind-build.log"; die "$NAME: release.sh failed ($OUTDIR/$kind-build.log)"; }
  VERSION="$(sed -n 's/^MARKETING_VERSION *= *//p' "$SRC/Config/Release.xcconfig" | head -1)"
  BUILD="$(git -C "$SRC" rev-list --count HEAD)"
  REL="$SRC/build/release/$PREFIX$VERSION-$BUILD"
  DMG="$REL/${NAME// /-}-$VERSION.dmg"
  [[ -f "$DMG" ]] || die "$NAME: no dmg at $DMG"
  say "$NAME: Gatekeeper checks as a recipient's Mac"
  verify "$kind" "$DMG" "$NAME"
  ditto "$DMG" "$OUTDIR/$(basename "$DMG")"
  rm -rf "$OUTDIR/$kind.xcarchive"; ditto "$REL/Lumina.xcarchive" "$OUTDIR/$kind.xcarchive"
  (cd "$OUTDIR" && shasum -a 256 "$(basename "$DMG")" > "SHA256-$kind.txt")
  LAST="$(cat "$EVID/last-$kind.sha" 2>/dev/null || true)"
  if [[ -n "$LAST" ]] && git -C "$SRC" cat-file -e "$LAST^{commit}" 2>/dev/null; then RANGE="$LAST..$SHA"; else RANGE="$SHA~30..$SHA"; fi
  { echo "$NAME $VERSION ($BUILD) from $SHA; commits $RANGE"; git -C "$SRC" log --no-merges --format='- %s' "$RANGE"; } > "$OUTDIR/$kind-changes.txt"
  echo "$SHA" > "$EVID/last-$kind.sha"
  printf '  %s  %s  %s\n' "$(du -h "$OUTDIR/$(basename "$DMG")" | cut -f1)" "$OUTDIR/$(basename "$DMG")" "$(cut -d' ' -f1 "$OUTDIR/SHA256-$kind.txt")"
done

git worktree remove --force "$SRC" 2>/dev/null || true
say "done: $OUTDIR (nothing uploaded or sent)"
