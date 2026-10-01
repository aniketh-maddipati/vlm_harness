# Handoff: Lumina — Open · Cull · Edit · Save

## Overview
Lumina is a macOS photo workflow for people who are new to editing. Four steps, always in this order, always reachable: **Open** (copy a card or folder in), **Cull** (keep or reject, fast, by keyboard), **Edit** (optional; light, colour, curve, effects, crop), **Save** (Lightroom XMP, folder of RAWs, or JPEGs). The design goal is that a first-timer can't get lost, can't lose work, and can't trigger something they didn't see coming.

## About the design files
Everything in `prototypes/` is a **design reference built in HTML**: working prototypes that show the intended look and behaviour. They are not production code. Rebuild them natively in the Lumina app's existing stack (SwiftUI/AppKit is assumed below), using its own patterns. When the prototype and this README disagree, **this README wins**; it records decisions made after the prototypes.

Open `prototypes/Lumina Workflow.dc.html` in Chrome or Safari to click through the whole app. Add `?shoot=unsplash-1000` to the address to load 1,000 real photos.

## Fidelity
**High fidelity.** Colours, type, spacing, motion and copy are final. Rebuild pixel-close. Use native controls wherever they match. Where they don't (the four-step tab bar, the sliders, the variations grid), build custom views to these specs.

## Package contents
| File | What it's for |
|---|---|
| `README.md` | Screens, components, tokens, copy, motion |
| `LAYOUT_SIZING.md` | **Read before building any view.** Units, UI scale for big screens, fill rules per screen, minimum sizes. This overrides fixed sizes in the prototype. |
| `KEYMAP.md` | Every key, mouse and trackpad gesture, and which layer owns it |
| `BEHAVIOR_SPEC.md` | Numbered rules (R-xx) the app must obey. Every test points at one. |
| `ACCESSIBILITY_CONTRACT.md` | Accessibility identifiers and test hooks the XCTests rely on. **Build these in from day one.** |
| `TEST_PLAN.md` | The 96 XCTests, how they map to the HTML suites, how to run them, release gates |
| `WORKSTREAMS.md` | How to split the build across parallel agents/engineers, with file ownership, dependencies and kickoff prompts |
| `XCTest/` | The test suite: UI tests, unit tests, fixtures, helpers |
| `prototypes/` | HTML references and the HTML test harnesses that produced the results these tests mirror |

---

## Global shell (all four steps)

**Window:** minimum 320×420. Everything must reflow down to 320 wide (see R-50).

**Top bar:** height 38 if the window is under 760 tall, 42 under 900, otherwise 48. Padding 0 / 20 (10 when the window is under 700 wide). Background `#262523`, 1px bottom hairline `rgba(239,236,230,0.08)`. Contents, left to right:
- **Wordmark** "Lumina": Iowan Old Style (fall back to Palatino, then Georgia), 21pt, `#EFECE6`. Hidden under 700 wide.
- **Step tabs** (centred), a four-segment control:
  - Track: padding 2, radius 7, fill `rgba(239,236,230,0.08)`, inset 0.5pt hairline `rgba(239,236,230,0.12)`.
  - Segment width: 88 (60 under 560 wide, 72 under 760). Height 24, 13pt.
  - Selected segment: a sliding thumb `#5B5854`, radius 5, shadow `0 0.5 1 rgba(0,0,0,0.4)`. It moves with a 160ms ease-out on transform. Selected label is 700 weight `#EFECE6`; others are 400 `#96918A`, `#EFECE6` on hover.
  - From 760 wide, each label is followed by its shortcut hint (⌘1…⌘4) in SF Mono 11pt `#96918A`.
  - Tooltips: Edit says "Optional · nothing changes unless you move a setting"; Save says "Available any time · ⌘4".
- **Shoot meta** (right, from 900 wide), 12pt:
  - Left part: "N keepers · S scenes" in `#B8B3AB`.
  - Right part: copy status, right-aligned in a fixed 118pt slot. While copying it reads "Copying 42/117" in gold `#FFD27A`; when done, "All 117 copied and checked" in `#96918A`.

**Step transitions:** fade only, 120–160ms ease-out. No slides (R-60).

**Reduced motion:** all durations become effectively zero.

