# BRIDGE v0.03: page ↔ app, what changed since v0.02

Additions to BRIDGE.md and BRIDGE-v0.02.md. Where they disagree, this file wins. Every page→app call is guarded with `typeof lumina.x === 'function'`. In a browser none of them run.

Page files: **Lumina Sets v9.dc.html** (mounts **Lumina Edit v22.dc.html**), `lumina-core-v4.js` (same name, added functions), `lumina-selftest.js`. `onDir` and `readOne` have not changed.

## 1. Edit drives the native canvas (Prompt 12)
Edit v22 makes these calls while it is mounted:

| Call | When | Payload |
|---|---|---|
| `lumina.canvasRect(r)` | on mount and every layout or resize (ResizeObserver on `[data-lumina=canvas]`), and when cover changes | `{x,y,w,h,dpr}` in CSS px relative to the viewport. `null` when Edit unmounts, or when the spectrum, scene grid, help or any Sets overlay covers the canvas |
| `lumina.preview(rel, look, px, seq)` | at most once per animation frame, with the newest look; again on drag end | `look` is the canonical look string (§4). `px` is the canvas long edge in device px (a number). `seq` rises by 1 each call |
| `lumina.drag(phase)` | press and release on any slider, curve point, histogram, vignette handle or canvas drag | `'start'` / `'end'` |
| `lumina.roi(r)` | while zoom is above 1.2×, and as it pans | `{x,y,w,h}` in image px when the photo record has `pw`/`ph`, else `{x,y,w,h,unit:'norm'}` as fractions. `null` when zoom ends |
| `lumina.prefetch(list)` | entering Edit and on every cursor move | P0 is the current photo at full size. P1: ±1 at full size, ±2…3 at screen size, and up to 12 photos from the same row at screen size |

**What `preview` returns**
- `null` / `undefined`: the native path. The canvas `<img>` stays blank, so the box is transparent.
- A URL string: the image path. The page shows it in the canvas `<img>`, with the previous URL kept underneath so no frame is ever blank. A 409 or an `onerror` leaves the previous image on screen.
- `false`: the app can't render this photo. The page shows its own embedded preview for it.

**Hooks Edit defines on mount and removes on unmount** (each carries `__owner`):
- `luminaPresented(seq)`: returns `false` when `seq` is older than one already shown, so the app drops it. It also clears "rendering…".
- `luminaHistogram({seq,r,g,b,clipHi,clipLo})`: any bin count, resampled to 64. Stale seqs are ignored. It drives the histogram and the clipping marks.
- `luminaFacts({canvas,raw9,decoder,note})`:
  - The facts line gets ` · canvas: native · raw 9: yes`.
  - If `note` contains "update shoot", those words become a gold link that calls `lumina.edit.updateDecoder()`.
  - While `raw9` is true, the keys in `Component.RAW9_HIDE` are hidden. Edit v22 has no Colour NR, Detail or Moiré slider yet, so today nothing is hidden.
- `luminaEditStats(s)`: stored, probe only.
- `luminaEditRect()` / `luminaEditImage()`: read-only getters (the last rect; `{rel,url,seq,shown}`). See CHANGES-v0.03 Q1.

**rendering…** appears in the facts line when the newest request hasn't been presented within 120 ms.

**`luminaState().native`** reports `{on, rect, seq, shown, pending, fallback, facts, roi}`.

**`luminaEdit.cover(bool)`**: Sets calls this when the cache panel, FAQ, keys tutorial, tour or phone page opens over Edit. Edit then sends `canvasRect(null)`.

## 2. Steps the app can enter
- `window.luminaStep('open'|'pick'|'edit'|'save')` returns true when the step command was sent. `luminaCommand('stepEdit')` works as before.
- Entering Edit mounts Edit v22, which reports its own canvas rect (§1). The app no longer needs `edit.layout(rect, true, {force:true})`.

## 3. Workflow state, moves, read end (asks 6, 7)
- `luminaState()` gains these fields:
  - `step`: `'open'|'pick'|'edit'|'save'`
  - `pass`, `passFrom`, `funnel[]`, `kept`, `total`, `aim`
  - `show`: `'all'|'picks'|'notKept'`
  - `tray`, `rowsSeen`, `rows`, `passDone`, `autoAdvance`, `stack`, `large`
  - `reading`, `readMoved`, `readStay`
  - `leadReady`: `{id, ms, nopv?, timeout?}`
  - `lastMove`
