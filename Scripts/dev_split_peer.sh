#!/usr/bin/env bash
# Park Cursor on the leading half of the main display.
# LuminaPlayground takes the trailing half when launched with --dev-split.
# Geometry matches DevSplitPlacement.leadingFrame (AppKit points, bottom-left).
# System Events uses a top-left origin, so Y is flipped against the primary screen.
# Always exits 0 — a missing permission must not cancel an Xcode run.
set +e

geometry="$(swift -e '
import AppKit
guard let screen = NSScreen.main else { exit(0) }
let visible = screen.visibleFrame
let width = (visible.width / 2).rounded(.down)
let frame = CGRect(x: visible.minX, y: visible.minY, width: width, height: visible.height)
let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? screen
let seY = primary.frame.maxY - frame.maxY
print("\(Int(frame.minX.rounded())) \(Int(seY.rounded())) \(Int(frame.width.rounded())) \(Int(frame.height.rounded()))")
' 2>/dev/null)"

read -r X Y W H <<<"$geometry"
if [[ -z "${W:-}" || -z "${H:-}" ]]; then
  exit 0
fi

osascript >/dev/null 2>&1 <<EOF &
tell application "System Events"
  if not (exists process "Cursor") then return
  tell process "Cursor"
    set candidate to missing value
    set best to 0
    repeat with w in windows
      try
        set sz to size of w
        set area to (item 1 of sz) * (item 2 of sz)
        if area > best then
          set best to area
          set candidate to w
        end if
      end try
    end repeat
    if candidate is missing value then return
    try
      set value of attribute "AXFullScreen" of candidate to false
    end try
    try
      set position of candidate to {${X}, ${Y}}
      set size of candidate to {${W}, ${H}}
    end try
    set frontmost to true
  end tell
end tell
EOF
child=$!
# A first-run Automation prompt must not stall the Xcode launch.
( sleep 4; kill "$child" 2>/dev/null ) &
waiter=$!
wait "$child" 2>/dev/null
kill "$waiter" 2>/dev/null
exit 0
