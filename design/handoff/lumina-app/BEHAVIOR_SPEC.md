# Behavior spec: rules the app must obey

Every rule has an ID. The tests in `XCTest/` reference these IDs in their names and failure messages. If a rule changes, change the test in the same PR.

## Keys and state (R-0x)
- **R-01** ⏎ on Open starts culling once. Repeats and presses within 450ms after a step change do nothing. Six fast ⏎ presses end on Cull, never on Save.
- **R-02** Step switching is idempotent and last-press-wins. 40 random ⌘1–4 presses 15ms apart end on the step of the last press.
- **R-03** ⏎ held on the last photo in Edit lands on Save and **does not save**.
- **R-04** Keep and undo are exact. 10 R presses (with held repeats ignored) give 10 keeps; 10 × ⌘Z gives 0; 3 × ⇧⌘Z gives 3.
- **R-05** Simultaneous R and X never produce a half-state: every decision is true, false or unset.
- **R-06** A variation applied after the photo has switched never lands on the new photo. The apply is cancelled if the photo changed within its 120ms window.
- **R-07** An edit made within 50ms of leaving Edit is saved (flush on step change).
- **R-08** Out in Edit, then ⌘Z in Cull, does not bring the photo back. Cull's undo history is reset when Edit changed decisions.

## Controls conflicts (R-2x)
- **R-20** R in Edit never rotates or changes the photo; it shows the explanation from KEYMAP.md.
- **R-21** T does nothing anywhere.
- **R-22** Typing in a number field never triggers shortcuts (R, X, Z, V, arrows, 0).
- **R-23** With Help open, X, R, arrows and nudges do nothing. Esc closes only Help.
- **R-24** Crop and Variations own the keyboard (see the KEYMAP layers). Variations closes when the window loses focus.
- **R-25** Esc backs out one layer at a time. From any mode, at most 3 Esc presses return to normal: zoom 1, no overlay, controls visible.
- **R-26** Help text and tooltips match the real keys. No mention of T, and R isn't listed as rotate outside Crop.
- **R-27** ⌘Z in Edit undoes the edit, never a Cull decision.
- **R-28** X means Out in both Cull and Edit, and ⌘Z restores the previous decision in each.

## Destructive or irreversible actions (R-3x)
- **R-31** Start over needs two clicks within 4 seconds. The first only changes its label.
- **R-32** Triple-clicking Save (plus 2 × ⌘S) produces exactly one save.
- **R-33** ⏎ on Save is ignored within 1.5s of arriving and within 1s of the previous ⏎. A deliberate ⏎ after a pause saves.
- **R-34** Save with an unchanged signature does nothing ("Already saved. Nothing changed since."). Changing the format or edits enables "Save again".
- **R-35** ⌘S in Edit goes to Save without saving; ⌘S on Save saves.
- **R-36** With everything Out, Save shows "Nothing to save yet" and is disabled; ⏎ and ⌘S do nothing.

## Import (R-1x)
- **R-10** Only files that actually decode as images are added. The file extension is a hint, not proof: a PNG named `.jpg` is accepted, and a "JPEG" that won't decode is rejected as damaged.
- **R-11** Silently ignored: `.DS_Store`, `._*`, `Thumbs.db`, `desktop.ini`, hidden files, and sidecars (`.xmp .thm .lrv .aae .dop .pp3 .on1 .cos .lrcat`).
- **R-12** Skipped with a counted reason in one message: RAW (in the browser prototype only; **the native app must decode RAW**), video, archive ("unzip it first"), damaged, empty (0 bytes), "not a photo", HEIC the platform can't decode, and "already in this shoot".
- **R-13** If nothing was added, stay on Open with an error-coloured message ending "Lumina opens JPEG, PNG, WebP, HEIC and AVIF." (the native app should add RAW to that list). An empty folder says "That folder is empty."
- **R-14** Duplicates (same relative path, size and modified time) are never added twice, within a batch or across imports.
- **R-15** Folders are walked recursively. Scenes come from subfolders and from gaps of more than 30 minutes in capture time. Bursts are frames ≤2s apart with the same aspect ratio, at most 8 per burst.
- **R-16** Capture time comes from EXIF DateTimeOriginal, falling back to file modification time. Camera, lens, focal length, aperture, shutter and ISO come from EXIF too; missing fields are left out of every line.
- **R-17** A drop on any step adds the photos and stays on that step. A drop of non-files (text) does nothing. The overlay never sticks after the drop.
- **R-18** A batch dropped while another is still being checked is queued and added; nothing is lost.
- **R-19** After a relaunch, the previous folder is offered again; reopening restores its decisions. Native: use a security-scoped bookmark and reopen automatically.
- **R-1A** Copy progress only ever increases, and survives a relaunch, resuming where it stopped (saved at least every 15 photos).
- **R-1B** Odd names import and never push the layout sideways: emoji, 220 characters, right-to-left text, leading and trailing spaces, "(1)", no extension.
- **R-1C** Odd shapes keep their true aspect ratio in Cull and Edit: 1×1, 40:1, 1:40, 2×3000.
- **R-1D** EXIF orientation is applied: a photo tagged rotate-90° shows upright and is never squashed.

