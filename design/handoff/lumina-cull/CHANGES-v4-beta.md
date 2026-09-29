# v4-mvp → v4-beta: what changed, and how to check it

Each section lists **what**, **where** in `Lumina Sets v4-beta.dc.html` (method / `data-lumina` name), and a **check** to run in the page console. The browser sample works without the app. `?notes` shows the import notes and `?oncard` shows the card warning.

Helpers: `S=()=>luminaState()` · `K=(key,code,o={})=>dispatchEvent(new KeyboardEvent('keydown',{key,code,...o}))` · `U=(key,code)=>dispatchEvent(new KeyboardEvent('keyup',{key,code}))`

---

## Removed (delete; don't hide)
| Gone | Instead |
|---|---|
| Reject: X, `'out'` marks, ✕, dimming | keep or leave it. Saved `'out'` marks are dropped on load (`Component.clean`) |
| U (clear), T/L as flag, G zoom, stars 1–5 / 0, colour labels 6–9 | P again un-keeps · F flags · Z zooms · every keeper is written as 3★ |
| Multi-select (⌘-click, ⇧-click, marquee, S, row-header select) | the unit under the cursor is the only selection |
| Resolve-on-leave, "decided" progress, ⇧X, sweep-rejects | rows are "seen" (§2) |
| Tile fact lines and soft / blown / shake / dark words | nothing on the tile except the picture and its state |
| Large-view bottom info line | frame strip plus time axis (§4) |
| Handoff target picker (Lightroom / Capture One) | one output. The steps under the button cover both apps |

**Check R1:** X, U, L, G and 1 each show a footer hint and change nothing: `S().undoDepth` stays the same.

