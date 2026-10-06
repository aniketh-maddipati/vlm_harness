# What's left after v0.03, element by element

> **Status at v0.05.**
> - Done: A1, A2, A4, B1, B2, B3 F, B5 b, C2, D1 A, D2, D3, E.
> - Before release: A3, D1 B/C.
> - After release: everything else.
> - Details are in CHANGES-v0.04 and CHANGES-v0.05.

Source: the app contract (DESIGN-ASKS Prompts 1 to 14, asks 1 to 11, the "Still open" list), checked against Sets v9 + Edit v22.

Each line is `[screen] element (data-lumina) — what to build — source`. Status: **open** means nothing is built; **partly** means some is built and the rest is listed. Every closed item is in CHANGES-v0.03.md.

## A. Open step

### A1. Opening state · ask 10 · open
- `window.luminaOpening(info)`: the app calls it with `{name, onCard}`, then with `null` when the listing arrives, access is refused, or the open is cancelled.
- `div[data-lumina=opening]` sits where `[data-lumina=live]` appears. It holds 2 spans, column, gap 2:
  - span 1 (13, `#B8B3AB`): `Opening <name>…`, shown after 400 ms;
  - span 2 (12, `#9A958D`): `the disk is waking up`, shown after 3 s.
- No spinner and no count.
- Keys: Esc clears it (the app drops the late listing). ⌘O still opens the picker.

### A2. Card Lumina may not read yet · Prompt 9 · open
- `div[data-lumina=card]` gets a third state when `lumina.cardPending` is set:
  - `l1` `<name> · not opened yet`;
  - `l2` `The Mac asks once per card. After that it opens at once.`;
  - gold button `Allow & open… ⏎`, which calls `impStart()`;
  - no photo count or GB.
- `card.l3` stays "Read-only. Files stay on the card."

### A3. Sessions from before the sandbox · Prompt 11 · open
- `div[data-lumina=import-notes]` variant: `Your earlier culls are in the old Lumina folder.` with a button `Bring them over…` (`lumina.migrate()`, name to be agreed).
- It shows only while the recents list is empty and `lumina.legacy` is true.

### A4. Folder too big / oversized sidecar / session refused · Prompt 6 · open
- The Open line (`openNote`) gets these words:
  - `not available · <folder> · over 100000 files · open one shoot`
  - `… folders over 12 deep …`
- The `?` failed list gets `DSC00002.xmp · sidecar over 1 MB, not read`.
- The footer `say`: `decisions not saved · session too big`.

## B. Pick

### B1. Photos Lumina can't show · Prompt 3 A · v0.02 "6b/7a" · open
- **Tile** `div[data-lumina=tile]` with `nopv`: under the file number, a second line `no preview` (11, `#7D7971`).
- **New `unread` record** (onDir keeps it, never drops it): same grey tile, second line `can't be read`.
- **Large view** `[data-lumina=large-shot]`: grey 3:2 frame, caption `DSC00203 · can't be read · 0 KB`.
- **Open line:** `500 photos · 41 rows · 12 stacks · 3 without a picture`.
- **`import-notes` wording:**
  - `2 without an embedded preview · shown as grey tiles`
  - `1 can't be read · shown as a grey tile`
- **Core:** a photo with no date sits after the nearest lower file number, in that photo's row. No `00:00` row, and no gap label worked out from a missing time.
- **Keys:** P/R/⌘A/paint work on these tiles. Each is always a single.

### B2. Shift capture time · Prompt 3 B · v0.02 "9a" · open
- Command `shiftTime` (MENUS: Photo ▸ Shift Capture Time…).
- `import-notes` two-body line gains an action `shift a camera's time…`.
- **Sheet `div[data-lumina=shift-sheet]`**, 520 card, onboarding style:
  - Title: `Shift capture time`.
  - Line 1, a radio list: `whole shoot` · one entry per body (`ILCE-7M3 · …1111 · 212 photos`) · `from this photo on`.
  - Line 2: a typed offset `+1:00:00`, plus `−1 h` / `+1 h` chips.
  - Line 3, live: `41 rows → 38 rows`.
  - Line 4, quiet: `Only changes how Lumina orders this shoot. Your files and their capture times are not changed.`
  - Keys: `⏎ shift · esc cancel`. ⏎ is off at 0:00:00.
- **After the shift:**
  - footer `Shifted 212 photos by +1:00:00`, one undo step;
  - row header `[data-lumina=row]` gets `· time shifted`;
  - the shift is stored in the session and never in a sidecar.