---

## 1 · Open
**Purpose:** get photos in. A first-timer must succeed whatever they pick or drop.

**Layout:** a scrolling column, centred, max-width 600, padding 56 top/bottom and 24 sides, gap 28.

**Components:**
1. **Title** "Open a shoot": Iowan 28pt. Subtitle 13pt `#B8B3AB`, line-height 1.5: "Lumina reads the card and never writes to it. Copies go to ~/Pictures/Lumina and are checked before you see them."
2. **Card tile:** `#262523`, radius 12, padding 20, gap 14, 1pt inset hairline `rgba(239,236,230,0.08)`.
   - Name: "SD card · Untitled", 15pt 600 weight.
   - Details line, 13pt `#B8B3AB`: "{camera} · {N} photos · {S} scenes · {first}–{last}".
   - Primary button: height 36, padding 0/18, radius 9, fill `#EFECE6`, text `#1E1D1B` 13pt 600 weight, `#FFFFFF` on hover. Its label changes:
     - "Copy & start culling" before copying,
     - "Copying… start culling" during,
     - "Continue culling" after.
     - It always ends with a "⏎" hint in SF Mono 11.5 at 60% opacity.
   - While copying, a 3pt progress bar sits under it: track `rgba(239,236,230,0.1)`, fill gold `#FFD27A`, 80ms linear.
3. **Import row** (wraps), gap 8:
   - "Open folder…" with a ⌘O hint, and "Choose photos…". Secondary buttons: height 32, padding 0/14, radius 8, fill `rgba(239,236,230,0.08)`, `0.16` on hover, 13pt.
   - Hint after them: "or drop photos or a folder anywhere", 12.5pt `#96918A`.
4. **Import progress** (while files are being checked): "Checking 24 of 400 files…" 12.5pt gold, plus a 3pt gold bar.
5. **Import message** (after an import; announced to VoiceOver as status): 12.5pt, line-height 1.5, wraps and breaks long words. Normal results are `#B8B3AB`; "nothing added" results are `#F0A39E`. The exact wording is in BEHAVIOR_SPEC R-10…R-19.
6. **Recent** (only once something has been opened): label "Recent" 12pt `#96918A`, then a resume row.
   - Row: padding 12/14, radius 9, fill `rgba(239,236,230,0.04)`, `0.09` on hover. Title "Today · {name}" 13.5pt, truncates. Subline "{N} photos · {d} decided · {e} edited" 12pt `#96918A`.
   - Under it, "Start over" as a 12pt text button, `#96918A`, `#EFECE6` on hover. It takes two clicks: the first changes its label to "Click again to clear {n} decisions" for 4 seconds (R-31).
7. **Folder to reopen** (after a relaunch, if the last shoot was an imported folder): a row reading "Folder · {name}" with the subline "{N} photos · choose the folder again to see them. Your decisions are kept." and a "Choose folder" affordance. In the native app, store a **security-scoped bookmark** so this reopens without asking again.

**Drop overlay** (on every step): inset 10, radius 14, 2pt dashed border `rgba(255,210,122,0.7)`, fill `rgba(22,21,20,0.86)`, fades in over 120ms. Text: "Drop to add photos" 18pt 600 weight, then "Photos or whole folders. Anything that isn’t a photo is skipped." 13pt `#B8B3AB`.

---

## 2 · Cull
**Purpose:** decide Keep or Out on every photo, as fast as you can press R and X.

**Layout:** a grid. From 900 wide it's two columns, `minmax(0,1fr) minmax(300px,38%)`, with a preview on the right; narrower, it's one column. A footer sits below.

**Grid column:** scrolls; padding 16 / 20 / 24; scenes stacked with gap 20.
- **Scene header**, min-height 24, gap 12, 12.5pt:
  - "{hh:mm}" (or "{hh:mm} · {folder}" for imported shoots), 600 weight, truncates.
  - Then "{n} photos · {d} decided" in `#96918A`.
  - Right-aligned, "Keep {n} suggested": height 24, padding 0/10, radius 6, fill `rgba(239,236,230,0.08)`. Tooltip: "Keep the photos Lumina marked with a ring. Undecided photos only."
