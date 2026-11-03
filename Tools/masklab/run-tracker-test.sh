#!/usr/bin/env bash
# Every tracker on every clip that has a prompt, then the scores (Tools/masklab/README.md). Mac only.
#
#   bash Tools/masklab/run-tracker-test.sh
#
# Reads the clips (never writes next to them) and ~/LuminaEvidence/masklab/prompts.json; writes
# ~/LuminaEvidence/masklab/runs/<date-time>/<tracker>/<clip>/ (masks + timing.json), log.txt,
# report.json and report.txt, and points runs/latest at it. Scores against labels/<clip>/<frame>.png
# where they exist; a clip without labels still gets fps and flicker.
#
# Environment:
#   LUMINA_VIDEO_DIR      clips folder, its top level only (default /Volumes/T7: the seven yvid-a7siii-C00*.mp4)
#   MASKLAB_EVIDENCE      evidence folder (default ~/LuminaEvidence/masklab)
#   MASKLAB_TRACKERS      default "vision-box vision-instance"; add "skim" for the app's own track (SkimTracker,
#                         built from the app's files with swiftc; its timing.json also has the sure / shaky / lost strip)
#   MASKLAB_SAM2_MODEL    a SAM 2.1 Core ML folder: adds sam2-coreml (experimental); nothing is downloaded
#   MASKLAB_PROXY         decode long edge (720)
#   MASKLAB_FRAMES        frames per clip at most (default: each prompt's "frames", else the whole clip)
#   MASKLAB_SAVE_FRAMES   also write every Nth proxy frame under the first tracker's output, to label on
#   MASKLAB_LIMIT         wall-clock limit for the whole run in seconds (3600)
#   MASKLAB_BIN           use this masklab-track instead of building Tools/masklab/track
#   MASKLAB_PYTHON        a Python with numpy and Pillow for score.py (default: python3 if it has them, else
#                         ~/LuminaEvidence/venv-parity/bin/python3)
#
# The run goes through Scripts/test_guard.py: bounded, one at a time, and refused while
# ~/LuminaEvidence/.tests-off exists.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"

if [ "${1:-}" != "--guarded" ]; then
  exec python3 "$ROOT/Scripts/test_guard.py" run --name masklab --limit "${MASKLAB_LIMIT:-3600}" -- bash "$0" --guarded
fi

VIDEO_DIR="${LUMINA_VIDEO_DIR:-/Volumes/T7}"
EVID="${MASKLAB_EVIDENCE:-$HOME/LuminaEvidence/masklab}"
PROMPTS="$EVID/prompts.json"
TRACKERS="${MASKLAB_TRACKERS:-vision-box vision-instance}"
if [ -n "${MASKLAB_SAM2_MODEL:-}" ] && [[ " $TRACKERS " != *" sam2-coreml "* ]]; then TRACKERS="$TRACKERS sam2-coreml"; fi

[ -d "$VIDEO_DIR" ] || { echo "masklab: no clips folder $VIDEO_DIR (set LUMINA_VIDEO_DIR)" >&2; exit 3; }
[ -f "$PROMPTS" ] || { echo "masklab: no $PROMPTS; copy Tools/masklab/prompts.example.json there and give each clip a start frame and a box" >&2; exit 3; }

if [ -n "${MASKLAB_BIN:-}" ]; then
  BIN="$MASKLAB_BIN"     # a tool built elsewhere (or a stand-in when checking this script)
else
  swift build -c release --package-path "$HERE/track"
  BIN="$HERE/track/.build/release/masklab-track"
fi

# `skim`: the app's own track (SkimTracker, #308), built with swiftc from the app's files (Tools/masklab/skim).
SKIM_BIN=""
if [[ " $TRACKERS " == *" skim "* || " $TRACKERS " == *" skim-prompted "* ]]; then
  mkdir -p "$EVID/build"; SKIM_BIN="$EVID/build/masklab-skim"
  swiftc -O -swift-version 5 -o "$SKIM_BIN" "$ROOT/Lumina/Sets/Look/LookMasks.swift" "$ROOT/Lumina/Sets/Core/SetsMasks.swift" \
    "$ROOT/Lumina/Sets/Video/SkimFollow.swift" "$ROOT/Lumina/Sets/Core/SkimFollower.swift" "$ROOT/Lumina/Sets/Core/SkimTracker.swift" \
    "$ROOT/Lumina/Sets/Core/SkimPrompt.swift" "$HERE/skim/Stub.swift" "$HERE/skim/main.swift"
fi

RUN="$EVID/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
LOG="$RUN/log.txt"

