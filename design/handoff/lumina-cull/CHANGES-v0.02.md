# CHANGES since v0.01 (exact behaviour)

## 1. Pick grammar: kept or not, passes, nothing deleted
- **Two states only:** kept, or not.
  - ⏎ / P / K keep the photo and move on. On an already-kept photo they just move on and never toggle.
  - R / X un-keep it (or pass it) and move on.
  - A closed stack: ⏎ keeps its best frame; R un-keeps every frame.
  - There is no "removed" mark any more. An old session with `out` marks loads them as not kept (`Component.clean`).
- **⇧ goes back:** ⇧⏎ / ⇧R step to the previous photo and keep it / un-keep it (`backDecide`). In the large view too.
- **Next row not yet seen** moved to ⌥↓.
- **Holding ⏎** repeats keep-and-move-on. Key-repeat events collapse to one per frame. On a closed stack, holding ⏎ keeps its best frame. ⏎ never opens the large view; only Space does.
- **Auto-advance** always moves; the Settings row is removed. Caps Lock is the only hold, and the footer says "auto-advance off · ⇪" while it's on.
- **Passes:**
  - ⇧P (or Save → "Start pass N · the K kept") starts the next pass (`startPass`). It records `depth[id]=N` for each kept photo and `funnel[N-1]=K`, increments `passN`, resets `seen`, and shows the kept photos only.
  - Later ⇧P presses switch between this pass's photos and all photos. ⇧P again from the picks view → all photos with the tray hidden → ⇧P → tray shown.
  - Esc → all photos.
  - `pass:3` shows only photos that aren't kept; ⏎ keeps one, and it then leaves that view.
  - The footer reads "Pass 2 · 52 → 31 · …". When all rows have been seen: "Pass N done · K of M kept · ⌘4 to see your passes".
- **Save step:**
  - The pass funnel: All 341 → Pass 1 52 → Pass 2 · now 31 (current pass in gold).
  - "Start pass N+1 · the K kept"; "Look at the M not kept".
  - Aim chips: none / 10 / 25 / 50 / 100, with "N to go · another pass narrows them" / "on aim" / "N under aim · fine as it is".
  - The note explains ratings and keywords.
  - The button reads "Save 64 photos · 3 passes".
- **Save guard:** warns once about rows not looked at this pass. It no longer warns about "undecided" photos.
- **Aim:** shown in the footer ("aim 30 · 22 to go") and when a pass starts.
- **Persisted per session:** `passN`, `depth`, `funnel`, `aim`.
- **Flag is gone:** no keys, no pill or chip, no words. Saved flags are ignored on reopen.
- **⇧A** suggested picks are behind `Component.AUTO_ON=false` (see prompts/PROMPT-8g-culleval.md).

## 2. Keys tutorial + FAQ
- A 7-step tutorial in the onboarding style (520 px card, 200 px illustration, serif title, key chips, dots, Skip / Back / Next ⏎).
- Steps: The rule · Stacks · Inside a stack · Look closer · Nothing is final · Passes · Save.
- Opened by `luminaCommand('grammar')`, by the FAQ's "Learn the keys →", and by the tutorial's FAQ button (which goes the other way).
- ← / → / ⏎ / esc work inside it.

## 3. Wording
- Cull → Pick everywhere (Sets and Edit).
- rejected / removed → "not kept" (Sets) / "removed from picks" (Edit X).
- ⌘3 Save → ⌘4 Save.
- The card line says "no ARW or DNG found".
- Edit R hint: "R sets photos aside in Pick, so it does nothing here. To turn this photo: C, then R."