## 1. Keys
- **P** keeps and **P again** un-keeps. **R** and **T** are silent aliases of P (T is Photo Mechanic's tag key). The key bar shows only P.
- **F** flags a photo to revisit; a flagged photo gets no sidecar. **⇧F** flags or unflags the whole stack.
- On a closed stack, **P** keeps the sharpest frame (a bracket keeps all frames); P again clears the stack's keeps. **⇧P** keeps the sharpest now.
- **Space** hold shows large view while held; a tap toggles it. **Z** hold shows 100% (and opens large view if it wasn't already).
- **⌘R** shows in Finder: the photo in cull, the folder in handoff.
- **Q / ⌘Z** undoes.
- Unused keys (X U L G 1–5) show what to press instead.
- **Where:** the key mapping at the top of `cullKey()`, `decide()` (toggle), `sweepCh()` (keep or null only).
- **Check 1:** P on a photo → `S().marks[id]==='keep'`; P → the key is absent; T → kept again.

## 2. Rows seen
- A row is seen once the cursor leaves it. The header reads `6 kept · seen`, the key bar's right side reads `N rows to go · K kept`, ⇧U shows only unseen rows, and ⏎ on a photo jumps to the next unseen row.
- **Where:** `seeCheck()`, `undec()`, state `seen:{rowId:true}` (persisted).
- **Check 2:** ↓ from row 0 → row 0's `[data-lumina=row-progress]` contains `seen`.

## 3. Stacks open in place, in capture order
- ⇧→ opens a closed stack inline at frame 1; ⇧← opens it at the last frame. The frames get their own line with a `[data-lumina=stack-axis]` above them: `burst · 31 · continuous drive` (or `≤2 s apart, similar`), ticks at capture time, the sharpest in gold, and the current frame's relative time. ⇧←→ steps frames. Plain ←→ closes the stack and moves to the next unit. ⏎ opens (on a closed stack) or finishes and moves on (on a frame). esc closes. Opening large view or zooming on a stack opens it at frame 1.
- **Where:** `openStack(gid,last)`, the layout (`c.ln / c.col / c.off`, where `c.ax` inserts the axis and `c.brk` a line break), `axis()`, `times()` (frames within the same second are spaced evenly and labelled ≈).
- **Check 3:** on g11, ⇧→ → `S().cur` is the first frame in time order and `[data-lumina=stack-axis]` exists. → → the axis is gone and the cursor is on the next unit.

## 4. Large view (loupe)
- Mid-grey surround `#3A3835`; the image is an `<img>` at its real aspect ratio with a hairline border and shadow, and the preview shows until the full-size image decodes. Opening fades over 220 ms and grows the photo from 0.94 over 280 ms; closing fades and shrinks over 200 ms. ±1/+2 images are preloaded.
- ←→ steps continuously: through the frames of a stack, then on to the next unit, then across rows. Arriving at a stack opens it at frame 1 (going forward) or the last frame (going back).
- Under the photo: position `12 / 31` with `sharpest · most edge detail in the preview`, a 13-frame strip (`+N` counts for hidden frames), the state (`kept` / `flagged` / blank), and `[data-lumina=large-axis]` with capture-time ticks. For single photos the strip and axis show the photo's row in clock time.
- Double-click opens and double-click closes. Z at 100% keeps a region per stack; dragging moves it.
- **Check 4:** Space on a stack → `[data-lumina=large-axis]` exists; → ×40 walks past the stack into the next unit without stopping.

## 5. Moves never hide a photo
- `setCuts()` refuses a move if any id would drop out of the rows. After a move the view scrolls to the photo, it pulses gold, and the footer says `moved … · inside the stack · Q undo`.

## 6. Handoff
- The top row has the keeper count and **⌘R Show in Finder** (always available).
- The button reads `⌘⏎ save 88 keepers`. Its tooltip says the RAWs aren't changed and that Lumina doesn't control Lightroom.
- Numbered lines explain it:
  1. A .xmp is written next to each RAW.
  2. It rates the photo 3★; existing sidecars only get the rating changed.
  3. How Lightroom Classic reads it.
  4. How Capture One reads it.
- "where the files go · 104 KB in 88 files" expands into a folder tree with real byte sizes (from `xmpFor()` output), then the summary lines.
- The keepers grid shows each keeper; clicking one opens it in cull, and "⌘2 back to cull" returns.
- **Card guard:** `onCard()` (app: `lumina.readingCard`) shows an amber notice and turns the button into an outline reading "copy to disk first"; ⌘⏎ explains instead of sending.
- **Check 6:** keep 2 photos, ⌘3 → `[data-lumina=handoff-finder]` exists and the send text is `⌘⏎ save 2 keepers`.

## 7. Import notes (one panel, not one warning per file)
- After reading, `[data-lumina=import-notes]` lists:
  - JPEGs with a matching RAW (left alone)
  - JPEG / HEIF without a RAW (not shown; Lightroom ignores sidecars for JPEG)
  - other RAW formats (`40 CR3 · Sony ARW only`)
  - videos and other files skipped
  - more than one body (warns that the clocks need to match)
  - existing sidecars and how many have Lightroom edits
  - photos already rated, with a **keep these N** button
  - missing previews
  - unreadable files
- A folder with no ARW files shows the breakdown on the Open screen instead.
- **Where:** `intake()`, `notesFor()`.

## 8. Open screen, steps, browser prompt
- A card panel and a ⌘O tile; recent shoots as cards. The card panel says "read in place · nothing is copied, moved or written to the card".
- The step bar is a sliding three-button switch.
- Browser only: before Chrome's "Upload N files?" prompt appears, an amber sheet explains it (⏎ continue · esc cancel · don't show again). The app never shows it.

## 9. Transparency, tooltips, contact
- Tooltips appear after 450 ms on `[data-tip]` and disappear on any key, click or scroll. They are on the row reason, row progress, stack badge, rank, axes, send button, Finder button, load bar and steps.
- The ? sheet adds **How Lumina decides** (rows, stacks, sharpest, peak, seen, written, card, saved) and **Contact** (X @aniketh745 · anikethcov@gmail.com; both open a link).

## 10. Loading, motion, accessibility
- Thumbnails fade in over 180 ms on load. A 2 px gold `[data-lumina=load-bar]` (role progressbar) fills while reading. `prefers-reduced-motion` turns animations off.
- Secondary text is `#96918A` or lighter; large-view text is `#CFCAC2` on grey. The footer is `role=status`, tiles are `role=img` with labels and `aria-current`, and steps are `role=tab`.

## 11. Storage
- Saved sessions are capped at the 8 most recent shoots (`prune()`). "Remove Lumina's working files" in the browser clears saved sessions and the image cache (`clearCache()`) and shows the real size.

## Contract (page ↔ app)
- **The app must provide:**
  - `lumina.reveal(path)`: Finder, for a file or a folder.
  - `lumina.readingCard`: true when the shoot is on a mounted card.
  - `lumina.removeWorkingFiles()`.
- `luminaState()` → `{cur, sel, marks, stars, flags, cuts, view, tile, undoDepth, shown, region, pending}`. `stars` is always empty now.
- `luminaGesture('hold',{key,down,modifiers})`: arrows (with modifiers `'shift'` inside a stack), Space, Z.
- plumbing.js: `labels` removed from BY_ID; `seen` and `regions` added to SCALAR.

## Known, left as-is
- `LuminaCore.sweep` still returns `'out'`; the page doesn't use it for decisions. The fixtures still test it, so leave it alone.
- There's no Tab focus order yet. A rule is needed first (proposed: Tab moves through buttons; letters act only while the grid has focus).