- **Tiles** wrap with gap 6.
  - Height 80 if the window is under 800 tall, otherwise 100.
  - Landscape width = height × min(aspect, 1.8), filled edge to edge (cover).
  - Portrait width = height × 1.5, photo shown whole (contain) inside a 1.5pt dotted border.
  - Radius 3, background `#161514`. Each image fades in over 120ms once loaded.
  - **Current tile:** outline 2pt with offset 2. Colour is `#EFECE6` in the prototype; check it in the build.
  - **Kept:** a 16pt gold circle with a ✓ (`#1E1D1B`, 10.5pt bold) at top-left 5,5. It pops in with the 200ms "pop" animation (scale 0.4 → 1.18 → 1).
  - **Out:** the tile dims and turns grey (filter `grayscale(1) brightness(0.7)`, 120ms).
  - **Suggested** (undecided only): a 10pt ring, 1.5pt gold, at 6,6.
  - **Burst member:** a 3pt bar along the bottom, `rgba(239,236,230,0.5)`.
- While copying, a line at the end of the grid: "Copying {n} of {N}. Photos appear here one by one…", 12.5pt `#96918A`.
- **Empty:** "Nothing open yet." plus an "Open a shoot" button.

**Preview column:** padding 16 / 20 / 16 / 4, gap 12.
- **Photo:** fills the column, shown whole, radius 3, `#161514`. Shown grey and dim when the photo is Out.
- **Line under it**, 12.5pt:
  - File name, 600 weight, truncates.
  - Camera details in `#96918A`: "{camera} · {hh:mm:ss} · {fl}mm f/{ap} {shutter} · ISO {iso}". Leave out any field that's missing, never show "undefined" or "—".
  - State on the right: "Kept", "Out" or "Undecided".
- **Buttons:** two equal ones, height 36, radius 9, 13pt 600 weight, with SF Mono key hints.
  - Keep (R): fill `#EFECE6` and text `#1E1D1B` when kept; otherwise `rgba(239,236,230,0.1)` with `#EFECE6` text.
  - Out (X): fill `rgba(239,236,230,0.28)` when out, otherwise 0.1.

**Footer:** min-height 56, padding 8/20, `#262523`, top hairline, wraps.
- "{d}/{N} decided" with a 150×3 progress bar.
- The key reminder (or the latest message), 12pt `#96918A`, single line, truncates: "R keep · X out · ← → photos · ↑ ↓ scenes · U next undecided · ⌘Z undo · ⇧⌘Z redo · ⌘3 Edit · ⌘4 Save".
- Two buttons: "Edit {n} keepers" (secondary, followed by "optional" in `#96918A`) and "Save {n} keepers →" (primary).

---

## 3 · Edit
**Purpose:** optional adjustments to kept photos. Safe to skip.

**Layout:** the top bar, then a grid of photo column and controls column.
- **Controls column width:** 20% of the window, never below 252 or above 340.
- **Under 860 wide:** the controls move below the photo (one column). A "Hide ▾ / Show ▴" toggle collapses them; they start collapsed when the window is under 640 tall.
- **Focus mode** (H) and "Large" hide the controls entirely.

**Photo column:**
- **Canvas:** `#161514`, radius 3, fills the space.
  - The photo is drawn in its true aspect ratio, never stretched. A crop changes the box, never the proportions (R-41).
  - **While loading:** a small blurred version (6pt blur) shows immediately, and the sharp version fades in over 150ms on top.
  - **Preloading:** once the current photo is sharp, preload the next two and the previous one at low priority.
  - **Image size:** request the canvas's longest side × backing scale factor, rounded up to 400, at most 3600. Thumbnails: the requested size × backing scale.
  - **Load failure:** show "Couldn’t open {file}" with a Retry button. Never a blank frame (R-44).
  - **No keepers:** an empty state centred on the canvas. Title "Nothing to edit yet" (16pt 600 weight). Body 13pt `#B8B3AB`: "Edit works on the photos you keep. Press R on a photo in Cull to keep it, then come back." Primary button "Go to Cull ⌘2".
