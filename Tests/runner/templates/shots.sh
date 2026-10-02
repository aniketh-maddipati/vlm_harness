#!/bin/bash
# about: screenshots of the native app's four steps, offscreen (no window, no keys, no sound). Args: [WxH] (default 1440x900), rendered at 2x. Photos: LUMINA_DEMO_PHOTOS=<folder> (the demo card's pictures), else generated ones.
# limit: 240
cd "$ROOT/LuminaKit" || exit 2
SIZE="${1:-1440x900}"
swift build --product lumina-snap || exit 1
BIN="$(swift build --product lumina-snap --show-bin-path)/lumina-snap"
OUT="$RUN/shots"; mkdir -p "$OUT"
shot() { # name keys
  "$BIN" --out "$OUT/$1.png" --size "$SIZE" --scale 2 --settle 1.0 ${2:+--keys "$2"} && echo "shot: $OUT/$1.png" || echo "ERR $1"
}
COPY="return,wait:2500"
shot 1-open ""
shot 2-cull "$COPY,r,right,r,right,x,right,right"
shot 3-edit "$COPY,r,right,r,right,r,right,r,cmd+3,wait:800,.,.,wait:400"
shot 4-save "$COPY,r,right,r,right,x,right,r,cmd+4,wait:500"
ls "$OUT"
