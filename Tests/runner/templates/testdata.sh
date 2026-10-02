#!/bin/bash
# about: fetch the test data this Mac lacks (outside the repo). Arg: demo | goldens | all (default all). demo = the demo card's picsum photos; goldens = the prototype screenshots (headless Chromium, no window).
# limit: 480
# Test data only: picsum / Unsplash pictures are never bundled into the app (README › Assets).
cd "$ROOT" || exit 2
WHAT="${1:-all}"
# Where the data goes: LUMINA_TESTDATA, else ~/LuminaEvidence/native-ui. A link to a drive that
# isn't mounted is refused, never written through or replaced.
EV="${LUMINA_TESTDATA:-$HOME/LuminaEvidence/native-ui}"
if [ -L "$EV" ] && [ ! -e "$EV" ]; then
  echo "$EV links to $(readlink "$EV"), which isn't there (drive unplugged?). Plug it in, or set LUMINA_TESTDATA=<local folder>."; exit 2
fi
if [ "$WHAT" = demo ] || [ "$WHAT" = all ]; then
  bash Scripts/fetch_demo_photos.sh "$EV/demo-photos" || exit 1
fi
if [ "$WHAT" = goldens ] || [ "$WHAT" = all ]; then
  if [ -f "$EV/goldens/manifest.json" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "goldens already in $EV/goldens (FORCE=1 to redo)"
  else
    # The capture script writes ../goldens next to itself; work on a copy so the repo stays clean.
    W="$RUN/capture"; mkdir -p "$W/capture"
    cp design/handoff/lumina-app/parity/capture/*.mjs design/handoff/lumina-app/parity/capture/package.json "$W/capture/"
    cd "$W/capture" || exit 2
    npm i --silent --no-audit --no-fund || exit 1
    PROTO="$ROOT/design/handoff/lumina-app/prototypes" node capture-goldens.mjs || exit 1
    # Never deletes: an old goldens folder is set aside next to it.
    mkdir -p "$EV" || exit 1
    [ -e "$EV/goldens" ] && mv "$EV/goldens" "$EV/goldens.old-$(date +%Y%m%d-%H%M%S)"
    mv "$W/goldens" "$EV/goldens" && echo "goldens → $EV/goldens"
  fi
fi