- **Zoom picker:** Small / Fit / {percent} / 1:1 / 2:1. Range is ¼× of Fit up to 2× of 1:1. Pinch and ⌘± step through it, ⌘0 fits, Z toggles 1:1 at the pointer, and dragging pans.
- **Status chip** while files load: "Loading full size".
- **Filmstrip** (scenes in order, each with "{done}/{n}"): thumbnail height 32, 40 (window ≥ 760 tall) or 56 (≥ 960 tall and ≥ 1400 wide). The current thumbnail is centred. Only ±120 around the current photo are drawn for large shoots. Done thumbnails get a 7pt `#EFECE6` dot at top-right. Empty: "No keepers yet. Mark photos to keep in Cull."
- **Facts line**, 12pt `#B8B3AB`, single line: "{lens} · {shutter} · f/{ap} · ISO {iso} · {fl} mm · {time}". Missing fields are left out.

**Controls column:** shadow inset 1pt 0 0 hairline on its left edge.
- **Header:** file name, then a tag ("As shot", "Auto", "Matched to scene", "Edited"). Undo ↶ and Redo ↷ buttons, plus a "More" ⋯ menu.
- **Tools row:** Auto (A), Crop (C), Before (a toggle switch; hold \ to just peek), Variations (V).
- **Sections:** Light · Curve · Colour · Effects.

| Section | Key | Label | Min | Max | Step | Default |
|---|---|---|---|---|---|---|
| Light | ev | Exposure | −5 | 5 | 0.05 | 0 |
| Light | wb | Temperature | 2500 K | 10000 K | 10 | as shot (log scale) |
| Light | tint | Tint | −150 | 150 | 1 | 0 |
| Light | hl | Highlights | −100 | 100 | 1 | 0 |
| Light | sh | Shadows | −100 | 100 | 1 | 0 |
| Light | con | Contrast | −100 | 100 | 1 | 0 |
| Light | sat | Saturation | −100 | 100 | 1 | 0 |
| Curve | cDark / cMid / cLight | Dark tones / Midtones / Light tones | −50 | 50 | 1 | 0 |
| Colour | {hue,sat,lum}_{red,orange,yellow,green,aqua,blue,purple,magenta} | per colour | −100 | 100 | 1 | 0 |
| Effects | vig | Vignette | −100 | 100 | 1 | 0 |
| Effects | vMid / vRound / vFeather / vHl | Midpoint / Roundness / Feather / Keep highlights | 0 or −100 | 100 | 1 | 50 / 0 / 50 / 0 |
| Effects | shp / nr | Sharpening / Noise | 0 | 150 / 100 | 1 | 40 / 0 |

Colour swatches for the Colour section: red `#E5534B`, orange `#E8913A`, yellow `#E3C84B`, green `#5DB860`, aqua `#4CC3C0`, blue `#4C82E0`, purple `#8E62D9`, magenta `#D45AB5`. Colour has Hue / Saturation / Luminance sub-tabs.

**Slider row:**
- Label on the left. Value on the right: grey `#96918A` when untouched, `#EFECE6` when changed, white while dragging.
- **Track:** 2.5pt `rgba(239,236,230,0.13)`; 4pt `0.22` on hover.
- **Fill:** runs from the default value to the current one. It moves over 160ms with cubic-bezier(0.2,0.8,0.2,1), and doesn't animate while dragging.
- **Default tick:** 6pt `rgba(239,236,230,0.35)`. Becomes 12pt `#EFECE6` while dragging and snapped to the default.
- **Thumb:** scales ×1.15 on hover and ×1.25 while dragging (×1.5 when snapped to the default), using cubic-bezier(0.34,1.56,0.64,1) over 220ms. While dragging it gets a 3pt gold glow `rgba(255,210,122,0.35)`.
- **Drag modifiers:** ⇧ moves at ¼ speed, ⌥ at 1/10. Within 1.2% of the default it snaps to the default. Esc cancels the drag and restores the start value.
- **Other controls:** double-click resets. Click the value to type one; out-of-range values clamp and junk input is ignored. A horizontal two-finger swipe over a slider adjusts it.
- **Hint line** while hovering: "{Label} — drag · ⇧ fine · double-click resets · click the number to type · hold V for variations".

**Bottom bar** (two rows):
- Row 1: "‹" Previous, then **Next →** in gold (⏎).
- Row 2: "Save {n}" and "✕ Out" (X).
- Then "All shortcuts ?".

