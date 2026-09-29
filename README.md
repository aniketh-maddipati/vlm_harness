# Lumina

A fast culling app for Sony α shooters: open a card or folder of ARWs, cull by time rows and
bursts with the keyboard, optionally touch up, then hand off to Lightroom / Capture One (XMP) or
export RAW + JPEG. It reads in place and never writes to the card.

The UI is designed in Claude Design and ships unchanged inside a native macOS window. See
`AGENTS.md` for how that works and how to sync a new design.

## Run it

Requires Xcode 16.4+ on Apple silicon, macOS 14+.

```bash
open Lumina.xcodeproj      # scheme "Lumina", My Mac, ⌘R
```

## Update the design

1. Paste `design/handoff/DESIGN-ASKS.md` (or your own prompt) into Claude Design.
2. Download the handoff zip.
3. Run `bash Scripts/sets_sync_design.sh "<zip>"`, review, then commit.