# One line per clip at the folder's top level: path, stem, start, --box|--point, value, frames
# (or SKIP and the stem when prompts.json has no entry). Python reads the JSON and lists the folder
# once, so .mp4 and .MP4 on a case-insensitive disk are not counted twice.
JOBS="$(python3 - "$VIDEO_DIR" "$PROMPTS" "${MASKLAB_FRAMES:-}" <<'PY'
import json, os, sys
folder, prompts_path, frames_env = sys.argv[1:4]
prompts = {k: v for k, v in json.load(open(prompts_path)).items() if not k.startswith("_")}
names = sorted(n for n in os.listdir(folder)
               if not n.startswith(".") and os.path.splitext(n)[1].lower() in (".mp4", ".mov"))
for n in names:
    stem = os.path.splitext(n)[0]
    p = prompts.get(stem)
    if p is None:
        print(f"SKIP\t{stem}")
        continue
    if "box" in p:
        flag, value = "--box", ",".join(str(v) for v in p["box"])
    elif "point" in p:
        flag, value = "--point", ",".join(str(v) for v in p["point"])
    else:
        sys.exit(f"masklab: prompts.json entry {stem} has neither box nor point")
    frames = frames_env or str(p.get("frames", ""))
    print("\t".join([os.path.join(folder, n), stem, str(p.get("start", 0)), flag, value, frames or "-"]))
for stem in sorted(set(prompts) - {os.path.splitext(n)[0] for n in names}):
    print(f"masklab: prompts.json names {stem}, which is not in {folder}", file=sys.stderr)
PY
)"

failed=0
first=1
for tracker in $TRACKERS; do
  while IFS=$'\t' read -r path stem start flag value frames; do
    [ -n "$path" ] || continue
    if [ "$path" = SKIP ]; then
      [ "$first" = 1 ] && echo "masklab: $stem has no prompt, skipped" | tee -a "$LOG"
      continue
    fi
    args=("$path" --start "$start" "$flag" "$value" --tracker "$tracker" --out "$RUN/$tracker/$stem")
    [ "${MASKLAB_PROXY:-}" ] && args+=(--proxy "$MASKLAB_PROXY")
    [ "$frames" != "-" ] && args+=(--frames "$frames")
    [ "$tracker" = sam2-coreml ] && args+=(--model "${MASKLAB_SAM2_MODEL:-}")
    [ "$tracker" = vision-oracle ] && args+=(--labels "$EVID/labels/$stem")
    [ "$first" = 1 ] && [ "${MASKLAB_SAVE_FRAMES:-}" ] && args+=(--save-frames "$MASKLAB_SAVE_FRAMES")
    echo "+ masklab-track ${args[*]}" >>"$LOG"
    # A failed clip is reported and the run goes on to the next; nothing is retried.
    # skim-prompted: the start outlined by Vision's prompted segmenter on the box, and each frame's outline from it
    # with the followed box as its prompt (a shape outlined by clicks in the app; OUTLINING.md B2). macOS 27.
    tool="$BIN"; [ "$tracker" = skim ] && tool="$SKIM_BIN"
    [ "$tracker" = skim-prompted ] && { tool="$SKIM_BIN"; args+=(--prompted); }
    if ! "$tool" "${args[@]}" 2>&1 | tee -a "$LOG"; then
      echo "masklab: $tracker on $stem failed (see $LOG)" | tee -a "$LOG"; failed=$((failed + 1))
    fi
  done <<<"$JOBS"
  first=0
done

runs=()
for tracker in $TRACKERS; do [ -d "$RUN/$tracker" ] && runs+=("$RUN/$tracker"); done
if [ ${#runs[@]} -eq 0 ]; then echo "masklab: nothing ran" >&2; exit 1; fi
# score.py needs numpy and Pillow: MASKLAB_PYTHON, else python3 if it has them, else the parity venv.
PY="${MASKLAB_PYTHON:-}"
if [ -z "$PY" ]; then
  for c in python3 "$HOME/LuminaEvidence/venv-parity/bin/python3"; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import numpy, PIL' 2>/dev/null; then PY="$c"; break; fi
  done
fi
[ -n "$PY" ] || { echo "masklab: no Python with numpy and Pillow; set MASKLAB_PYTHON or pip install -r Tools/parity/requirements.txt" >&2; exit 1; }
"$PY" "$HERE/score.py" "${runs[@]}" --labels "$EVID/labels" --out "$RUN/report.json" | tee "$RUN/report.txt"
ln -sfn "$RUN" "$EVID/runs/latest"
echo "masklab: report in $RUN/report.txt ($failed failed)"
[ "$failed" -eq 0 ]
