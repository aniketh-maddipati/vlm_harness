#!/usr/bin/env bash
# Caches the demo card's pictures (picsum.photos, the ones the prototype shows) for the native
# demo card and the golden comparison. Outside the repo; the app itself never fetches anything.
#   bash Scripts/fetch_demo_photos.sh [dir]      default ~/LuminaEvidence/native-ui/demo-photos
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; D="${1:-$HOME/LuminaEvidence/native-ui/demo-photos}"; mkdir -p "$D"
python3 - "$ROOT/design/handoff/lumina-app/parity/demo-shoot-117.json" <<'PY' | (cd "$D" && xargs -P 6 -n 2 sh -c '[ -s "$1" ] || curl -sfL --retry 3 --max-time 60 -o "$1" "$0"')
import json, re, sys
M = 2000
for p in json.load(open(sys.argv[1]))["photos"]:
    seed = re.search(r"lumina(\d+)", p["image"]).group(1); a = p["aspect"]
    w, h = (M, round(M / a)) if a >= 1 else (round(M * a), M)
    print(f"https://picsum.photos/seed/lumina{seed}/{w}/{h}{'?grayscale' if p['bw'] else ''} seed{seed}_{round(a * 1000)}{'_bw' if p['bw'] else ''}.jpg")
PY
echo "$(ls "$D" | wc -l | tr -d ' ') demo photos in $D"
