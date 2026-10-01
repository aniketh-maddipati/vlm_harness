#!/usr/bin/env bash
# Lumina probe suites — drive the page in WKWebView and try to break it.
#
#   bash Scripts/probe.sh reference [--record]   every v5 screen × 2 sizes (+ app twins) and state dumps, byte-compared to
#                                                Tests/probe/reference/manifest.json (--record rewrites it)
#   bash Scripts/probe.sh smoke                  the v5 page runs, its ?selftest passes, plumbing fits, and the app reads,
#                                                keeps, saves sidecars into the folder, reopens (app-smoke needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh selftest               the design's own ?selftest (25 checks, key and large-view timing)
#   bash Scripts/probe.sh contract               plumbing.js still fits the page (run by sets_sync_design.sh)
#   bash Scripts/probe.sh fuzz                   seeded key/mouse storms on the sample shoot
#   bash Scripts/probe.sh edge                   camera-data edge cases   (needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh ingest                 the same edge cases read by the app's native reader
#   bash Scripts/probe.sh card                   golden card + camera-clock parity, page vs native read (needs LUMINA_CARD_DIR)
#   bash Scripts/probe.sh app                    contract + app-smoke: native read, sidecars, .lumina-bak, sessions (needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh fault                  native writes: kill -9 mid-write + relaunch recovery, disk full mid-copy (disk images)
#   bash Scripts/probe.sh scroll                 scrolling Cull while a folder reads (no jump when it ends), then fast scrolling at
#                                                1440×900 and 2560×1440: frame pacing, blank tiles, thumbnail
#                                                upscale, memory. Folder: LUMINA_SCROLL_DIR, else LUMINA_CARD_DIR (only read), else
#                                                408 APFS clones of LUMINA_FIXTURE_ROOT/src, 20 s apart (built once)
#   bash Scripts/probe.sh edit                   the Edit canvas (addendum §8): 2 s drags on exposure and shadows, look-event-to-
#                                                presented-frame latency (p95 ≤ LUMINA_EDIT_P95, default 16 ms), dropped frames,
#                                                rest render, bases resident, canvas vs export ΔE; native first, then the image
#                                                fallback path (LUMINA_CANVAS=image). Folder: LUMINA_EDIT_DIR, else as scroll
#   bash Scripts/probe.sh raw9                   RAW 9 (§8): decoder map, time to first tile / full region, export time + memory
#                                                per decoder version, the forced per-file fallback, tiles vs export ΔE per version
#   bash Scripts/probe.sh readspeed              how fast a folder reads: Open → first rows, first thumbnail, first screen full,
#                                                100 / 500 / 1000 / 2000 photos, done; photos per second. Folder: LUMINA_READ_DIR, else as scroll
#   bash Scripts/probe.sh v3                     the scenarios still written for the v3 page (see V3 below): expected to fail
#   bash Scripts/probe.sh all [--require-all]    everything v5; --require-all turns a SKIP into a failure
#
# Build fixtures once: LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Tests/probe/forge_fixtures.sh
# Evidence goes to ~/LuminaEvidence/probe/<stamp> (not /tmp: it gets swept).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source Scripts/page_files.sh; export PAGE

suite="${1:-all}"; shift || true
record=0; extra=()
for a in "$@"; do [[ $a == --record ]] && record=1 || extra+=("$a"); done

swift build -c release --package-path Tools/LuminaProbe >/dev/null || { echo "probe build failed" >&2; exit 2; }
PROBE="Tools/LuminaProbe/.build/release/lumina-probe"
OUT="${LUMINA_PROBE_OUT:-$HOME/LuminaEvidence/probe/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
S=Tests/probe/scenarios
export LUMINA_FIXTURE_ROOT="${LUMINA_FIXTURE_ROOT:-}"
# The probe is a SwiftPM tool with no bundle: the look rules come from the checkout (LookRules.bundled reads LUMINA_RULES).
export LUMINA_RULES="${LUMINA_RULES:-$ROOT/Lumina/Sets/Look/rules-v1.json}"
status=0