### B3. Culling signals · Prompt 2 · partly
- Done: A (sonyMN), E (soft only within a stack), H (`AUTO_ON=false`).
- **Open B:** `measure()` dHash from cell means instead of 9×8 point samples, with thresholds set from real frames. "≥ 28 splits" never cuts a sequence-numbered burst. (Core only.)
- **Open C:** retakes via `lumina.near(a,b)` / `lumina.nearLimit`. Stack two frames when they are ≤ 60 s apart, have the same lens, focal length (±5 %) and orientation, and `near ≤ nearLimit`. Fall back to dHash when `near` is null. (Core + readOne; nothing visible.)
- **Open F:** remove the `shake` word from the tile words and the large-view info. Keep the shutter speed in facts.
- **Open G:** `lumina.measures(path)` → `{faceQ, faces}`. When every frame of a stack has `faceQ`, rank by it, and the stack badge reads `kept best faces of N` instead of "sharpest".

### B4. Fast scroll · ask 7 · partly
- Done: (b) no lazy load, no fade at rest; (c) the window leans 2 viewports ahead.
- **Open (a):** `readOne` makes a separate 720 × 480 tile `src` (JPEG 0.9, never upscaled). Measuring stays on 360 px. This touches readOne's hash, so it is agreed with the app first.

### B5. Read while culling · ask 8 · partly
- Done: (a) keep the reader's place, now reported as `readEnd`.
- **Open (b):** when a saved session is restored at the end of a read, merge it. Decisions made during this read win.
- **Open (c):** while the reader scrolls, `grow` waits 1.5 s (today 450 ms). No row-height animation for rows off screen, and no tile fade for rows already on screen.

### B6. Tab focus order · ask 6 · open
- Proposal: Tab walks the buttons (steps, pill, footer buttons). Letters act only while the grid has focus. A grid focus ring sits on the scroll box.

### B7. Side-by-side compare from pass 2 · deferred · open
- Large view ⇧Space: two frames 50/50 with independent zoom and a shared ⏎/R. Design not started.

## C. Edit

### C1. RAW 9 region facts · Prompt 1 addendum C · open
- When `luminaEditStats(s)` has `s.facts.source==='raw9-region'`, use its sharpness and clipping for the strip tile's words (`soft`, `clipped`). The facts line adds `raw 9 · region`.

### C2. Export JPEGs with the look · Prompt 1 §7 · open
- **Save card** (`[data-lumina=handoff-card]`), under the sidecar line:
  - checkbox row `Also export JPEGs with the look`;
  - when on: a segmented control `2048 px · Full size` and a folder line `JPEG/ next to the sidecars`.
- **Button:** `⌘⏎ Save 88 picks + JPEGs`.
- **Call:** `writeInto(files,'jpeg')` with `{name:'JPEG/DSC….jpg', look:{src:rel, look, px}}`.
- **Result:** `88 JPEGs · JPEG/ · rendered with RAW 9`.
- **Browser:** `JPEG export needs the app`.

### C3. Colour NR / Detail / Moiré sliders · Prompt 1 §4/D · open
- `RAW9_HIDE` is wired, but Edit has no such sliders. Either add them in Effects ▸ Detail (hidden while `raw9`), or declare them not needed.

## D. Save

### D1. Sidecar changed after the open · Prompt 5 · open
- Save notes (`[data-lumina=handoff-how]`) get a line `3 sidecars changed since you opened · their edits are kept, only the rating changes`, from `lumina.sidecars()`.
- The result lists `DSC… · changed on disk` for refusals.

### D2. Unreadable sidecar / name too long · Prompt 10 · open
- Result rows `DSC… · sidecar can't be read · left as it is` and `… · name too long to save`.

### D3. Export cut short · Prompt 8 · open
- When `lumina.cutShort` is set, `div[data-lumina=cut-short]` appears in Open:
  - text `An earlier export to <folder> stopped part-way · N files finished`;
  - buttons `Show in Finder` and `Clean up`.

### D4. Save card + sidecar refresh · v0.02 "4a–d" · open
- Carried from v0.02; spec in DESIGN-ASKS 4a–d.

### D5. Open-step states · v0.02 "5a–f" · open
- Carried from v0.02.

## E. Menus and alerts (MENUS.md only)
- **Prompt 4:** alert words `Lumina keeps stopping` / `It stopped again after reloading 3 times in a minute. Your decisions so far are saved.` with buttons `Try Again · Quit`.
- **Prompt 7:**
  - Help menu: `Lumina FAQ · Keyboard Shortcuts ? · Acknowledgements · Contact`;
  - `luminaCommand('acknowledgements')` opens a sheet `[data-lumina=acks]` with the THIRD-PARTY-NOTICES text, monospace 11, scrolling.
- **Ask 5:** menu titles for plain keys (`Keep P`). Confirm the wording.

## F. Contract questions (CHANGES-v0.03 Q1, Q2)
- `luminaEditImage` / `luminaEditRect` semantics.
- `pw`/`ph` on Edit's photo records, so `roi` comes in image px.