## 4. Edited indicator
- A 5 px dot (#EFECE6 at 0.7, 1.5 px dark ring) at the top-right of a tile edited in Edit.
- For a stack, the dot shows if any frame was edited.
- The large view's info line adds " · edited".
- Auto-only and as-shot looks don't count as edited.
- Read from Edit's store (`lumina-edit.<shoot>` → `looks`, `tags`) on mount and whenever Edit is left.

## 5. Grid performance and resilience
- **Time axis:** ticks are laid out in content coordinates and moved with `translate3d` in `onScroll`. No React render per scroll frame.
- **Visible rows:** found with a binary search (`rowSpan`). The ±700 px render window comes back 240 ms after scrolling stops.
- **Tile width/height animation:** only within 240 ms of − / +, never during a window resize, and never with Reduce Motion.
- **Rows:** `contain: layout paint`; the scroll box has `overscroll-behavior: contain`.
- **Unfurl** (stack open):
  - The snapshot only records which tiles are in the DOM: no rect reads, no clones.
  - It's skipped if keys are queued or another unfurl happened under 260 ms ago.
  - A new unfurl finishes the previous one; at most 24 frames animate.
- **Key queue** (`onKeyQ`):
  - One key per frame. The next one drains at rAF or after 40 ms, whichever comes first.
  - Held-key repeats collapse into one.
  - ⌘ keys, Shift, Esc, Tab and every keyup flush the queue first, so order holds.
  - Errors are caught, and the queue keeps going.
  - If it's stuck for over 150 ms, it force-drains.
  - Window blur / visibility change clears the queue, held keys and any paint in progress.
- **Holding ⇧** for ⇧⏎ / ⇧R: the add-photos bar closes as soon as one of those keys is pressed.
- **Images:** the picks tray only renders an `<img>` when the photo has a preview (no empty `src`).

## 6. Reading files (lumina-core-v4.js)
- `parseHead`:
  - Returns `null` under 8 bytes.
  - Collects tiled (0x0144 / 0x0145) and multi-strip JPEG previews (`pvParts`) and uncompressed 8-bit RGB thumbnails (`pvRGB`).
  - Checks FF D8 on 0x0201 previews inside the head.
  - `previews` lists up to 4 candidates.
  - `dng` defaults to null.
- `assemblePreview(file,m)`: draws the pieces onto a canvas, or falls back to the RGB thumbnail (`low:true`). The tile word is "low-res preview", and those photos get no soft or blown words.
- `readOne` (Sets): tries each preview candidate in turn; the first with FF D8 wins.
- **Sony MakerNote:**
  - Read with or without the "SONY" header (IFD at +12 or +0).
  - The 0x9400 layout is checked on the stored byte `u8[p]`.
  - `seqImage = SequenceImageNumber+1` when length > 1, else null.
- **Soft and blown (8g):**
  - Soft only within a burst (< 0.45 × its sharpest frame).
  - Blown in a burst only if `clip ≥ 3` and `> min+3`. For a single only if `clip ≥ 3` and `> max(5, row median × 2.5)`. Brackets never.
  - "slight" is removed.
- **Notes:** "N without an embedded preview · shown as grey tiles"; "N with only a small built-in preview · shown low-res · no soft or blown words".

## 7. Edit v21
- **Default render** is Lightroom-match (`state.tm='match'`, the v19 / `rules-v1.json` baseline). ⇧T switches to the AgX preview.
- **Auto:** `autoRecipe()` asks `lumina.auto` → `LuminaAutoFixtures` → the estimate. The footer names the source.
- **The estimate** (browser only) treats the camera's exposure as the baseline:
  - It lifts only if the median is < 0.30 (≤ +0.6 EV, +0.4 for DNG, and never into clipping).
  - It pulls only if the median is > 0.62 and more than 1% of the image is clipped (≤ −0.5 EV).
  - Highlights and shadows are left to their own sliders.

## 8. Window chrome
Decision 9a: a standard title bar. Page area 1440 × 872.

## 9. Tests to add
- **Core:**
  - a head under 8 bytes → null;
  - a tiled or multi-strip fixture → `pvParts`;
  - `pixel-rgb-thumb` → `pvRGB`;
  - a SONY-less MakerNote is read;
  - a single shot has `seqImage` null; frame 3 of 5 has `seqImage` 3.
- **Soft/blown:**
  - a single has no soft;
  - a burst frame below 0.45× its sharpest is soft;
  - a bracket is never blown;
  - a single at 6% clip in a row with median 1% is blown; in a row with median 4% it isn't.
- **Sidecars:**
  - `freshXmp(…,'Lumina pass 2')` contains the dc:subject and lr:hierarchicalSubject bags;
  - `mergeXmp` replaces an old Lumina pass keyword and keeps the others.
- **Selftest** (already in the file): R un-keeps (two states only); ⇧R steps back and un-keeps; F held shows the focus overlay; ⌘4 shows the Save bar with a count.

## Still open (not in this handoff)
- 6b: unreadable files stay as grey tiles instead of being dropped. 7a pairs with it.
- 8e: dHash cutoffs from real frames.
- 8f: retakes via `lumina.near`.
- 10b: keying rows by id (needs a runtime change).
- 4a–d: Save card and sidecar refresh.
- 5a–f: Open-step states.
- 9a: the shift-capture-time sheet.
- Side-by-side compare from pass 2 on.