run() { "$PROBE" run "$@" --out "$OUT" ${extra[@]+"${extra[@]}"} || status=1; }
run_out() { local o=$1; shift; mkdir -p "$o"; "$PROBE" run "$@" --out "$o" ${extra[@]+"${extra[@]}"} || status=1; }

reference() {
  run "$S/screens-1920.json" "$S/screens-1440.json" "$S/smoke.json" "$S/keys-open-return.json" \
      "$S/screens-1920-app.json" "$S/screens-1440-app.json"
  local manifest=Tests/probe/reference/manifest.json now="$OUT/manifest.json"
  python3 - "$OUT" "$now" <<'EOF'
import hashlib, json, os, platform, subprocess, sys
out, dest = sys.argv[1], sys.argv[2]
files = {}
for suite in ("screens-1920", "screens-1440"):
    d = os.path.join(out, suite)
    for f in sorted(os.listdir(d)):
        if f.endswith(".png") or f.endswith(".state.json"):
            files[f"{suite}/{f}"] = hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest()
page = hashlib.sha256(open("design/handoff/lumina-cull/" + os.environ["PAGE"], "rb").read()).hexdigest()
osv = subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip()
json.dump({"page_sha256": page, "macos": osv, "arch": platform.machine(), "files": files}, open(dest, "w"), indent=1, sort_keys=True)
EOF
  if [[ $record == 1 ]]; then
    mkdir -p "$(dirname "$manifest")"; cp "$now" "$manifest"; echo "reference recorded → $manifest"
  elif [[ -f $manifest ]]; then
    python3 - "$manifest" "$now" "$OUT" "$PROBE" <<'EOF' || status=1
import json, subprocess, sys
ref, now, out, probe = (json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4])
if ref["page_sha256"] != now["page_sha256"]: print("NOTE  page changed since the reference was recorded")
if ref["macos"] != now["macos"]: print(f"NOTE  reference recorded on macOS {ref['macos']}, now {now['macos']} (font rendering may differ)")
bad = [k for k in ref["files"] if ref["files"][k] != now["files"].get(k)]
missing = [k for k in ref["files"] if k not in now["files"]]
for k in bad: print(f"DIFF  {k}")
print(f"reference: {len(ref['files']) - len(bad)} / {len(ref['files'])} identical" + (f", {len(missing)} missing" if missing else ""))
# The shipped app (page + plumbing.js) must render exactly what the design renders.
import hashlib, os
app_bad, app_n = [], 0
for size in ("1440", "1920"):
    d = os.path.join(out, f"screens-{size}-app")
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith(".png") or f.endswith(".state.json"):
            app_n += 1
            if ref["files"].get(f"screens-{size}/{f}") != hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest():
                app_bad.append(f"screens-{size}-app/{f}")
for k in app_bad: print(f"APP≠DESIGN  {k}")
print(f"app vs design: {app_n - len(app_bad)} / {app_n} identical")
sys.exit(1 if bad or app_bad else 0)
EOF
  else
    echo "no reference manifest yet — run with --record"
  fi
}

# Scenarios still written for the v3 page (bare 1/2/3 steps, R/X keys, the Edit step, RAW/JPEG
# export to a picked folder). They need rewriting for v5 before they mean anything; see
# Tests/probe/EDGE-CASES.md. `probe.sh v3` runs them anyway.
V3=(app-export app-session app-xmp-lightroom app-xmp-both app-rename-mid-cull look-parity app-empty-start
    card-stress card-stress-app fault-card-pull-export fault-card-pull-read fault-disk-full fault-readonly-card fuzz-app-card)
v3files() { for n in "${V3[@]}"; do echo "$S/$n.json"; done; }