**Overlays:**
- **Variations** (hold V): a grid over the canvas of the setting under the pointer, or the section's main setting. Three cells: "−¼ EV / now / +¼ EV" for exposure, "cooler / now / warmer" for temperature. It's a 3×3 temperature × tint grid when white balance is the target, and two cells ("none" / "−30") for vignette. Releasing V applies the highlighted cell; tapping V opens the grid without applying. Arrow keys plus ⏎ choose; Esc or V closes. The selected cell gets the gold ring `0 0 0 2px #161514, 0 0 0 4px #FFD27A`.
- **Help** (?): five groups, each key in SF Mono. The exact list is in KEYMAP.md.
- **Crop:** ratio menu (Original, 1:1, 4:5, 3:2, 16:9, Free) with a portrait/landscape swap, a turn button, a straighten angle (−45…45°, 0.1° steps), and a rule-of-thirds grid.
- **First-run intro:** three numbered cards. Esc or ⏎ closes it; it's stored as `lumina.edit.intro.v1`.
- **Warnings:**
  - "Couldn’t save on this computer. Keep this window open." (storage failed)
  - "Changed in another window" (the same shoot is open elsewhere)
  - "Offline · saved on this computer"

---

## 4 · Save
**Layout:** a centred column, max-width 640, padding 44 / 24 / 56, gap 22.
1. **Title** "Save" (Iowan 28pt). Subtitle: "Originals are never changed. You can save again any time."
2. **Summary:** "{n} keepers ready to save" (15pt 600 weight), or "No keepers yet". Under it: "{x} out · {y} undecided · not saved", with a "Finish culling" link when anything is undecided.
3. **"Save for"** segmented control, 3 columns: Lightroom / Folder / JPEG. Padding 3, radius 10, fill `rgba(239,236,230,0.07)`. Each segment is 34pt high; the selected one is `#5B5854` at 700 weight. Below it, a description 12.5pt `#B8B3AB`:
   - XMP: "A small .xmp file next to each RAW: keepers as 3★, edits as develop settings. The RAW is untouched. Works with Capture One too."
   - Folder: "Copies of your keepers…"
   - JPEG: the JPEG equivalent.
4. **Destination:** the path in SF Mono, truncated in the middle, plus "Change…". In the app this opens a folder picker.
5. **"Include my edits"** toggle row (only when something is edited):
   - Row: `#262523`, radius 10, padding 12/14.
   - Switch: 30×18, gold when on.
   - Subline: "{e} edited, {k−e} as shot" when on, or "All as shot · edits stay in Lumina" when off.
   - A "Review" link that opens Edit.
6. **Save button:** height 40, padding 0/22, radius 10, 14pt 600 weight, ⏎ hint. Its label:
   - "Save {n} photos"
   - "Save again · {n} photos" (after a change)
   - "✓ Saved" (disabled)
   - "Nothing to save yet" (disabled)

   The note beside it reads "Keep photos in Cull first.", "Up to date." or "Changed since {hh:mm}. Only what changed is rewritten."
7. **Saved card:** slides in over 180ms (translateY 4 → 0 plus fade). Gold tint `rgba(255,210,122,0.08)`, inset 1pt `rgba(255,210,122,0.25)`, radius 12.
   - Title "Saved · {n} photos, {e} with edits · {hh:mm}" (or "Saved again · …") in gold 13.5pt 600 weight, then a "Show in Finder" link.
   - Hint: "In Lightroom: Import → Add, or Metadata → Read Metadata from Files." (XMP), or "JPEGs are ready to share or upload."

---

## Design tokens
**Colours:**
- Backgrounds: app `#1E1D1B`, panel `#262523` (hover `#2C2B29`), canvas and tiles `#161514`, selected `#5B5854`.
- Text: primary `#EFECE6`, secondary `#B8B3AB`, tertiary `#96918A`, disabled `#6E6A64`.
- Gold accent `#FFD27A`: primary emphasis, progress, Next, "kept".
- Errors: text `#F0A39E`, dot `#E5534B`, background `rgba(229,83,75,0.08)`. Success dot `#7FC46B`.
- Fills, as `rgba(239,236,230,α)`: α = 0.04 (rest row), 0.06, 0.07, 0.08 (secondary button, hairline), 0.09 (row hover), 0.1, 0.12, 0.13, 0.16 (button hover), 0.22, 0.28.
- The primary button `#EFECE6` turns `#FFFFFF` on hover.

