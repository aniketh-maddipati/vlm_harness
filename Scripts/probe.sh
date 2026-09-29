#!/usr/bin/env bash
# Lumina probe suites — drive the page in WKWebView and try to break it.
#
#   bash Scripts/probe.sh reference [--record]   21 screens × 2 sizes + state dumps, byte-compared to
#                                                Tests/probe/reference/manifest.json (--record rewrites it)
#   bash Scripts/probe.sh fuzz                   seeded key/mouse storms on the sample shoot
#   bash Scripts/probe.sh edge                   camera-data edge cases   (needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh card                   721-photo stress + scroll pacing (needs LUMINA_CARD_DIR)
#   bash Scripts/probe.sh fault                  card pulled mid-read / mid-export, disk full, locked card (disk images)
#   bash Scripts/probe.sh contract               plumbing.js still fits the page (run by sets_sync_design.sh)
#   bash Scripts/probe.sh app                    the app's own bridge: exports, refusals, .lumina-bak, sessions, ΔE
#                                                (needs LUMINA_FIXTURE_ROOT)
#   bash Scripts/probe.sh all [--require-all]    everything; --require-all turns a SKIP into a failure
#
# Build fixtures once: LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Tests/probe/forge_fixtures.sh
# Evidence goes to ~/LuminaEvidence/probe/<stamp> (not /tmp: it gets swept).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

suite="${1:-all}"; shift || true
record=0; extra=()
for a in "$@"; do [[ $a == --record ]] && record=1 || extra+=("$a"); done

swift build -c release --package-path Tools/LuminaProbe >/dev/null || { echo "probe build failed" >&2; exit 2; }
PROBE="Tools/LuminaProbe/.build/release/lumina-probe"
OUT="${LUMINA_PROBE_OUT:-$HOME/LuminaEvidence/probe/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
S=Tests/probe/scenarios
export LUMINA_FIXTURE_ROOT="${LUMINA_FIXTURE_ROOT:-}"
status=0

run() { "$PROBE" run "$@" --out "$OUT" ${extra[@]+"${extra[@]}"} || status=1; }

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
page = hashlib.sha256(open("design/handoff/lumina-cull/Lumina Sets v3.dc.html", "rb").read()).hexdigest()
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

case "$suite" in
  reference) reference ;;
  sync)      echo "use: bash Scripts/sets_sync_design.sh <handoff.zip>"; exit 2 ;;
  fuzz)      run "$S"/fuzz-sample-*.json ;;
  edge)      run "$S"/edge-*.json ;;
  card)      run "$S/card-stress.json" "$S/golden-card.json" ;;
  app)       run "$S/app-plumbing-contract.json" "$S/app-export.json" "$S/app-session.json" "$S/look-parity.json" ;;
  contract)  run "$S/app-plumbing-contract.json" ;;
  fault)     run "$S"/fault-*.json ;;           # disk images: card pulled mid-read / mid-export, disk full, locked card
  empty)     run "$S/app-empty-start.json" ;;     # acceptance test for DESIGN-ASKS #2; fails until v7
  all)       reference; run "$S"/fuzz-sample-*.json "$S"/edge-*.json "$S/app-plumbing-contract.json" "$S/app-export.json" "$S/app-session.json" "$S/look-parity.json" "$S"/fault-*.json "$S/card-stress.json" ;;
  *)         sed -n '2,13p' "$0"; exit 2 ;;
esac
echo "evidence: $OUT"
exit $status