# A folder big enough to scroll. The fixtures hold 12 real frames: clone them (APFS, no extra space)
# 34 times and restamp every clone 20 s apart, so each is its own tile rather than one big stack.
scrolldir() {
  [[ -n ${LUMINA_SCROLL_DIR:-} ]] && return
  if [[ -n ${LUMINA_CARD_DIR:-} ]]; then export LUMINA_SCROLL_DIR="$LUMINA_CARD_DIR"; return; fi
  [[ -n $LUMINA_FIXTURE_ROOT && -d $LUMINA_FIXTURE_ROOT/src ]] || return 0      # unset: the scenarios SKIP
  local d="$LUMINA_FIXTURE_ROOT/scroll-408"
  if [[ ! -f $d/.done ]]; then
    local exif; exif="$(command -v exiftool || ls /opt/homebrew/bin/exiftool /usr/local/bin/exiftool 2>/dev/null | head -1)"
    [[ -x $exif ]] || { echo "scroll: exiftool not found (needed once to build $d)" >&2; return 0; }
    rm -rf "$d"; mkdir -p "$d"
    local src=("$LUMINA_FIXTURE_ROOT"/src/*.[aA][rR][wW]) args="$d/.args" i=0 t0 t
    t0=$(date -j -f "%Y-%m-%d %H:%M:%S" "2026-09-01 09:00:00" +%s)
    : > "$args"
    for rep in $(seq 1 34); do for f in "${src[@]}"; do
      local n; n=$(printf "DSC%05d.ARW" $((10001 + i)))
      cp -c "$f" "$d/$n" 2>/dev/null || cp "$f" "$d/$n"
      t=$(date -r $((t0 + i * 20)) "+%Y:%m:%d %H:%M:%S")
      printf -- "-overwrite_original\n-DateTimeOriginal=%s\n-CreateDate=%s\n%s\n-execute\n" "$t" "$t" "$d/$n" >> "$args"
      i=$((i + 1))
    done; done
    "$exif" -q -q -@ "$args" && rm -f "$args" && touch "$d/.done"
  fi
  export LUMINA_SCROLL_DIR="$d"
}

# A folder of real ARWs for the Edit canvas and RAW 9 suites: LUMINA_EDIT_DIR, else the scroll folder.
editdir() {
  [[ -n ${LUMINA_EDIT_DIR:-} ]] && return
  scrolldir
  [[ -n ${LUMINA_SCROLL_DIR:-} ]] && export LUMINA_EDIT_DIR="$LUMINA_SCROLL_DIR"
  return 0
}

case "$suite" in
  reference) reference ;;
  sync)      echo "use: bash Scripts/sets_sync_design.sh <handoff.zip>"; exit 2 ;;
  smoke)     run "$S/smoke.json" "$S/keys-open-return.json" "$S/selftest.json" "$S/app-plumbing-contract.json" "$S/app-smoke.json" ;;
  selftest)  run "$S/selftest.json" ;;
  fuzz)      run "$S"/fuzz-sample-*.json ;;
  edge)      run "$S"/edge-*.json ;;
  ingest)    LUMINA_PROBE_MODE=app run "$S"/edge-*.json ;;
  card)      run "$S/golden-card.json" "$S/card-clock.json" ;;
  app)       run "$S/app-plumbing-contract.json" "$S/app-smoke.json" ;;
  contract)  run "$S/app-plumbing-contract.json" ;;
  fault)     run "$S/fault-kill-mid-handoff.json" "$S/fault-native-dest.json" ;;   # native only: kill -9 mid-write, disk full mid-copy
  scroll)    scrolldir; run "$S/scroll-read.json" "$S/scroll-fast.json" "$S/scroll-fast-2560.json" ;;
  edit)      editdir; run "$S/edit-canvas.json"
             echo "— image fallback path (LUMINA_CANVAS=image) —"
             LUMINA_CANVAS=image run_out "$OUT/image-path" "$S/edit-canvas.json" ;;
  raw9)      editdir; run "$S/raw9.json" ;;
  readspeed) [[ -n ${LUMINA_READ_DIR:-} ]] || { scrolldir; export LUMINA_READ_DIR="${LUMINA_SCROLL_DIR:-}"; }
             run "$S/read-speed.json" ;;
  v3)        run $(v3files) ;;                  # scenario paths have no spaces
  all)       reference; run "$S/selftest.json" "$S"/fuzz-sample-*.json "$S"/edge-*.json "$S/app-plumbing-contract.json" "$S/app-smoke.json" \
               "$S/fault-kill-mid-handoff.json" "$S/fault-native-dest.json"
             LUMINA_PROBE_MODE=app run "$S"/edge-*.json ;;
  *)         sed -n '2,21p' "$0"; exit 2 ;;
esac
echo "evidence: $OUT"
exit $status