## Edit display (R-4x)
- **R-41** The photo is never stretched. The displayed aspect ratio equals the source (after crop and rotation) within 5%.
- **R-42** The blurred low-res image shows at once, and the sharp one fades in when decoded. Neighbours are preloaded.
- **R-43** Resizing while zoomed keeps the photo visible (at least 40×40pt) and the zoom within range.
- **R-44** A failed load shows "Couldn’t open {file}" with Retry, never a blank frame.
- **R-45** With no keepers, show the empty state and Go to Cull.
- **R-46** Pinch storms keep zoom within ¼× of Fit and 2× of 1:1.

## Layout (R-5x)
- **R-50** At every window size from 320×480 to 3000×600, including 375×812, 600×300, 1024×1366, 1920×1080, 2560×1440 and 400×1600, on all four steps:
  - no horizontal scroll;
  - tabs fully visible;
  - the step's main action reachable;
  - the Edit photo at least 40×40.
- **R-51** No control text is clipped at 1440×900, 1100×760, 860×600, 700×560 or 480×800.
- **R-52** Every button, tab, radio, slider and checkbox has a label (text, accessibility label or help).
- **R-53** No screen shows "undefined", "NaN", "{{", "[object", "nil" or "Optional(".
- **R-54 (nothing small)** At every size: every text element is ≥ 11pt × S. Every button is ≥ 28pt high × S (tabs and chips ≥ 24); primary actions are ≥ 34. Slider rows are ≥ 28. S is the UI scale from LAYOUT_SIZING.md §3. At 2560×1440, chrome must measure 1.25× its 1440×900 size (±1pt).
- **R-55 (Edit fills)** The Edit photo reaches the canvas edge on at least one axis (gap ≤ 12pt on each side of that axis). The canvas takes ≥ 70% of the window area at 1440×900 and above, and the whole window in focus mode.
  *Lumina ruling 2026-10-02:* relaxed to ≥ 52% to follow the v19 prototype's Edit layout (about 57% at 1440×900, 54% at 1920×1080) with the larger native UI scale; the test checks 52%.
- **R-56 (Cull fills)** In every scene, every row except the last fills the grid width to within 2pt. Tile height is ≥ 0.10 × grid height (up to 200). No portrait tile wastes more than 40% of its box.
- **R-57 (no dead bands)** On Open and Save, empty space above the content is ≤ 72pt and never larger than the empty space below it. The content column is ≥ 46% of the window width up to 760×S. No top toolbar and no title gap: the top bar starts within 0–28pt of the window top (titlebar overlap).
- **R-58 (preview fills)** The Cull preview photo (from 900 wide) touches the preview column on one axis (gap ≤ 4pt), and the column is ≥ 300pt and ≤ 50% of the width.
- **R-59 (scale is consistent)** Resizing the window between 1440×900 and 2560×1440 changes chrome sizes smoothly, by the formula, with no jumps over 2pt between neighbouring sizes 20pt apart.

## Motion (R-6x)
- **R-60** Step changes fade (no slide), and every overlay or panel fades in 120ms.
- **R-61** After things settle, the main photo is fully opaque and nothing animates in a loop except loading spinners.

## Persistence and failure (R-7x)
- **R-70** Relaunching on any step returns to that step with every decision and edit.
- **R-71** When storage is full, Edit shows "Couldn’t save on this computer. Keep this window open." and keeps working in memory.
- **R-72** With the same shoot open in two windows, an edit in one shows "Changed in another window" in the other.
- **R-73** Unhandled errors: zero, across every suite.

## Load and performance (R-8x)
Times are measured on an M1 MacBook Air or better, release build. "95th" means 95th percentile.

| ID | Rule | 117 photos | 5,000 photos |
|---|---|---|---|
| **R-80** | Key handling in Cull while copying (95th) | < 100ms | < 100ms |
| **R-81** | Photo switch in Edit (95th) | < 50ms | < 60ms |
| **R-82** | Marking every photo at full speed gives exact counts | ✓ | ✓ in < 60s |
| **R-83** | Save (95th) | < 500ms | < 500ms, excluding file I/O, which runs in the background |
| **R-84** | Relaunch to interactive | < 4s | < 4s |
| **R-85** | Import of a 400-photo folder | Exact counts; keys < 150ms (95th) while checking | |
| **R-86** | Stored edits for 300 photos | < 2 MB | < 2 MB |

## Soak (R-9x)
- **R-90** After N rounds of chaos (re-importing the same files, 80 random clicks, 80 random keys, 15 resizes, a lap of the steps), the app still answers and the tabs still work.
- **R-91** On-screen element count, measured on the same screen, stays under 1.6× from early to late rounds.
- **R-92** Memory, measured after 2.5s idle on the same screen, stays under 1.5× from early to late rounds (median of the first ⅓ against the last ⅓). Bounded caches such as the 200-step undo history are allowed to fill.
- **R-93** A big import still completes with exact counts after the soak.