**Type:**
- UI: SF Pro Text. Sizes 11 / 12 / 12.5 / 13 (body) / 13.5 / 14 / 15 / 16 / 18. Weights 400 / 600 / 700.
- Titles: Iowan Old Style 21 / 24 / 28.
- Key hints: SF Mono 11–11.5.
- Use tabular figures throughout.

**Radii:** 2–3 (photos, tiles), 5 (tab thumb), 6 (small chips), 7 (tab track, radio pills), 8 (secondary buttons), 9 (primary buttons, rows), 10 (segmented control, Save button, toggle row), 12 (cards), 14 (drop overlay).

**Control heights:** 24 (tabs, chips), 28 (pills), 32 (secondary), 34 (footer buttons, segments), 36 (primary, Keep/Out), 40 (Save).

**Spacing:** 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 28, 44, 56.

**Motion:**
| What | Duration | Easing |
|---|---|---|
| Step change | 160ms | fade, ease-out |
| Panels and overlays | 120ms | fade |
| Tab thumb | 160ms | ease-out |
| Tile load, Out-dim | 120ms | ease-out |
| Keep badge "pop" | 200ms | ease-out |
| Saved card | 180ms | ease-out, 4pt rise |
| Slider fill/thumb | 160ms | cubic-bezier(0.2,0.8,0.2,1) |
| Thumb scale | 220ms | cubic-bezier(0.34,1.56,0.64,1) |
| Sharp photo fade-in | 150ms | ease-out |
| Crop/rotate box | 220ms | cubic-bezier(0.2,0.8,0.2,1) |

Nothing loops forever except loading spinners (R-61).

## State (what the app must model)
- **Shoot:** photos (id, file, scene, burst, aspect ratio, capture time, camera details, source URL), scenes (start time, title, ids), bursts (ids).
- **Flow:** `step` ∈ open/cull/edit/save, `copied`, `cur`, `fmt` ∈ xmp/folder/jpeg, `withEdits`, `saved{sig,n,ne,fmt,at,again}`.
- **Decisions:** `keep[id]` = true / false / unset. Undo and redo stacks hold the last 200 steps.
- **Edits:** `looks[key]` maps setting to value. The key is the photo id, or the burst id when 2+ frames of one burst are kept, so kept burst frames share one edit. Also `tags[key]`, `done[key]`, and Edit's own undo/redo (200 steps).
- **Save signature:** `fmt # withEdits # keptIds # (if withEdits) per-edited-photo look JSON`. Saving with an unchanged signature does nothing (R-34).
- **Persistence:** save every change immediately (Edit coalesces drags); the prototype keys are `lumina.flow.v1` and `lumina.flow.edit.v1`. The native app should use its real store (backend is ready). It must restore the step, current photo, decisions, edits and copy progress on relaunch, and cope with a full disk (R-70…R-73).

## Assets
- No custom icons. Glyphs used: ↶ ↷ ⋯ ✓ ✕ ‹ → ▾ ▴ ⏎ ⌘ ⇧ ⌥.
- Demo photos in the prototype come from picsum.photos. The real-photo set is the Unsplash Lite dataset, first 5,000 photos (`prototypes/data/lumina-shoot-unsplash.js`); it's free for commercial use but the images may not be redistributed.
- Use real camera files for app testing.

## Files
- `prototypes/Lumina Workflow.dc.html`: Open, Cull and Save, and the Edit host.
- `prototypes/Lumina Edit v19.dc.html`: Edit.
- `prototypes/Lumina Stress Test.dc.html`, `Lumina Controls Test.dc.html`, `Lumina Newbie Test.dc.html`: the HTML test harnesses. Open one and click Run; keep the tab in front.
- `prototypes/data/lumina-shoot-unsplash.js`: the real-photo shoot (`?shoot=unsplash` or `?shoot=unsplash-1000`).
- `prototypes/support.js`: the runtime the prototypes need. Not part of the app.