- Events go through `lumina.emit(type, detail)` and `window` `lumina:<type>`. They are always sent on a later task, never inside a render:

| Event | Sent when | Detail |
|---|---|---|
| `flow` | any field above changes | the same object |
| `moved` / `stayed` | split, merge, drag-drop onto a row, stack or gap, or a header boundary drag | `{kind:'move'\|'split'\|'merge'\|'boundary', ids, label, rows}`; `stayed` adds `reason` (`'same place'`, `'would hide photos'`, `'no change'`) |
| `readEnd` | a folder read finishes | `{stay, cur, photos}`. When `stay` is true, the reader moved, kept or scrolled during the read, and the page kept `cur` and the scroll position (v0.02 behaviour, now reported) |
| `leadReady` | the first tile under the cursor has decoded after entering Pick or starting a pass | `{id, ms}`, or `{nopv:true}` / `{timeout:true}` after 6 s |

## 4. Look string (BRIDGE-v0.02 §4, now fixed text)
`LuminaCore.lookString(look)` and `LuminaCore.parseLook(str)` follow the Prompt 1 §2 grammar, extended with Edit's own keys:
- Space-separated `key:value`.
- Order: `ev wb con hl sh wh bl vib sat clr shp nr vig bw crop`, then every other key A→Z.
- `ev` has two decimals and a sign. Integers have a sign, except 0. `shp` and `nr` have no sign.
- `wb:K/tint`; either side may be empty.
- `bw:1`.
- `crop:x,y,w,h/angle`, plus `cropRatio:<preset>`.
- Anything else (curve points, strings) is `key:~` + `encodeURIComponent(JSON)`.
- `''` is as shot.

The roadmap example `ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0` round-trips byte for byte (tests in `lumina-core-v4.test.mjs`). Port both functions exactly.

## 5. Rows (ask 8 / design ask 11)
- `rows` is now every layout row in order. Rows outside the render window come through as `{gap:true, h}` and render as `<div data-lumina="row-gap" data-key data-id style="height:h">`. So a row's position in the list is its index, and an element is never handed another row's content while you scroll. `topPad`/`botPad` are 0.
- Every row element carries `data-key="k<first photo id>"`. `data-lumina="row"` + `data-id` are unchanged.
- The tile `<img>` no longer has `loading="lazy"`. A thumbnail that is already decoded shows at full opacity; the fade runs only during a read (v0.02 `imgOp`). The render window leads the scroll: 700 px behind, 2 viewports ahead.
- plumbing.js can drop `rowKeys`, `readyTile` and `lead`.

## 6. Warm-ahead (ask 9)
The page decides what to warm; the app decides when.
- **Pick:** kept photos nearest the cursor, P2 screen (≤ 60), re-sent when marks change.
- **Picks-only view (⇧P):** every pick at P1, the first 3 full size, the rest screen size (≤ 300).
- **Save:** every pick at P2, full size (≤ 300).
- **Edit:** Edit's own list (§1).
- The page also preloads big-view JPEGs ±2 around the cursor, as before.

The same list is never sent twice. Calls are debounced 150 ms.

## 7. Storage meter (Prompt 14)
- **Browser:** the localStorage scan is measured again after every write (persist, prune, remove, clear). It is never memoised on a timer. The big-view preview count is read live, and a preload that changes it redraws the meter at once.
- **App:**
  - `lumina.workingFiles()` runs on mount, when the panel opens, when Save opens, after a save and after a removal. Only the newest answer counts.
  - While a removal is being measured again, the total, rows and bar are blank (no number at all). "freed N" is the size before minus the size after.
  - The app may push `window.luminaWorkingFiles(bytes)` whenever the size changes.
- No clocks decide what is drawn.

## 8. Save on a removable volume (DESIGN-ASKS 9)
- `onCard()` is true whenever `lumina.readingCard` is true, even with no card in the panel.
- While the card is out (`luminaCardGone(true)`), the primary button reads "card removed · insert it to keep going".
