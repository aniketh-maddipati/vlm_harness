# Live Edit — Clean Mac Manual Checklist

## Prep

1. macOS 14+, Xcode 15+, `brew install exiftool`
2. Checkout `cursor/raw-perf-lr-handoff`
3. Confirm RAW folder exists, e.g. `~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS` (Sony ARW)

## Builds

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Release build
```

## Harness

```bash
LUMINA_DEVELOP_RAW_DIR=~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS \
  /path/to/Lumina.app/Contents/MacOS/Lumina --raw-harness artifacts/live-edit-v1
```

Expect `failures: 0`, `scrubDrain.convergedOnLatest: true`, `scrubDrain.atLeast20Frames: true`, all `controlPixelDiffs.*.pass: true`.

## Isolated live editor

```bash
LUMINA_DEVELOP_RAW_DIR=~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS \
  open -n /path/to/Debug/Lumina.app --args --live-editor
```

Or run the binary with `--live-editor` from Terminal (cwd = repo for log file).

Checklist:

- [ ] Real ARW fills the Metal surface (not a gray/blank flash)
- [ ] Drag **Exposure** continuously — image brightens/darkens under the pointer with no wait for mouse-up
- [ ] Drag **Warmth** continuously — white balance shifts live
- [ ] Drag **Highlights** and **Shadows** continuously
- [ ] Before/After toggles without blank frame
- [ ] Status line shows `rev N→N` converging; `metalView` / session prepare counts stay at 1 while scrubbing
- [ ] Switch photos in the list and return — committed recipe restores; no stale other-photo texture
- [ ] `artifacts/live-edit-v1/live-edit-path.log` shows slider → render start → finish → publication accepted → MTKView draw

## Workbench

1. Launch Lumina normally, open a shoot with matched ARWs
2. Select a set photo, press **T** (or ⌘-double-click) to open Treatment
3. Confirm layout: filmstrip | one focused Metal photo | one control stack (no carousel, no per-row sliders)
4. Repeat Exposure / Warmth / Highlights / Shadows continuous drags
5. Arrow or click filmstrip to another photo — prior image stays until new preview; controls show that photo’s recipe
6. Return to the first photo — committed offsets restore

## Pass / fail

**Pass** only if a real ARW visibly and continuously responds while dragging, with no release-to-apply, blank flash, stale frame, or editor/Metal recreation mid-scrub.

**Fail** if any of the stop conditions in the phase brief still hold — do not claim completion from harness alone.
