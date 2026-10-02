#!/usr/bin/env bash
# Q4 hostile and damaged input (docs/release/STRESS-MATRIX.md section 7; report: docs/release/stress/Q4-hostile.md).
#
#   bash Tests/probe/fuzz/run.sh build                  the two tools (swiftc, the app's SetsIngest / SetsFileOps unchanged)
#   bash Tests/probe/fuzz/run.sh ingest [SEED] [N]      head + preview-range fuzzer: N seeded cases (default 10,000)
#                                                       through the page's parseHead (Node) and SetsIngest head/preview/thumb
#   bash Tests/probe/fuzz/run.sh decode [SEED] [N] [R]  N mutated JPEGs into ImageIO and R mutated ARWs into CIRAWFilter, in
#                                                       hostile-decode, signed ad hoc with Config/Lumina-Sets.entitlements
#                                                       (App Sandbox): a decoder crash kills the helper only. With
#                                                       LUMINA_FIXTURE_ROOT, 2 real ARWs from its src/ join the synthetic
#                                                       ones; their mutations stay under ~/LuminaEvidence/hostile
#   bash Tests/probe/fuzz/run.sh xmp                    the page's sidecar code (mergeXmp, hasDevelop) on hostile XMP
#   bash Tests/probe/fuzz/run.sh fixtures               the folders Tests/probe/scenarios/hostile-*.json copy, into
#                                                       $LUMINA_FIXTURE_ROOT (default ~/LuminaEvidence/fixtures)
#   bash Tests/probe/fuzz/run.sh bridge                 LuminaLogicTests/SetsBridgeOpsTests (the op table)
#   bash Tests/probe/fuzz/run.sh bridge-crash           the inputs that stop the app process, one test process each,
#                                                       crash reports kept
#
# Everything mutated lives under ~/LuminaEvidence/hostile/<run>.noindex (Spotlight skips a .noindex folder;
# each also holds .metadata_never_index). Nothing is opened in Finder, Preview or Quick Look, and nothing
# is sent anywhere. Inputs that stopped a tool are kept in <run>/findings with the crash report.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
EV="${LUMINA_HOSTILE_OUT:-$HOME/LuminaEvidence/hostile}"
export HOSTILE_BIN="$EV/build"
SRC=Tests/probe/fuzz/Sources
APP=(Lumina/Sets/Core/SetsIngest.swift Lumina/Sets/Core/SetsFileOps.swift)
mode="${1:-all}"; shift || true

build() {
  mkdir -p "$HOSTILE_BIN"
  xcrun swiftc -O -parse-as-library -swift-version 5 "$SRC/Common.swift" "$SRC/IngestFuzz.swift" "${APP[@]}" -o "$HOSTILE_BIN/hostile-ingest" 2> "$HOSTILE_BIN/build-ingest.log" || { cat "$HOSTILE_BIN/build-ingest.log" >&2; exit 2; }
  # A sandboxed command-line tool needs a bundle identifier of its own: an Info.plist in __TEXT.
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.lumina.hostile-decode" -c "Add :CFBundleName string hostile-decode" "$HOSTILE_BIN/Info.plist" >/dev/null 2>&1 || true
  xcrun swiftc -O -parse-as-library -swift-version 5 "$SRC/Common.swift" "$SRC/DecodeHelper.swift" "${APP[@]}" -o "$HOSTILE_BIN/hostile-decode" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$HOSTILE_BIN/Info.plist" 2> "$HOSTILE_BIN/build-decode.log" || { cat "$HOSTILE_BIN/build-decode.log" >&2; exit 2; }
  # The app's sandbox, ad hoc: the helper gets a container and no access to the user's files.
  codesign -s - --force -i com.lumina.hostile-decode --entitlements Config/Lumina-Sets.entitlements "$HOSTILE_BIN/hostile-decode"
  echo "built $HOSTILE_BIN/hostile-ingest, $HOSTILE_BIN/hostile-decode (sandboxed)"
}

bridge_test() {
  xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
    -destination 'platform=macOS,arch=arm64' -only-testing:"LuminaLogicTests/SetsBridgeOpsTests$1" test
}

case "$mode" in
  build) build ;;
  ingest) build; node Tests/probe/fuzz/fuzz.mjs ingest --seed "${1:-1}" --n "${2:-10000}" --out "$EV/ingest-seed${1:-1}.noindex" ;;
  decode) build; node Tests/probe/fuzz/fuzz.mjs decode --seed "${1:-1}" --n "${2:-3000}" --raw "${3:-300}" --out "$EV/decode-seed${1:-1}.noindex" ;;
  xmp) node Tests/probe/fuzz/fuzz.mjs xmp --out "$EV/xmp.noindex" ;;
  fixtures) build; node Tests/probe/fuzz/fuzz.mjs fixtures --out "${LUMINA_FIXTURE_ROOT:-$HOME/LuminaEvidence/fixtures}" ;;
  bridge) bridge_test "" ;;
  bridge-crash)
    mkdir -p "$EV/bridge-crash"
    for c in seqHuge seqInf seqNaN layoutInf loupeInf; do
      t0=$(date +%s)
      TEST_RUNNER_LUMINA_BRIDGE_CRASH_CASES=$c bridge_test /testCrashingInputs > "$EV/bridge-crash/$c.log" 2>&1 || true
      if grep -q "survived" "$EV/bridge-crash/$c.log"; then echo "$c: survived"; continue; fi
      sleep 2                                                   # the report lands a moment after the process
      ips=$(ls -t "$HOME"/Library/Logs/DiagnosticReports/Lumina-*.ips 2>/dev/null | head -1 || true)
      if [[ -n $ips && $(stat -f %m "$ips") -ge $t0 ]]; then cp "$ips" "$EV/bridge-crash/$c.ips"; else ips=""; fi
      echo "$c: $(grep -m1 -o 'Fatal error: .*' "$EV/bridge-crash/$c.log" || echo 'stopped') ${ips:+· $EV/bridge-crash/$c.ips}"
    done ;;
  all) "$0" ingest; "$0" decode; "$0" xmp; "$0" bridge; "$0" bridge-crash ;;
  *) sed -n 2,25p "$0"; exit 2 ;;
esac
