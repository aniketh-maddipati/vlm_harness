# WP-5 (Edit controls): contract requests and seams

Nothing here blocks WP-5; each item says what WP-5 does meanwhile.

## 1. R-86 UI test expects more stored looks than the burst rule allows (rule and test disagree)
`LuminaUITests/Native/LoadTests.swift` `test_R86_edit300Photos_storageSmall` asserts
`looksCount > 250` after nudging 300 photos of `demo:1500` with all 1,500 kept. Kept burst frames
share one edit (README "State", `DecisionAndEditTests.test_burstFramesShareOneEdit`), so those 300
photos store **116** looks. The HTML suite this test ports only asks for `n > 0 && kb < 2048` and
prints "bursts share one". Headless: `WP5EditTests.test_R86_300EditedPhotos_under2MB`.
**Ask (WP-0 / test owner):** lower the threshold (`> 100`), or make `debug.state.looksCount` count
edited photos rather than stored looks. WP-5 did not touch the test.

## 2. Esc while a slider is dragged should not also run `editEscape()` (WP-6 / KeyRouter)
Esc during a drag cancels the drag (README "Slider row"). The key table sends Esc in Edit to
`.editEscape` (WP-6's `editEscape()`), which knows nothing about drags.
**Meanwhile:** `EditControls` watches `model.heldKeys` for "escape" and calls
`model.cancelSliderDrag()`. The drag is cancelled, but `editEscape()` still runs once (it may also
leave zoom or Before).
**Ask:** first line of `editEscape()`: `if cancelSliderDrag() { return }` (the function exists and
returns false when nothing is dragged).

## 3. White picker: the canvas calls `pickWhite(at:)` (WP-4)
`W` toggles `edit.pickingWhite`. While it is on, a click on the photo should call
`model.pickWhite(at: CGPoint)` with the click as fractions of the photo (0,0 top-left … 1,1
bottom-right). It sets temperature, clears tint, switches the picker off, one undo step.
The value is the prototype's stand-in (Auto's white balance, shifted by the click's height).
**Ask (backend adapter):** a way to sample the pixel, e.g. on `ImageProvider`:
`func neutral(for photo: Photo, at: CGPoint) async -> (kelvin: Double, tint: Double)?`.

## 4. Auto is a stand-in (`AutoLook.make(for:)`)
Exposure from a per-photo figure derived from the file name (the prototype's formula), temperature
5600 K, highlights −22, shadows +18. **Ask (backend adapter):** a measured Auto, e.g.
`ImageProvider.autoLook(for: Photo) async -> Look`; `auto()` would apply it the same way.

## 5. `lumina-snap`: no way to open a section or hover a slider
Only keys drive it, and no key changes the section. For the WP-5 snapshots a local, uncommitted
patch added `--section`, `--axis`, `--hover`, `--type`, `--drag`, `--warn`.
**Ask (WP-0):** add `--section <light|curve|colour|effects>` (calls `model.setSection`) and
`--hover <key>` (sets `model.edit.hoverKey`).

## 6. Seams other WPs should know
- **Section changes go through `model.setSection(_:)` / `model.setColourAxis(_:)`**, not by
  assigning `edit.section`: they also move the setting `,` `.` `[` `]` act on into the section.
  (`targetKey` is safe either way: it never returns a setting that isn't on screen.)
- **The "Hide ▾ / Show ▴" toggle is in the controls header** (as in the prototype) when the window
  is under 860 wide; it flips `edit.controlsCollapsed`, and the column then shows only its header
  and bottom bar. WP-4 should not hide `EditControls` itself when collapsed, or add a second toggle.
- **`EditControls` fills the frame it is given** and adapts to its width (tools in one row from
  440pt, sliders in two columns from 536pt under the photo). Beside the photo it takes the full
  height; under the photo it takes its natural height, so WP-4 caps it (prototype: 46 % / 58 % of
  the window height).
- **`edit.hint` lives in the column** (the prototype has it in a window-wide footer that the README
  dropped). Its space is reserved so rows don't move under the pointer.
- **Coalescing in `EditStore`**: `set(…, coalesce: true)` folds into the step of the drag in
  progress. Callers outside WP-5 that drag (canvas ⌥-drag on a colour, vignette handles) should
  bracket the gesture with `edits.beginCoalescing()` / `endCoalescing()`, or use
  `model.sliderDragBegan(key)` / `sliderDragMoved(by:)` / `sliderDragEnded()`.
- **Two-finger swipe direction**: the thumb follows the fingers (swipe right = more). The prototype
  moves the other way (it reuses the page-scroll sign); say so if parity wants that.
- **Nudge size**: one step per `,` `.` (README table), 2 % for Temperature (traces). The prototype
  nudges two steps for everything except Exposure.
