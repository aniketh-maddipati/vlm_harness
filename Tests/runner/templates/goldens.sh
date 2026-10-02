#!/bin/bash
# about: golden parity headless: every capture-goldens.mjs state rendered offscreen with lumina-snap and diffed with ~/LuminaEvidence/native-ui/goldens (no window, no keys). Args: [WxH, default 1100x760] [states, default all]. Gated at 1100x760 and 480x800; 1440x900 informational (native S > 1); Cull and 2560x1440 by eye.
# limit: 300
# Images: $RUN/goldens/<size>/<state>.png (native) and <state>.cmp.png (golden | native | diff).
# Another goldens folder: LUMINA_GOLDENS=/path/to/goldens (laid out <size>/<state>.png + manifest.json).
cd "$ROOT/LuminaKit" || exit 2
SIZE="${1:-1100x760}"; STATES="${2:-all}"
GOLDENS="${LUMINA_GOLDENS:-${LUMINA_TESTDATA:-$HOME/LuminaEvidence/native-ui}/goldens}"
case "$SIZE" in
  1100x760|480x800) ;;
  1440x900) echo "note: 1440x900 is informational: the native UI is S 1.125 there, the goldens S 1 (AGENTS.md, ruled 2026-10-02)" ;;
  2560x1440) echo "note: 2560x1440 is compared by eye (LAYOUT_SIZING): look at the .cmp.png images" ;;
esac
swift build --product lumina-snap || exit 1
BIN="$(swift build --show-bin-path)/lumina-snap"
"$BIN" --golden "$STATES" --size "$SIZE" --goldens "$GOLDENS" --out-dir "$RUN/goldens/$SIZE"
