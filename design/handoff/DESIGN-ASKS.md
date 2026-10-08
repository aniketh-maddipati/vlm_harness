# Design asks for the next handoff (after v8 / Edit v21)

> **Status after the Prompts 20–24 handoff (2026-10-08).** The app now ships `Lumina Sets v12.dc.html`
> with `Lumina Edit v23.dc.html`. v11 / v22 and the v8 / v21 names below are history. v0.03 to v0.05 answered asks
> 1 to 11 (CHANGES-v0.03), Prompts 12 to 14, and REMAINING-v0.03's A1, A2, A4, B1, B2, B3 F,
> B5 b, C2, D1 A, D2, D3 and E. Still open before release: A3 (the call that brings sessions over
> from before the sandbox) and D1 B / C (`lumina.sidecars` refresh). After release: B3 B / C / G,
> B4 a, B5 c, B6, B7, C1, C3, D4, D5. `design/handoff/lumina-cull/REMAINING-v0.03.md` is the
> element-by-element list; new asks reach its next revision through a prompt written here.
>
> **New for the next revision (Edit v22 on the native canvas).** The canvas is drawn above the web
> view, so anything Edit draws inside `[data-lumina=canvas]` is hidden under it unless the app knows
> to leave it see-through. Plumbing finds the small pieces itself (the zoom pill, the loading chip),
> but not the crop tool: its frame and dimming cover the whole box. Ask: while crop (or any tool
> drawn over the whole photo) is on, either send `lumina.canvasRect(null)` and show the embedded
> preview, or report the regions to keep visible with the rect (`{x, y, w, h, dpr, holes: [...]}`).

Status: open. Paste the prompt below into Claude Design, download the new handoff zip, then run
`bash Scripts/sets_sync_design.sh "<zip>"` (add `--record` once you've approved the new look).

The Mac app ships `Lumina Sets v8.dc.html` (with `Lumina Edit v21.dc.html` mounted inside it) byte for byte. The asks below were written against v5; v0.02 answered some (8: the read keeps the reader's place; the window chrome, decision 9a). Prompt 12 is new with v8. Anything visible has to change in the
design and then be synced here. These asks were found while fitting `plumbing.js` to v5
(2026-09-29), by `Tests/web/plumbing-harness.mjs` and `Tests/web/parity.mjs`. The WKWebView probe
runs are still to come.

**Answered by v5** (the v3-era asks 1–8, 10): the `window.lumina` contract, no sample data in
the app, empty states for Open, Cull and Save, data from `lumina.card` on the card panel, the demo layer gone
in the app, working files in Save, the body serial and `SequenceNumber` read by `parseHead`,
missing previews kept as photos (`nopv`), and rows drawn only near the viewport. The Edit step and
its story images are gone. Ask 9 (window chrome) is still open, and ask 11 moved to #2 below.

---

## Prompt to paste into Claude Design

> Update `Lumina Sets v5.dc.html` for the Mac app. Keep the look, keys and wording otherwise
> unchanged, and keep the browser behaviour as it is.
>
> **1. Working files size when Save opens.** In the app, Save shows "Remove Lumina's working
> files (N MB)" only after a save, because `s.ex.wf` is set only in `runExport`. Call
> `lumina.workingFiles()` when the Save step opens (and after "Remove"), and show the row as soon
> as the size is known. The app does this for you today from `plumbing.js`; with it in the page,
> that code can go.
>
> **2. One sidecar per RAW when both `DSC….xmp` and `DSC….XMP` exist** (possible on a
> case-sensitive disk). `onDir` keeps whichever file finishes reading last, which is a race. Use the
> lower-case `.xmp` (Adobe's name, and the one new sidecars get), otherwise the first by name.
> Never read or write the other one. The app's native read already does this.
>
> **3. Unsaved keepers, from the page.** Quit asks when keepers aren't saved (MENUS.md). The app
> works this out itself (the kept list against the last successful save). Please expose
> `window.luminaUnsaved()` → the number of keepers whose sidecars aren't written, so the rule lives
> with the Save screen's own "saved" state (today `ex.result` resets on any keeper change but is
> lost on reopen).
>
> **4. Window chrome (was ask 9).** The Mac window has a standard title bar, so the page area is
> about 28 px shorter than the window (1440 × 872 in 1440 × 900). Tell us whether you want a full-bleed page. If so, the top bar
> needs about 80 px clear on the left for the window buttons.
>
> **5. Menu shortcuts for plain keys.** The menu bar shows ⌘ shortcuts natively. Plain keys
> (P, F, ⇧P, ⇧F, ⏎, esc, Space, Z, ⇧U, −, +, H, ?) can't be bound in a Mac menu without taking the
> key away from the page (hold-to-show and key repeat stop working), so the app writes them into the
> item title ("Keep  P"). If you want a different wording in the menu, list it in MENUS.md.
>
> **6. Tab focus order** (CHANGES-v4-beta "Known, left as-is"). Still no rule. The proposal stands:
> Tab moves through buttons; letters act only while the grid has focus.
>
> **7. Fast scrolling in Cull.** Scrolling fast shows tiles popping in and soft thumbnails. Please:
> (a) **Thumbnail size.** `readOne` keeps the 360 px measuring bitmap as the tile image (JPEG 0.82),
> but the largest tile is 216 × 1.5 = 324 × 216 CSS px, i.e. 648 × 432 on a Retina screen: up to
> 1.8× magnified. Keep measuring on the 360 px bitmap (so keeps, stacks and sharpest don't
> change) and give `src` a separate image covering 720 × 480 (never upscaled, resized at high
> quality, JPEG 0.9). The app does this today: the Mac makes it (`/media/thumb`) and `plumbing.js`
> uses it. In the browser, make it in `readOne` the same way (the app keeps supplying its own).
> (b) **No fade for a ready image.** Tile `<img>`s start at `opacity:0` and fade in over 180 ms on
> `onLoad`, and use `loading="lazy"`. On a fast scroll every newly mounted row blinks, even when its
> thumbnail is already decoded. Drop `loading="lazy"` (rows are already windowed at ±700 px), and show
> an image that is `complete` on mount at full opacity; keep the fade only for thumbnails that
> arrive while you look (during a read).
> (c) **Render window follows the scroll.** `onScroll` mounts rows within ±700 px of the viewport.
> Make it lean with the scroll direction (e.g. 700 px behind, 2 viewports ahead) so a fling lands
> on rows that are already mounted.
>
> **8. Culling while a card is still being read.** Rows appear while a card reads, and people start
> culling straight away (a user's recording: a 775-photo card at ~45 photos/s, scrolled and kept
> during the read). Please:
> (a) **Don't jump when the read ends.** `onDir` ends with `cur: order[0]` and `land()`, which
> smooth-scrolls from wherever the reader is back to the first photo — about 2 s of blank, moving
> grid across hundreds of rows, and the reader loses their place. If the reader has moved, kept or
> scrolled during the read, keep `cur` and the scroll position as they are. The app does this in
> `plumbing.js` today.
> (b) **Keep decisions made during the read.** When the card has a saved session, the restore
> replaces them; merge instead (decisions made during this read win). The app does this today.
> (c) **Calmer growth.** Every refresh rebuilds and re-renders the whole grid; rows re-split as bursts
> become stacks, row heights animate (180 ms) and each new tile fades in. While the reader is
> scrolling, add rows less often (the app waits 1.5 s instead of 400 ms), don't animate row heights
> for rows that are off screen, and don't fade in tiles for rows that were already on screen.
>
> **10. Say so while a folder opens.** Between choosing a folder and the first photo being read the
> page shows nothing: no word, no progress. That wait is the disk listing the folder, and it is
> not always short. Measured in the app (`probe.sh readspeed`, 2026-10-01): under 0.1 s on the
> internal disk, 0.4–3.6 s on a USB disk, and **13.9 s the first time a folder is opened after
> that disk is mounted** (the same wait a freshly inserted card or a sleeping disk gives). For
> those seconds the app looks as if the click did nothing. Please:
> (a) **An opening state.** Define `window.luminaOpening(info)`: the app calls it with
> `{name, onCard}` the moment a folder is chosen (picker, drop, Open Recent, "Cull this card"),
> and with `null` when the listing arrives, access is refused, or the open is cancelled. While it
> is set, Open says what is happening in the place the read's progress appears a moment later,
> e.g. `Opening <name>…`, so the two read as one sequence. In the browser nothing calls it (the
> folder input answers at once).
> (b) **Not for fast opens.** Show it only once the wait has lasted about 400 ms, so an open on
> the internal disk doesn't flash a word.
> (c) **A long wait says why.** After about 3 s add a second, quieter line, e.g. `the disk is
> waking up`, so 14 s doesn't read as a hang. No spinner that implies progress: there is no
> count until the listing returns.
> (d) **Keys stay alive.** `Esc` leaves the opening state (the app drops the listing's result
> when it arrives) and `⌘O` can choose another folder; today nothing can be done until the
> listing returns.
>
> **11. Cull rows wobble while scrolling.** `sc-for` keys its items by position, and `rows` is the
> slice of the layout's rows around the viewport. Each time the first mounted row changes, every
> row's element is handed the next row's content: its `height` animates 180 ms to that row's
> height (so do the tiles' width and height), and its `<img>`s swap `src` in place. On a shoot whose
> rows differ in height the grid shows clipped second lines, empty bands and the neighbour's photos
> for a few frames, every time a row enters or leaves. Measured in the app on 408 photos
> (`probe.sh scroll`, 1440 × 900 and 2560 × 1440): 50 to 85 % of the rows on screen are drawn at
> another height or place than `layout()` gives them while scrolling, up to 224 px off. Please:
> (a) **A row keeps its element.** Key the rows by `r.id` (and a row's tiles by the photo or stack
> they show), so a row that stays mounted is not touched when the window moves, and only the rows
> entering or leaving mount. The app does this today from `plumbing.js` (it gives the row items
> their id as key); with it the same passes measure 0 %.
> (b) **Height animates only for a reason.** Keep `transition:height` for what it is for (a stack
> opening, the tile size changing), never for a row arriving.
> (c) With (a), every row entering is a new element, so 7 (b) and (c) matter more: the app also
> loads existing thumbnails at once, shows them without the fade unless a read is running and the
> grid is at rest, and lets the mounted rows lead the scroll by 0.4 s of travel (at most two
> viewports ahead, back to ±700 px at rest). Blank tiles on screen while scrolling: 4 to 15 %
> before, 0 % after.

## Prompt 1 — the Edit step (paste into Claude Design)

> Update `Lumina Sets v5.dc.html` (+ `support.js`, `lumina-core-v4.js`, `lumina-v4-data.js`,
> `lumina-selftest.js`, PARITY.md, GRAMMAR.md, MENUS.md, CHANGES) to add the **Edit** step between Cull
> and Save. Keep every existing screen, key, token and wording exactly as it is; the app ships these
> files byte for byte and compares every screen at 0 px, so change only what this prompt names.
> Read PARITY.md and GRAMMAR.md first and stay inside their tokens (colours, radii, motion, type).
>
> ### 1. Where Edit lives
> - Segmented control: **Open · Cull · Edit · Save**, four segments of 88 × 24 (the control widens by
>   one segment, stays centred). ⌘1 ⌘2 ⌘3 ⌘4 in that order; `window.luminaCommand('stepEdit')`
>   opens it; MENUS.md View gains "Edit ⌘3" and Save moves to ⌘4. Tab moves Cull → Edit → Save.
> - Edit opens on the current photo (the cursor's photo; a closed stack opens at its sharpest
>   frame). Empty state when the shoot has no photos: "Nothing to edit yet", one sentence, gold
>   "Back to Cull ⌘2". Edit works on any photo, kept or not; a "keepers only" toggle in the filmstrip
>   (off by default) narrows the strip.
> - Layout at 1440 × 872 (the app's page area; also lay it out at 1920 × 1052): left, the **canvas**
>   (photo at its aspect on the loupe surround `#3A3835`, 20 padding, same hairline + shadow as the
>   large view, a "100%" chip top-right while Z is held); right, a **panel** 300 wide (raised `#2A2927`)
>   with the slider groups; bottom, the **filmstrip** 92 high (the current row's frames, 48 × 32
>   tiles, current 66 × 44 with the ring, same rules as the large view's nav strip); under the canvas,
>   one **facts line** 12.5 tertiary. Key bar and toolbar unchanged.
>
> ### 2. The look string is the only edit state
> Every edit of a photo is one string, and the string is the contract with the Mac (the app renders
> it natively; the design's own approximation is only for the browser prototype):
>
> ```
> ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0 [bw:1] [crop:x,y,w,h/r]
> ```
> - Keys and ranges: `ev` −5.00…+5.00 step 0.05 · `wb` Kelvin 2000…50000 on a log scale / tint
>   −150…+150 · `con hl sh wh bl vib sat clr vig` −100…+100 step 1 · `shp` 0…150 · `bw:1` black and
>   white · `crop:x,y,w,h/r` fractions of the frame (0…1, y from the top) and a straighten angle in
>   degrees (±45). A missing key is its reset value; `wb` missing means "as shot"; `crop` missing means
>   the whole frame. Canonical text: this key order, `ev` with two decimals and a sign, integers with a
>   sign (`0` unsigned), `shp` unsigned, `wb` as `K/tint`. `""` is the neutral look.
> - `LuminaCore` gains `look.parse(s) → object`, `look.format(o) → canonical string`, `look.clamp`,
>   `look.isNeutral`, `look.merge(base, over)` (per-key override), and `look.fromAuto(photo)`: the
>   existing Auto (V / A keys) expressed as a look string (exposure, contrast, highlights, shadows,
>   white balance) so Auto and manual edits are the same thing. Add fixtures for all of them to
>   `lumina-core-v4.fixtures.json` and cases to `lumina-core-v4.test.mjs`.
> - State: `state.look` = `{ [photoId]: lookString }` and `state.rowLook` = `{ [rowId]: lookString }`.
>   A photo's effective look is `merge(rowLook[row], look[photo])`. "Apply to row" (⇧A) copies the
>   photo's look into `rowLook` and clears the photos' overrides in that row; "Reset" clears the
>   photo's override; "Reset all" clears both. Looks are **never written to XMP sidecars**: Save stays
>   ratings only. The app persists `look` and `rowLook` in its session; in the browser keep them in
>   the same localStorage session object the other decisions use.
>
> ### 3. Preview: the Mac renders, the page presents
> - The page never renders pixels itself in the app. It asks the app for previews through one call:
>   `const url = window.lumina.preview(rel, look, px, seq)`; when it returns a URL, set it as the
>   canvas image's `src` (double-buffer: two stacked `<img>`s, swap on `decode()`, never show a blank
>   frame); when it returns `null`, the app is presenting the pixels itself on a native canvas
>   overlay and the page draws only the frame chrome (surround, hairline, chips, facts) and keeps the
>   canvas area transparent. `rel` is the photo's path inside the shoot (`realInfo.name + '/' +
>   file`, the same value `media` requests use), `px` the long edge in device pixels, `seq` an
>   increasing integer per request.
> - **Latest wins.** While a slider moves, the page keeps only the newest look string and asks at most
>   once per animation frame (`requestAnimationFrame`, never `setTimeout`). A response older than the
>   last presented `seq` is ignored (the app answers HTTP 409 for superseded requests; treat a 409 or
>   an `onerror` as "ignore"). Never queue.
> - Tell the app what the canvas is doing, through plumbing-provided calls (all optional; guard with
>   `typeof … === 'function'` so the browser prototype runs without them):
>   - `window.lumina.canvasRect({x, y, w, h, dpr})` on Edit open, layout, resize, scroll and zoom, in
>     CSS px relative to the viewport; `window.lumina.canvasRect(null)` whenever Edit is not the active
>     step or a large view / sheet covers the canvas.
>   - `window.lumina.drag('start')` on pointer-down / key-repeat start on any slider,
>     `window.lumina.drag('end')` on release / key up.
>   - `window.lumina.roi({x, y, w, h})` in normalised frame coordinates while Z (100 %) is held and
>     when the region pans; `window.lumina.roi(null)` when zoom ends.
> - Hooks the app calls on the page (define them on `window` when Edit mounts, remove on unmount):
>   - `window.luminaPresented(seq)`: the app has put this request on screen. Use it to clear the
>     "rendering…" state; show that word (12.5 tertiary, in the facts line) only if the newest request
>     has not been presented within 120 ms.
>   - `window.luminaHistogram({seq, r, g, b, clipHi, clipLo})`: 256-bin arrays and clipped-pixel
>     fractions, computed by the app on rest renders only. Draw the histogram 300 × 72 at the top of
>     the panel (RGB overlaid, `#EFECE6` at 0.5 alpha per channel, luma in tertiary), and, when the
>     clipping toggle is on (J), tint clipped highlights `#FFB4A2` and shadows `#9ED7B0` on the
>     canvas via a stacked `<canvas>` that the app fills; the page draws only the toggle state.
>   - `window.luminaFacts({canvas: 'native' | 'image', raw9: true | false, decoder: '8' | '9',
>     note: string | null})`: appended to the facts line as `canvas: native · raw 9: yes` plus the
>     note (e.g. `raw 9 · region`, `refining…`, `raw 9 · slowed by thermal state`, `decoder 8 pinned ·
>     update shoot`). The facts line reads: `DSC03311 · ILCE-7M4 · 35 mm · 1/250 · f/2.8 · ISO 400 ·
>     5200 K as shot` then the app's part.
> - Browser prototype: with no `window.lumina.preview`, approximate the look on the embedded JPEG
>   with CSS filters (`brightness`, `contrast`, `saturate`, `sepia` / `hue-rotate` for WB, a subtle
>   `drop-shadow`-free vignette via a radial gradient overlay) through `LuminaCore.look.cssFilter(look)`;
>   label the facts line `canvas: css` so nobody mistakes it for the real render.
>
> ### 4. Sliders and the panel
> Groups, top to bottom, each collapsible (header 26 high, chevron rotates 90°, state remembered):
> - **Light**: Exposure (stops, ±5, step 0.05, shown `+0.70`), White balance (Temperature
>   2000–50000 K on a log slider with a `K` suffix and an "as shot" reset dot; Tint ±150), Contrast,
>   Highlights, Shadows, Whites, Blacks.
> - **Colour**: Vibrance, Saturation, B&W (toggle; when on, Vibrance and Saturation grey out).
> - **Presence**: Clarity, Sharpening (0–150), Noise (Luminance NR 0–100, sent as `nr:`; hide the row
>   when `luminaFacts.raw9` is true and show it when false; keep the key out of the look string when 0).
> - **Effects**: Vignette (±100).
> - **Crop & straighten**: a crop button that shows handles on the canvas (thirds grid while
>   dragging), aspect presets (free · 3:2 · 4:5 · 1:1 · 16:9), a straighten slider ±45° with a
>   level grid, "Done" / "Reset crop".
> - Slider anatomy: label 12.5 left, value 12.5 tabular right (editable on click: type a number, ⏎
>   commits, esc cancels), track 4 high full width, `rgba(239,236,230,0.16)`, fill from the zero
>   point in `#B8B3AB` (gold `#FFD27A` while dragging or focused), thumb 14 circle with the same
>   hairline as buttons. Bipolar sliders have a centre notch. Double-click the label = reset that
>   slider; ⌥-click = reset the group; the value flashes 160 ms on reset.
> - Keyboard: a slider takes focus with Tab; ← → nudge one step, ⇧ ten steps, ⌥ a tenth (`ev`
>   only), Home/End to the ends, ⌫ resets. Focused slider name in the key bar. The whole panel is
>   reachable by keyboard; ARIA `role="slider"` with `aria-valuenow/min/max/valuetext` on each.
> - Interaction quality (this is the part the app measures, so please be exact):
>   - A drag updates *only* the slider's own DOM (value text, fill, thumb via `transform`) and the
>     look string; nothing else re-renders during a drag. Commit to React state on release, or at
>     most once per animation frame while dragging, never per pointer event.
>   - Emit `window.lumina.preview` at most once per frame, with the newest values (coalesce).
>   - No layout reads inside the pointer-move handler; cache the track rect on pointer-down.
>   - `pointer-events` capture on the thumb so fast drags don't drop out; touch and trackpad fine.
>   - Thumb and fill animate only on keyboard steps (120 ms), never during a drag; reduced motion off.
>   - No `content-visibility`, no filters on the canvas frame (the app compares screens at 0 px).
>
> ### 5. Keys in Edit (add to GRAMMAR.md and the ? sheet under "Edit")
> ```
> ← →         previous / next photo in the strip (⇧ stays inside the stack, as in Cull)
> ↑ ↓         previous / next row
> P R F       keep / un-keep / flag the photo shown (as everywhere)
> \ hold      before / after (neutral look while held; the fill dims)
> ⇧A          apply this photo's look to the whole row
> ⌘⇧C ⌘⇧V    copy / paste the look
> ⌫ (on a slider)  reset it · ⌥⌫ reset all sliders of this photo
> V           Auto look (LuminaCore.look.fromAuto), A hold compares as today
> J           clipping overlay on / off
> C           crop mode · ⏎ done · esc cancel
> Z hold      100 % at the region under the cursor · drag pans · same region across the stack
> Space       large view of the canvas without the panel (toggle), same as Cull's large view
> Tab         next step (Save)
> ```
> Q / ⌘Z undo covers every look change as one step per slider release.
>
> ### 6. Filmstrip, facts and status
> - Strip: current row's frames (stack frames when a stack is open), tile states as in Cull (kept ✓,
>   flag chip, sharpest ring); a photo with a look shows a 6 px gold dot bottom-right; a row with a
>   `rowLook` shows the dot on the row label at the strip's left ("09:25 · row look").
> - Facts line as in §3. While the app is rendering past 120 ms: `rendering…` at the right end.
> - Footer messages (1.2 s, sentence case): "Look applied to 37 photos", "Look copied", "Reset",
>   "Auto: +0.35 ev, −18 highlights".
>
> ### 7. Export with the look (Save step)
> - Save gains one row under the sidecar line: a checkbox "Also export JPEGs with the look" and, when
>   on, a size segmented control "2048 px · Full size" and a folder line ("JPEG/ next to the
>   sidecars"). The button reads "⌘⏎ Save 88 keepers + JPEGs".
> - The files list passed to `writeInto(files, 'xmp')` is unchanged; JPEGs go through a second call
>   `writeInto(files, 'jpeg')` where each file is `{ name: 'JPEG/DSC03311.jpg', look: { src: rel,
>   look: lookString, px: 2048 | null } }` (`null` = full size). The app renders them natively through
>   the same pipeline as the preview; in the browser, skip the JPEG call and say "JPEG export needs
>   the app". Sidecars stay ratings only; the look string is never in XMP.
> - The result block gains "88 JPEGs · JPEG/" and lists the decoder the app names in
>   `writeInto`'s result (`decoder: 'RAW 9'`), e.g. "rendered with RAW 9".
>
> ### 8. Selftest, docs, parity
> - `?selftest` gains: look parse ⇄ format round trip on the roadmap example; latest-wins (100 slider
>   events in one frame produce one preview request); a 409 never replaces a newer presented image;
>   Edit's keys; the filmstrip follows ← →.
> - PARITY.md gains an "Edit" section in the same checklist style (measure everything at 1440 × 900).
>   CHANGES notes the new step; MENUS.md the new items and ⌘3/⌘4 shift; README's step list.
> - `onDir` and `readOne` must not change (the app checks their hash); `writeInto('xmp')` payloads
>   must not change.
> - Add Edit screens to the screen list the app captures (`screens-1440`, `screens-1920`): Edit on a
>   photo with a look, Edit with the panel scrolled to Effects, crop mode, the empty state.

### How Prompt 1 is checked once its handoff lands

- The look grammar: `LookStringTests` (Swift) and `lumina-core-v4.test.mjs` (page) must agree on the roadmap example and on clamping; `Tests/web/plumbing-harness.mjs` round-trips `look` / `rowLook` through the session.
- Preview contract: `app-plumbing-contract` checks `window.lumina.preview`, `canvasRect`, `drag`, `roi` are called with the shapes above and that `luminaPresented` / `luminaHistogram` / `luminaFacts` exist while Edit is mounted; `probe.sh edit` measures the slider path (see the canvas addendum).
- Export: `app-smoke` saves keepers + JPEGs; the JPEG bytes equal `lumina-render render --look <same string>` for the same file (`SetsLookExport` and `lumina-render` share `LookPipeline`).
- Screens: the four Edit screens join `screens-1440` / `screens-1920` and the app twins at 0 px.

## Addendum to Prompt 1 — the native canvas and RAW 9 (paste after Prompt 1)

> The app now draws the Edit picture itself (a Metal view laid over the canvas box; §3's
> `window.lumina.preview` returns `null` there) and refines the 100 % region with Apple's RAW 9
> decoder where the Mac has it. Everything in §3 stands; four small additions:
>
> **A. The canvas box.** `window.lumina.canvasRect({x, y, w, h, dpr})` is the canvas *box* (the
> surround's inner rect); the app letterboxes the photo inside it at its aspect, exactly where your
> own `<img>` would sit. Keep the box transparent in the app (`luminaFacts.canvas === 'native'`)
> and draw the surround, hairline, chips and crop handles over it as before.
>
> **B. The update-shoot offer.** When `luminaFacts.note` is `decoder 8 pinned · update shoot`, the
> words "update shoot" are a link: on click call `window.lumina.edit.updateDecoder()`, which moves
> the shoot's pinned decoder to the newest one and re-renders (the facts update through
> `luminaFacts`). Until then the shoot keeps rendering with the version it was opened with, on purpose.
>
> **C. Facts from the model.** Besides `luminaHistogram`, define `window.luminaEditStats(stats)`:
> after a rest render `stats.source` is `'jpeg'` or `'raw9-region'`, and while the 100 % region has
> been refined `stats.facts = {sharpness, clipHi, clipLo, source: 'raw9-region'}`. When
> `stats.facts.source === 'raw9-region'`, prefer its sharpness and clipping to the embedded JPEG's
> for that tile's flag words (`soft`, `clipped`) in the filmstrip and Cull, and show `raw 9 · region`
> next to them in the facts line. `stats.histogram` carries the same bins as `luminaHistogram`.
>
> **D. Noise.** As §4 says, Luminance NR goes into the look string as `nr:35`; it re-develops the
> base, so treat it as a keystroke slider (commit on release, no per-frame preview). While
> `luminaFacts.raw9` is true hide Colour NR, Detail and Moiré (RAW 9 ignores them); show them when
> it is false.

> **9. Save stays off for anything `lumina.readingCard` covers.** `onCard()` is
> `lumina.card && lumina.readingCard`, so the "copy to disk first" state needs a card in the panel.
> Two cases fall through, and in both the Save step shows the normal "Save N keepers" button, ⌘⏎
> runs, and the result reads "0 saved · N failed" with every keeper listed as "on the card":
> (a) the shoot is on a removable volume that is not a camera card (a USB stick or SD card without a
> DCIM folder): `lumina.readingCard` is true, `lumina.card` is null;
> (b) the card was pulled after its shoot was read: `luminaCardGone(true)` has been called,
> `lumina.card` is null, `lumina.readingCard` is still true.
> Please make `onCard()` true whenever `lumina.readingCard` is true (SAFETY.md 4: "Save stays disabled
> with the copy-first message" for any mounted removable volume). For (b), while `gone` is set, say
> that the card is out instead (the Cull notice's wording is fine). Nothing is written in either case
> today; this is only about what Save offers.

## Prompt 2 — culling logic, from the culling eval (paste into Claude Design)

Found by `Tools/culleval` (2026-09-30) on 4,938 real α7 III frames: 80 camera bursts (341 frames
shot in a drive mode), 500 bursts by hand, six shoots with known keeps (1,468 frames, 546 kept;
five of them complete). The measures ran in headless Chromium on the page's own 360 px bitmap.
Numbers: `make culleval`.

> Update `lumina-core-v4.js` (and its fixtures). No visible change is asked for; keep the page's
> look, keys and wording as they are.
>
> **A. `sonyMN` reads nothing from a real ARW.** On all 4,938 frames `releaseMode2`, `seqImage`,
> `seqLength` and `focusMode` came back null, so real camera bursts fall through to the dHash rule
> and are split: 15 of 80 came out as one stack (pair recall 14 %). With the camera's sequence
> numbers filled in, the same `buildShoot` gets 74 of 80 (pair recall 95 %). Two causes:
> (1) `sonyMN` returns unless the MakerNote starts with `SONY` and reads its IFD at +12. That
> header exists in Sony JPEGs; in an ARW the MakerNote (0x927C) starts directly with the IFD
> (entry count at the MakerNote offset; value offsets from the TIFF start, as you already read
> them). Accept both: +12 after a `SONY` header, +0 otherwise.
> (2) The 0x9400 layout check `[0x23,0x24,0x26,0x28,0x31,0x32,0x33].includes(d[0])` tests the
> deciphered byte. The layout byte is the first byte as stored (α7 III: stored 0x26, deciphered
> 0xd7), so test `u8[p]` before deciphering.
> Then make the two sources agree: the 0x9400 SequenceImageNumber (offset 0x12) counts from 0
> (exiftool adds 1), the plain 0xB04A SequenceNumber counts from 1 with 0 for a single frame.
> Expected on an α7 III: a single frame → `seqImage` null, `releaseMode2` 0, `seqLength` 1; the
> third frame of a five-frame burst → `seqImage` 3, `releaseMode2` 1, `seqLength` 5.
> Please add a `parseHead` fixture with real MakerNote bytes (both layouts); today's stack
> fixtures start from already-parsed numbers, which is how this went unseen.
>
> **B. The dHash is too noisy to carry the stack rule.** `measure` makes the 9 × 8 hash with one
> `drawImage(bmp,0,0,9,8)` from the 360 px bitmap, which samples a few pixels per cell instead of
> averaging the cell. Measured distances between consecutive frames (64 bits, on 4,002 of the frames):
> inside a camera burst: median 12, only 20 % ≤ 6 (the stack threshold), 2 % ≥ 28 (the "always
> split" threshold); same framing ≤ 2 s apart by hand: median 21, 9 % ≤ 6, 23 % ≥ 28; frames more
> than 5 minutes apart: median 30. So the hash barely separates a burst from a new scene.
> Please average each cell (box means over the luminance array `g` that `measure` already has, or
> halve the bitmap step by step down to 9 × 8), then set the two thresholds from real frames, and
> do not let "dHash ≥ 28 always splits" cut frames whose sequence numbers say they are one burst.
> `Tools/culleval` re-measures this after the sync.
>
> **C. Retakes are left as singles (revised 2026-10-01 from hand labels, see below).** This
> photographer mostly shoots single frames and repeats: 500 runs of the same framing ≤ 2 s apart
> against 80 camera bursts. Lumina stacks 7 % of those pairs. In 197 of 199 runs of tries that
> held a keeper, Lumina showed the tries as separate photos, and 229 of the 582 frames it suggested
> and the photographer rejected were one of several tries where another try was kept.
> The first version of this ask proposed "within 2 s, same lens, hashes agree". The photographer
> has since marked 277 consecutive pairs by eye ("would you put these two in one stack and choose
> between them?"), and time turns out to be a weak sign of a retake: the two frames are the same
> picture in 83 % of pairs at most 2 s apart, 63 % at 2–10 s, 43 % at 10–60 s and 11 % beyond.
> Against those labels:
>
> | Stack two consecutive frames when | Right when it stacks | Retakes it finds |
> |---|---:|---:|
> | ≤ 2 s, same lens / focal length / orientation, dHash ≤ 20 (the first version of this ask) | 95 % | 14 % |
> | ≤ 4 s, nothing else | 78 % | 43 % |
> | ≤ 60 s, dHash ≤ 20 | 87 % | 40 % |
> | ≤ 60 s, dHash ≤ 24 | 84 % | 58 % |
> | ≤ 60 s, same lens / focal length / orientation, the app's distance ≤ 0.35 | 93 % (88–97) | 59 % (51–67) |
>
> No dHash threshold reaches the last row, so the measure has to come from the app. Please:
> (1) **Take a distance from the app.** `window.lumina.near(pathA, pathB)` resolves to a number
> (0 = the same image, about 1 = unrelated) or `null` (in the browser, and until the app has
> measured both frames: it measures behind the read, so a value can arrive after the photo is on
> screen). Call it for each photo and the photo before it in capture order and keep the answer on
> the later frame's record (`near`), where `buildShoot` can read it like `dhash`.
> `window.lumina.nearLimit` is the threshold (0.35 today). It comes from the app because it
> belongs to the app's measure, which can change with macOS; please don't write the number into
> the page.
> (2) **The rule.** Two consecutive frames at most 60 s apart with the same lens, focal length
> (±5 %) and orientation are one stack when `near ≤ nearLimit`. Where `near` is `null`, fall back
> to the dHash rule you have after B. Camera bursts (A) stay stacked by their sequence numbers
> whatever the distance says. No 2 s or 4 s limit: it would leave out more than half the retakes.
> (3) **One kind of stack.** A stack of retakes behaves as a burst does (open, rank, keep one,
> `⌥←→` skips it, B splits and ⇧B merges, manual cuts win over the rule). If you want the badge
> or header to say which kind it is, the wording is yours.
> (4) **Calm arrival.** `near` values arrive while rows are already on screen. Regroup with the
> same pacing ask 8 (c) asks for, and never regroup the row the cursor is in while a key is held.
> Known limit, nothing asked: when one of the two frames is a miss (blurred, a blink, something
> in the way) the distance grows, and the rule stacks 9 of the 23 such pairs the photographer
> marked as the same picture (39 %, against 59 % overall). The missed frame is the one most likely
> to be left beside its stack. That is open on the app side; B (split) and ⇧B (merge) cover it
> by hand meanwhile.
>
> **D. `blown` fires on bright scenes, and it removes keepers from the suggested keeps.** The rule
> is "more than 2 % of pixels at 250 or above in all three channels". On a bright indoor event it
> flagged 296 of 509 frames, 173 of them among the photographer's 309 keepers: flagged frames were
> kept as often as unflagged ones, so there the flag says nothing, and because a blown single is
> never suggested, the suggested keeps found only 37 % of the real keeps (95 % and 89 % on the
> two shoots where `blown` is rare). Of 223 keepers that were not suggested, 186 were flagged
> blown and 35 soft. On a desert shoot it flagged 27 of 204 frames, 7 of its 61 keepers. Please make the flag relative
> to the shoot (a frame that clips much more than its neighbours in the same row, or the top few
> percent of the shoot) rather than a fixed 2 %, and keep a flagged single among the suggested keeps
> unless a cleaner frame of the same stack exists.
>
> **Not asked yet:** "sharpest" as the frame to keep agreed with the photographer in 37 of 94 groups
> of tries with one keeper (39 %; picking at random scores 37 %), and in none of the 10 groups of six
> or more. In Lumina's own stacks it agreed in 6 of 10. Sharpness alone is close to a coin toss
> between near-identical tries; what would do better (faces, eyes, expression) is a product
> decision, not a fix. `shake` (exposure longer than 2 / focal length) flagged 49 of 80 frames of
> an evening shoot, all 3 of its keepers among them; three keepers are too few to ask on.

## Prompt 2, second part — what Cull says about a frame (paste after Prompt 2)

A second eval, through the app (2026-10-01; now `Tools/culleval/culleval-app.mjs` and `Tools/culleval/signals`), follows up Prompt 2's "Not asked yet". It runs
`lumina-core` through the real app (the page and the native reader in the probe) on 1,854 photos
over 12 shooting days, scored against the 444 of them that were finished and exported from
Lightroom (a "pick": stricter than a keep), and it measures candidate signals on the Mac (Apple
Vision on the embedded preview). One photographer, one body: the numbers say which way to move,
not how far. Reports stay on the Mac (`~/LuminaEvidence/culling-eval`).

| What Cull says today | Rule in `lumina-core-v4.js` | Photos | Picks carrying it | Picked if said / if not |
|---|---|---:|---:|---:|
| `soft` (single frames) | sharpness in the bottom 12 % **of the shoot** | 14 % | 43 (10 %) | 16 % / 25 % |
| `shake` | exposure longer than 2 / focal length | 6 % | 27 (6 %) | 23 % / 24 % |
| `blown` | more than 2 % of pixels white | 13 % | 45 (10 %) | 19 % / 25 % (see D) |
| `dark` | mean luma under 0.08 | 0.4 % | 0 | 0 % / 24 % |

It agrees with Prompt 2 where they overlap: the sharpest frame of a row was a pick 38 % of the
time against 42 % by chance (Prompt 2: 39 % against 37 %), and the suggested keeps left out 24 %
of the picks, almost all of them frames carrying a flag word (D). It found only 19 stacks in
1,854 photos; that is A (the camera's drive data is not read), not how these shoots were taken,
so it says nothing about bursts. Frames at most 4 s apart inside a row cover 42 % of the photos,
and 56 % of the runs that hold a pick hold exactly one: the same picture as C, on other shoots.

> These follow A–D and, unlike them, change what the page **says** about a frame. They never
> hide, dim or skip a frame.
>
> **E. `soft` on a single frame is judged against its own stack, not the whole shoot.** Today a
> single frame is `soft` when its sharpness is in the bottom 12 % of the folder
> (`f.soft = f.sharp < 12`), so 12 % of every shoot is called soft however good it is, and one
> pick in ten carries the word. Once C stacks the tries at one picture, use the burst rule on
> them: `soft` when `focus < 0.45 ×` the sharpest frame of its stack. A frame with nothing to
> compare it with gets no `soft` word. Measured with runs of frames at most 4 s apart standing in
> for C's stacks: `soft` on 2 % of photos instead of 14 %, on 4 picks instead of 43, and a frame
> it names is picked 11 % of the time against 24 % (today: 16 % against 25 %). Drop `slight`
> (`f.sharp < 25`) from the data: the page never shows it and it predicts nothing (picked 27 %
> against 23 %).
>
> **F. Remove the `shake` word.** `exp > 2 / focal length` ignores stabilisation. Prompt 2 saw it
> flag 49 of 80 frames of an evening shoot with too few keepers to judge; here it names 118
> frames, 27 of them picks, and a frame it names is picked as often as the rest (23 % against
> 24 %). Keep the shutter speed in the facts line, where it is a fact rather than a verdict.
>
> **G. When there are faces, rank by the faces.** Prompt 2 leaves "what would do better than
> sharpness" open. Measured inside rows (pairs of a pick and a frame passed over): whole-frame
> sharpness puts the pick first 52 % of the time, a coin; the quality of the faces 63 % (interval
> 54–71 %, on the 33 rows with faces); sharpness on the largest face 61 %; smiles 60 %. Shooting
> order (the last try) says nothing. The page can't measure faces, so take it from the app:
> `window.lumina.measures(path)` resolves to `{faceQ: 0…1 | null, faces: n}` (null without
> faces, and always null in the browser). Where every frame of a stack has a `faceQ`, rank the
> stack by it and say `best faces` where the page says `sharpest` today (`kept best faces of
> N`); otherwise rank by sharpness as now. An ordering and a word, nothing else: a modest signal
> on one photographer's shoots.
>
> **H. `sugKeep` stays off the screen until D and E are in.** The page does not show the
> suggested keeps today. Leave it that way: as built they propose 69 % of the photos and still
> leave out 24 % of the picks.

## Prompt 3 — photos Lumina can't show, and camera clocks (paste into Claude Design)

Found by `probe.sh edge` and `ingest` on v5 (2026-10-01; the page's read and the app's read agree),
on the forged fixtures of `Tests/probe/EDGE-CASES.md` C1, C2 and C5:

- **Damaged files** (5 ARWs: one intact, one with its preview cut short, one with its preview
  zeroed, one cut inside the header, one empty). Open says `4 photos · 2 rows · 0 stacks · 1
  unreadable`. Two are grey tiles showing only the file number. The empty file has no tile. The
  header-only file sits alone in a row labelled `00:00`, and the next row reads `496917 h gap`.
  Import notes: `2 without an embedded preview`, `1 unreadable · see ? for the list`.
- **Clock moved 9 hours back mid-trip** (6 ARWs): two rows, the later photos first. Nothing on the
  page can shift a time.
- **Two bodies, clocks one minute apart** (6 ARWs): one row, A B A B A B. The import note says
  `2 bodies · … · check that the camera clocks match`, and that is all the photographer can do.

A photographer who opens 500 photos and sees 497 stops trusting the app, so A comes first.
C4 (a 10 fps burst) needs nothing new: it is Prompt 2 A and B.

> Update `Lumina Sets v5.dc.html` and `lumina-core-v4.js` (and its fixtures). Keep the look, keys
> and wording otherwise unchanged.
>
> **A. Every ARW in the folder gets a tile.**
> (1) **No preview** (`nopv`, today a grey tile with the file number): add a second line under the
> number, same type one step quieter: `no preview`. Large view shows the same grey frame at 3:2
> with `DSC00204 · no preview in this file`. No flag words and never `sharpest`, as today.
> (2) **Can't be read** (today `readOne` throws, `onDir` drops the file and counts it in
> `_failed`): keep it as a photo, `{unread: true}`, with the same grey tile and the second line
> `can't be read`. Large view: `DSC00203 · can't be read · 0 KB` (the file's size). This is only
> for a file that was read and failed. Files not reached because the card was pulled stay as they
> are today (they are read when the card returns).
> (3) **Counted.** These tiles count as photos everywhere: the Open line, each row's `N photos`,
> `rows to go`, the kept count. Open adds how many: `500 photos · 41 rows · 12 stacks · 3 without
> a picture`. Import notes become `2 without an embedded preview · shown as grey tiles` and
> `1 can't be read · shown as a grey tile` (the list in `?` stays).
> (4) **Placed by file number when there is no capture time.** A photo without a date goes next
> to the photo with the nearest lower file number, in that photo's row. Never a `00:00` row, and
> never a gap label worked out from a missing time.
> (5) **Keep and save as any photo.** P, R, F, ⌘A, undo and paint work on them. Each is a single:
> never joined to a stack, never picked by "keep sharpest". A kept one is a keeper in Save and
> gets its sidecar like the rest; if the write fails it is listed as `DSC00203 · reason`
> (SAFETY.md 6).
> (6) **Edge states.** A folder where no file can be read keeps today's Open message
> (`0 photos · N unreadable`). A stack that loses a frame to (1) keeps its other frames.
> `onDir` and `readOne` change here; the app's read repeats them and will be reviewed on sync.
>
> **B. Shift capture time.** For a camera clock that was wrong, a time zone that changed mid-trip,
> and two bodies whose clocks disagree.
> (1) **Where.** A command `shiftTime` (MENUS.md: Photo ▸ `Shift Capture Time…`), and an action
> on the import note for more than one body: `2 bodies · ILCE-7M3 + ILCE-7M4 · check that the
> camera clocks match` gains `shift a camera's time…`.
> (2) **The sheet.** Title `Shift capture time`. Line 1, what to shift: `whole shoot` · one entry
> per body (`ILCE-7M3 · …1111 · 212 photos`: model, last four of the serial, count) · `from this
> photo on` (the photo under the cursor to the end of the shoot, for a clock changed mid-trip).
> Line 2, by how much: a typed `+1:00:00` / `−0:01:10`, with `−1 h` and `+1 h` buttons. Line 3,
> what it does, live: `41 rows → 38 rows`. Line 4, quiet: `Only changes how Lumina orders this
> shoot. Your files and their capture times are not changed.` `⏎ shift · esc cancel`.
> (3) **After.** Rows, stacks and the time axis are rebuilt from the shifted times. Footer:
> `Shifted 212 photos by +1:00:00`. One undo step. A shifted row's header shows `time shifted` after
> its count. The shift is part of the session (the app stores it with the other decisions) and
> is never written to a sidecar or a RAW.
> (4) **Edge states.** One body: no per-body entries. Photos without a serial are grouped by
> model. A shift that would change nothing (`0:00:00`) leaves ⏎ off. No shoot open: the command
> does nothing.
> (5) **Two bodies stay sorted by time.** No change to the order rule: with matching clocks the
> interleaved order is the order things happened. The row header's `2 bodies` stays.

## How each ask is checked once the new handoff lands

- 1: `Tests/web/plumbing-harness.mjs` and `probe.sh smoke` (`app-smoke`: the Save screen shows the row before any save). Remove the `wf` block in `plumbing.js`'s view loop.
- 2: `probe.sh fault` (`app-xmp-both`, app mode: the lower-case `.xmp` is read on three opens in a row). For the page's own read,
  run it with `"mode"` removed: today it can pick either file.
- 9: `app-xmp-both` and `fault-card-pull-cull` (`probe.sh fault`): both assert today's "0 saved · 1 failed · … on the card" after ⌘⏎;
  once the page keeps Save off, they assert the "copy to disk first" notice instead and that ⌘⏎ makes no save call.
- 3: `__lumina.unsaved()` in `plumbing.js` becomes a call to `window.luminaUnsaved`; the contract scenario checks it exists.
- 4, 5: by eye.
- 6: a probe Tab walk scenario.
- 10: `probe.sh slowdisk` (`open-slow-disk.json`, `LUMINA_SLOW_DIR_MS=12000`): `luminaOpening` is among the hooks the
  contract scenario lists; the scenario then expects `Opening <name>…` on screen 1 s into the open and gone when the
  rows appear, and `Esc` during the wait returns to Open with no rows. `plumbing.js` calls the hook around
  `native('openFolder')` (the bridge sends the name before it lists), and `probe.sh readspeed` adds "opening shown" to
  its timeline.
- 8: `probe.sh scroll` (`scroll-read`: read-end.json shows no cursor move and under 200 px scrolled by the app; the keep
  made while reading survives), `Tests/web/plumbing-harness.mjs` (during read / reopen during read). Then drop
  plumbing's `readMoved` / `stay` handling and its refresh pacing in `grow`, and review ONDIR.
- 11: `probe.sh scroll` on a Mac (`rows out of place`, 0 % expected on every pass, reported and not gated: the CI runner
  measures 1 to 26 % with either keying, not yet explained; `tile216-dy150-indexkeys` is the page's
  own keying, for comparison). Then drop plumbing's `rowKeys`, `readyTile` and `lead` blocks and their `__lumina` switches,
  and run the scroll scenarios once more: the numbers must hold without them.
- 7: `probe.sh scroll` (`scroll-fast`, `scroll-fast-2560`: blank-tile % and upscale min per tile size) and the WebKitGTK
  sandbox's `scroll` suite; `card-clock.json` measures unchanged in both modes. Then drop plumbing's warm-ahead
  block (c) and review its `readOne` repeat (a) against the new ONDIR.
- Prompt 1 §3 + the addendum: `Tests/web/plumbing-harness.mjs` (the `edit:` checks: `lumina.preview` / `canvasRect` /
  `drag` / `roi`, `luminaPresented` / `luminaHistogram` / `luminaFacts`, latest wins on the image path, the 500 ms
  session debounce, the shoot header), `probe.sh edit` and `probe.sh raw9` (`edit-canvas`, `raw9`: today they drive
  `lumina.edit` themselves with the canvas forced up, `lumina.edit.layout(rect, true, {force: true})`, because the
  page has no Edit step; once it does, they switch to `stepEdit` and the page's own `canvasRect`). The contract
  scenario then lists `luminaPresented`, `luminaHistogram`, `luminaFacts` among the hooks. Drop plumbing's
  `pollRect` fallback.
- Prompt 2: `make culleval` on the same shoots (`~/LuminaEvidence/culleval/shoots.json`). A: "the page read drive data on N frames"
  equals exiftool's count and the camera-burst row reaches the what-if row (74 of 80 exact, recall 95 %). B and C: the
  dHash distances inside bursts drop and pair recall for bursts by hand rises with precision held; best-of-stack and keep
  precision are re-read. D: the bright-event shoot's "flagged blown" count falls and its suggested-keeps recall rises
  toward the other shoots'. A sync that changes `readOne` fails `make culleval-test` until `Tools/culleval/lib/measure.mjs` is reviewed.
- Prompt 2 C (revised): the numbers are from 277 hand-marked consecutive pairs (300 drawn across nine shoots by time
  gap and distance, 20 marked unsure, 3 not marked; one photographer, one body; the threshold was chosen on the same
  pairs, so read 93 % / 59 % as the best case). The app's distance is Vision's image feature print (revision 2) on the
  embedded preview at 512 px, about 24 ms a photo; the last row of C's table is scored with the app's own code
  (`SetsNear`) on those pairs (a first run through ImageIO's thumbnail of the RAW gave 95 % / 57 %: the same within the intervals). Labels, pairs and scripts stay on the Mac
  (`~/LuminaEvidence/culleval/labels`: `label.py` is the marking sheet, `score_labels.py` the scorer, `report.md` the
  tables); they are not in `Tools/culleval` yet. The app side is PR 164: `SetsNear` behind the
  bridge, `lumina.near` / `lumina.nearLimit` in `plumbing.js`, both listed by the contract scenario. After the handoff:
  dump the page's stacks through the app (`Tools/culleval/dump-decisions.json`) and score them against the same labels;
  expect about 93 % of stacked pairs marked the same picture and more than half of the marked retakes stacked.
- Prompt 2, second part (E, F, H): the culling eval through the app, on the Mac (it needs shoots with traceable
  exports; labels and photos stay in `~/LuminaEvidence/culling-eval`).
  `LUMINA_CULL_DIR=<shoot> lumina-probe run Tools/culleval/dump-decisions.json` dumps what the page decided;
  `node Tools/culleval/culleval-app.mjs --exports exports.csv … decisions.json` gives each word's false alarms on picks
  and its picked-if-said rate. After the handoff: `soft` on no more than about 2 % of photos and 1 % of picks, no
  `shake` or `slight` in the dump. `make culleval-test` covers the scorers.
- Prompt 2, second part (G): `plumbing.js` gains `lumina.measures` (Vision's face capture quality from the embedded
  preview, the measure `Tools/culleval/signals/signals.swift` takes); the contract scenario lists it, and
  `python3 Tools/culleval/signals/rank_signals.py` re-scores "top-1 is a pick" for stacks ranked by it.
- Prompt 3 A: `probe.sh edge` and `ingest` (`edge-corrupt-preview`, which already expects 5 photos from the 5-file
  fixture; add: both grey-tile lines on screen, no `00:00` row, no gap label over 24 h, the Open line's `without a
  picture` count, P on the unreadable tile then Save writes its `.xmp`). Review `plumbing.js`'s repeat of `readOne` /
  `onDir` and update `ONDIR`.
- Prompt 3 B: `edge-tz-jump` (it already expects `shiftTime` or the word "shift" on the page; add: `from this photo
  on` +9:00:00 gives one row in file order) and `edge-two-bodies` (rewrite its expectation: today it asks for serial
  order, which B(5) declines; instead, shifting body B by −0:01:00 changes the order as computed, and the files'
  bytes are unchanged). The session round trip of the shift joins `Tests/web/plumbing-harness.mjs`.
- EDGE-CASES C4: re-forge `burst-10fps` (its twelve frames are twelve different pictures with no sequence numbers,
  so v5 shows twelve singles and the scenario no longer tests a burst), then re-read it after Prompt 2 A and B.
- Prompt 5: `Tests/web/plumbing-harness.mjs` (the `stale sidecar:` checks: changed, made and deleted since the open; changed
  during Save → the result line and the file untouched), `SetsSidecarTests` (the base check), and `probe.sh app` with
  `app-xmp-changed-since-open` (real Lightroom sidecars swapped in after the read; add it to `APP` in `Scripts/probe.sh`).
  A: the harness asserts the new wording. B: add the contract check for `lumina.sidecars`, an expect on the Save notes
  before ⌘⏎, then drop the re-read and re-merge in `plumbing.js`'s `writeInto` (the base check on the Mac stays).
  C: the scenario with `"mode"` removed.

## Prompt 4 — when the page keeps stopping (paste into Claude Design)

Found by the threat model (T7, 2026-10-01). When the page's process dies (a crash, or memory), the
app reloads it. A file that kills the page every time would loop forever, so the app now reloads at
most 3 times in a minute; on the next stop it stops reloading and shows a native alert, because the
page is gone and cannot show anything:

- Title: `Lumina keeps stopping`
- Text: `It stopped again after reloading 3 times in a minute. Your decisions so far are saved.`
- Buttons: `Try Again` (reloads once more, the count starts over) · `Quit`

Quit also no longer waits for a page that doesn't answer: after 2 s it quits as if no keepers were
unsaved. Decisions are saved by the app as they are made (`saveSession`), so neither path loses them.
Both alerts are native, but their words are the design's, like the Quit alert's in MENUS.md.

> In MENUS.md (or SAFETY.md), add the app's alerts with their exact wording: Quit with unsaved
> keepers (as today), Remove Working Files (as today), and the new one above. Change its words if
> you want them different; keep it to a title, one or two plain sentences and two buttons.
> (1) **After a reload the page says so.** Today a reloaded page comes back on Open with no word.
> When the app reloads after a stop, `window.lumina.restarted` will be `true` before your script
> runs (plumbing.js adds it when this lands; no UI of its own): show one quiet footer line, e.g. `Lumina restarted ·
> your decisions are kept`, gone on the next key, and reopen nothing by itself.
> (2) **Optional, naming the file.** If you want the alert to name the photo being read when the
> page stopped (`DSC03311.ARW`), say so in the wording; the app would then track the last file the
> page asked for.

Checked by `LuminaLogicTests/SetsPageRecoveryTests.swift` (the reload count and the wording the
app ships today) and by hand: kill the page's process 4 times inside a minute and see the alert;
Quit with the page hung and see the app quit after 2 s.

## Prompt 5 — a sidecar another app changed after the open (paste into Claude Design)

Found by reading the code (release threat model T4, 2026-10-01) and reproduced in
`Tests/web/plumbing-harness.mjs`: the page keeps each sidecar's text from the read (`p.xmp`) and
`xmpFor` merges the rating into that text at Save, however long ago the read was. Open a folder,
edit a photo in Lightroom, press ⌘⏎ in Lumina: the sidecar got the text from the open back, with
the new rating, and Lightroom's newer settings were gone.

The app no longer does that. At Save, `plumbing.js` has the Mac read each sidecar again, puts the
text on disk into `p.xmp` (and `p.lrEd`) where it differs, and lets the page's own `xmpFor` merge
again; the Mac then refuses a file that changed once more in the instant before the write, leaves
it untouched, and returns it in `errors` as `{ name, reason: 'changed on disk' }`. Three things
stay with the page:

> Update `Lumina Sets v5.dc.html` (and `SAFETY.md`). Keep the look, keys and wording otherwise
> unchanged.
>
> **A. The result line for a sidecar that changed during Save.** The app can return a new reason
> in the result list: today it reads `DSC03311 · changed on disk` (the app's word, in the list's
> existing style). Decide the wording and add it to SAFETY.md 6's list of reasons (disk full,
> read-only, locked, missing). The file was not written and is exactly as the other app left it;
> pressing ⌘⏎ again reads it again and saves it. If the line should say that (`… · save again`),
> say how; nothing is retried silently.
>
> **B. Save shows what is on disk now, not what was there at the open.** The Save step's own
> facts come from `p.xmp` as read: the import note `N already have a .xmp sidecar · M with
> Lightroom edits · only the rating will be updated`, the `was★ → now★` rows, `new sidecars` /
> `existing sidecars` counts, the file tree's `merged` / `new`. After a long cull they can be
> wrong before ⌘⏎ (a sidecar made, edited or deleted since) and the result is computed from the
> counts taken before the write. When the Save step opens in the app, and again right before
> `runExport` builds its files, call `await lumina.sidecars(names)` (new; the names `runExport`
> gives its files) → `[{ name, text, base }]` (`text` null when there is no file), put each `text`
> into `p.xmp`, recompute `p.lrEd` with `LuminaCore.hasDevelop`, and rebuild the notes and the
> rows from that. Pass each file's `base` on in `writeInto(files, 'xmp')` as `{ name, data, base }`.
> The app does the read and the merge for you today from `plumbing.js`; with it in the page that
> code can go, and the screen is right before the write as well as after.
>
> **C. The browser has the same gap.** The page's own `writeInto` (`showDirectoryPicker`) writes
> `f.data` over whatever is there. Before writing each file, read it through its handle; when its
> text is not the `p.xmp` the merge used, merge the rating into the text just read
> (`LuminaCore.mergeXmp`) and write that. The `.lumina-bak` copy stays as it is.

## Prompt 6 — folders too big to be a shoot, oversized sidecars, sessions refused (paste into Claude Design)

Found by the release threat model (T5, 2026-10-01). The Mac now bounds what a folder can make it
read: a listing stops past 100,000 files and folders or 12 folder levels (opening `/`, a home folder
or a whole disk), a sidecar over 1 MB is not read, and a session over 16 MB is not stored. The page
has no words for any of it, so `plumbing.js` says stand-ins through `say` and the Open line
(`openNote`), and adds skipped sidecars to `_failed`:
`not available · <folder> · over 100000 files · open one shoot`,
`not available · <folder> · folders over 12 deep · open one shoot`,
`DSC00002.xmp · sidecar over 1 MB, not read` (in `?`, counted in `N unreadable`), and
`decisions not saved · session too big`.

> Update `Lumina Sets v5.dc.html`. Keep the look, keys and wording otherwise unchanged, and keep
> the browser behaviour as it is.
>
> **A. A folder too big to be a shoot.** In the app, `openFolder` can come back as
> `{ tooBig: { name, why: 'tooManyFiles' | 'tooDeep', files: 100000, depth: 12 } }` instead of a
> listing: nothing was read. Stay on Open and say it where `no ARW found` is said today, in the
> same voice, naming the folder and what to do: for example `Pictures is too big to be one shoot
> · over 100,000 files · open the shoot's own folder` (or `· folders nested over 12 deep ·`).
> No banner and no list: it is the photographer's pick that was wrong, not the app.
>
> **B. A sidecar Lumina didn't read.** The listing can carry `skippedXmp: [rel]`: sidecars over
> 1 MB, left unread. Their photos open as if they had no sidecar. Count them in the import notes
> as their own line, not as unreadable photos (the photo itself reads fine):
> `1 sidecar over 1 MB not read · its rating isn't shown` with the files in the `?` list as
> `DSC00002.xmp · over 1 MB, not read`. On Save, a keeper whose sidecar was not read should say
> so in the result list rather than replace it silently (the Mac keeps a `.lumina-bak`).
>
> **C. Decisions not saved.** `lumina`'s session write can be refused (over 16 MB, or the disk).
> Say it once per shoot in the footer, quiet but not hidden: `Decisions for this shoot can't be
> saved · <reason>`, and keep culling.

### How Prompt 6 is checked once its handoff lands

- A: `LuminaLogicTests/SetsIngestBoundsTests` (the listing's refusal) and a `Tests/web/plumbing-harness.mjs`
  case with the stand-in bridge returning `tooBig`: the Open line shows the page's own words. Drop plumbing's
  `L.tooBig` stand-in.
- B: the same harness with a `skippedXmp` entry: the import note line and the `?` entry. Drop plumbing's push
  into `_failed`.
- C: the harness's `saveSession` rejecting with "too big": the footer line once. Drop plumbing's `.catch` wording.

## Prompt 7 — Help ▸ Acknowledgements (paste into Claude Design)

The app bundles React 18.3.1, React DOM 18.3.1 and @babel/standalone 7.29.0 (and the packages
inside Babel). Their licences require the copyright and permission notices to ship with the
copies. They now do, as `Lumina/Resources/THIRD-PARTY-NOTICES.txt` in the app bundle (R6), but
nothing in the app shows them. MENUS.md has no place for them, and the app's menus follow MENUS.md.

> Update `MENUS.md` and `Lumina Sets v5.dc.html` for the Mac app. Keep the look, keys and
> wording otherwise unchanged.
>
> **A. Help ▸ Acknowledgements.** In MENUS.md the Help menu becomes
> `Lumina FAQ · Keyboard Shortcuts ? · Acknowledgements · Contact on X`, and `acknowledgements`
> joins the command names for `window.luminaCommand`. About gains a quiet link
> `Acknowledgements` next to the FAQ link that does the same.
>
> **B. The sheet.** `luminaCommand('acknowledgements')` opens a sheet titled
> `Acknowledgements`, with one line under the title, same type one step quieter:
> `Lumina uses open-source software. Their licences follow.` Below it, the text from
> `await lumina.notices()` (a plain-text string the app reads from its bundle), shown exactly
> as given: monospaced, line breaks kept, no reflow, selectable, in a pane that scrolls on its
> own. `esc` or ⏎ closes it. It opens from any step and changes nothing in the shoot.
>
> **C. Edge states.** In the browser (no `window.lumina`, or no `notices`), the sheet lists the
> three libraries the page loads, with their versions and their licence links
> (`https://unpkg.com/react@18.3.1/LICENSE`, `https://unpkg.com/react-dom@18.3.1/LICENSE`,
> `https://unpkg.com/@babel/standalone@7.29.0/LICENSE`). If `lumina.notices()` fails, the same
> list shows with the line `The full text ships inside Lumina.app (Contents/Resources/THIRD-PARTY-NOTICES.txt).`

### How Prompt 7 is checked once its handoff lands

- `plumbing.js` gains `lumina.notices()`, returning `THIRD-PARTY-NOTICES.txt` from the bundle through the bridge
  (data, no UI); the contract scenario lists it, and `Tests/web/plumbing-harness.mjs` checks the sheet shows the
  file's first and last lines.
- `LuminaApp.swift` adds Help ▸ Acknowledgements calling `luminaCommand("acknowledgements")`, after MENUS.md says so.
- `probe.sh screens` gains the sheet in prototype and app mode.

## Prompt 8 — an export that was cut short (paste into Claude Design)

Found by release task R1d (2026-10-01). An export killed mid-way (crash, kill, power) leaves its
finished files (each verified) and, at most, one half-written hidden temp file per file in flight
(`.DSC00001.ARW.lumina-tmp-…`). On the next launch the app removes those temp files through a
bookmark of the export folder it kept when the export began. That cannot always work: the folder was
moved to a disk that isn't connected, or the export was made by an older Lumina that kept no
bookmark. Then the temp files stay and the app tries again on every launch. Today none of this
reaches the page; the app only logs it.

> When the app starts and finds an export that was cut short, `window.lumina.cutShort` will be an
> array before your script runs (plumbing.js adds it when this lands; no UI of its own), newest
> first: `{label, folder, planned, done, cleaned}` — `label` the export's kind as the page sent it
> (`lr`, `both`, `xmp`…), `folder` the export folder's name, `planned` / `done` counts, `cleaned`
> `true` when the half-written files were removed, `false` when they could not be reached.
> (1) Show it once, as a quiet footer line on Open, gone on the next key, e.g.
> `last export stopped after 14 of 40 · Lightroom Exports · export again to finish` and, when
> `cleaned` is false, `· reconnect Lightroom Exports so Lumina can tidy it`. Your words; keep it
> one line, name the folder, and do not reopen or retry anything by itself.
> (2) Exporting again into the same folder already finishes the job (the probe's
> `fault-kill-mid-handoff` checks it); say so only if you want to.

Checked by `LuminaLogicTests/SetsExportJournalSandboxTests.swift` (what recovery does and records)
and, once the page shows it, by a probe scenario that kills an export and relaunches.

## Prompt 9 — a card Lumina may not read yet (paste into Claude Design)

Found by the threat model (T10, release task R1c, 2026-10-01). In the App Store build (the App
Sandbox), Lumina may read a camera card only after the user has picked it once in the Mac's folder
panel. So when a card goes in for the first time, the app knows its name but not how many photos
are on it, how big they are, or whether it is a Sony card. After that one pick the app keeps a
grant for that card (by its volume UUID, so under any mount name), and the next time the card goes
in everything is known at once, as today. Builds outside the sandbox always know everything.

What the page gets today. `window.lumina.card` is unchanged for a card the app can read: `{name,
photos, bytes, sony, path, …}`, now also `known: true` and `grant` (`"open"`, `"bookmark"`, `"recent"` or
`"panel"`, data only). A card it cannot read yet is **not** put in `lumina.card`, because v5's
banner would read it as `no ARW found · 0 photos` with no button. It is in a new field instead:

    window.lumina.cardPending = { name: "Untitled", path: "/Volumes/Untitled", uuid: "…",
                                  photos: null, bytes: null, sony: null, known: false }

and `lumina.card` stays `null` until the user picks the card. Until this lands, the sandboxed app
shows no card banner on a first insert (⌘O on the card's DCIM still works, and the app remembers
that grant too).

> (1) **The banner for a card Lumina can't read yet.** When `window.lumina.cardPending` is set
> (and `lumina.card` is null), show the card banner with what is known and the same button:
> - line 1: `Untitled · /Volumes/Untitled` (name and path; no count and no size, they are not
>   known: never `0`);
> - line 2: `the Mac asks once which card to read · Lumina remembers this card`;
> - the button `Cull This Card` (and ⏎ when the banner is selected on Open), calling `impStart()`
>   as today. The app then shows the Mac's folder panel, opened on the card's `DCIM`, button
>   `Cull This Card`, message `Choose the card Untitled to let Lumina read it. Lumina only reads
>   it, and remembers this card.` A pick that is not on that card is refused and the panel asks
>   again with `That folder is not on the card Untitled. Choose the card.` (a folder elsewhere) or
>   `Choose the card Untitled itself, or its DCIM folder.` (a folder inside the card). Change
>   these words if you want them different; the app will use yours.
> - Cancel in the panel: nothing happens, the banner stays.
> (2) **Right after the pick.** The app sends the whole card (`lumina.card` with the count,
> `cardPending` back to null) and opens it straight away, as `Cull This Card` does today. If you
> want a word that the card is now remembered, show it once, quietly, when `lumina.card.grant ===
> "panel"` (for example a footer line `Untitled · Lumina will read this card without asking`).
> `"bookmark"` and `"recent"` mean it was read through a remembered grant; no word is needed then.
> (3) **Pulled before the pick.** `cardPending` goes back to null, as `card` does today.

Checked by `LuminaLogicTests/SetsCardAccessTests.swift` (what the app sends before and after the
grant, where the panel opens, the refusals, no panel the second time) and the probe's
`card-sandbox-first` / `card-sandbox-again` (`bash Scripts/probe.sh sandbox scenarios
card-sandbox-first card-sandbox-again`). Once this lands, those scenarios assert the banner's
line 1 for a pending card and press ⏎ on it instead of calling `impStart()` directly.

## Prompt 10 — a sidecar Lumina can't read, and a name too long to save (paste into Claude Design)

Found by the hostile-input stress run (Q4-F5 and Q4-F4, `docs/release/stress/Q4-hostile.md`,
2026-10-01). A `.xmp` that is not UTF-8 text (Lightroom's settings saved in Latin-1 by an old
tool, a UTF-16 sidecar, a damaged file) used to be left out of the app's listing: the page took the
photo for one without a sidecar and Save wrote a fresh ratings-only sidecar over it. The other
app's develop settings survived only in `.lumina-bak`.

The app no longer does that. The listing names such a sidecar in `unreadableXmp: [rel]` (beside
Prompt 6's `skippedXmp`), the photo opens with its sidecar's path and no text, and on Save the Mac
leaves the file byte for byte as it is and returns it in `errors` as `{ name, reason: 'unreadable' }`.
A file whose name the disk refuses comes back as `{ name, reason: 'name too long' }`. The page has
no words for either, so `plumbing.js` adds the sidecar to `_failed` as
`DSC00107.xmp · sidecar unreadable, not read` (in `?`, counted in `N unreadable`), and the result
list shows the Mac's words in its existing style: `DSC00107 · unreadable`, `LLL…L · name too long`.

> Update `Lumina Sets v5.dc.html` (and `SAFETY.md`). Keep the look, keys and wording otherwise
> unchanged, and keep the browser behaviour as it is except where C says so.
>
> **A. A sidecar that is there but can't be read.** The listing can carry `unreadableXmp: [rel]`:
> sidecars that exist but are not text Lumina can read. Their photos open as usual, without a
> rating from the sidecar. Count them in the import notes as their own line, not as unreadable
> photos (the photo itself reads fine), next to Prompt 6 B's line for sidecars over 1 MB:
> `1 sidecar can't be read · it will be left as it is`, with the files in the `?` list as
> `DSC00107.xmp · not readable as text`. In the Save step, before ⌘⏎, such a keeper's row says its
> sidecar will not be written (`existing sidecar · can't be read · left as it is`) instead of
> `new` or `merged`, and it is not counted in `new sidecars` / `existing sidecars`.
>
> **B. The result lines.** Two new reasons can come back in the result list; decide the wording
> and add both to SAFETY.md 6's list of reasons (disk full, read-only, locked, missing, changed
> on disk, over 1 MB):
> - `unreadable`: the sidecar on disk is not text Lumina can merge a rating into. It was not
>   written and is exactly as the other app left it. Suggested: `DSC00107 · sidecar can't be
>   read · left as it is`. Saving again changes nothing until the other app writes the file again.
> - `name too long`: the sidecar, or the `.lumina-bak` kept before replacing it, would have a
>   name longer than the disk allows (a RAW name of about 245 bytes or more). Nothing was
>   replaced. Suggested: `<name> · name too long for a sidecar` with the name shortened in the
>   middle so the line still fits.
>
> **C. The browser has the same gap.** The page's own `onDir` reads every `.xmp` with
> `file.text()`, which turns bytes that are not UTF-8 into replacement characters, and the page's
> `writeInto` then writes that text back with the rating merged: the other app's label or
> keywords are damaged for good. Read each sidecar's bytes and decode them with
> `new TextDecoder('utf-8', { fatal: true })`; when that throws, treat the sidecar as in A and
> never write it.

## Prompt 11 — sessions from before the sandbox (paste into Claude Design)

Found by release task R1e (2026-10-02). Until the app was sandboxed it kept its working files
(recent shoots, the decisions per shoot) in `~/Library/Application Support/Lumina`. A sandboxed
build keeps them in its own container and may not read the old folder, so after the update Open
shows no recent shoots and the decisions of every earlier cull look gone. They are still on disk.
The app now brings them over once the user has picked the old folder in a panel (the pick is the
permission). It only reads that folder. A shoot culled further since the update keeps what it has
now; nothing is replaced.

On the first launch of a build whose own store is still empty, the app shows a native alert (a
sheet on the window, because the page has no words for this yet):

- Title: `Bring over your earlier sessions?`
- Text: `Lumina now keeps its working files in a protected place of its own. If you used an
  earlier version on this Mac, choose its folder and Lumina brings your decisions over. Photos and
  sidecars stay where they are.`
- Buttons: `Choose Folder…` · `Not Now` (never asked again by itself)

`Choose Folder…` opens the Mac's folder panel on `~/Library/Application Support/Lumina`, button
`Bring Over`, message `Choose the folder “Lumina” in Library ▸ Application Support. Lumina only
reads it.` A pick without sessions is refused and the panel asks again with `No earlier sessions in
that folder. Choose “Lumina” in Library ▸ Application Support of your home folder.` Cancel changes
nothing. Afterwards the status line says one of (through `say`, stand-in wording):

- `3 sessions brought over · open a folder to continue it` (`1 session brought over · open its folder to continue it`)
- with `· 1 kept as it is here` (`· 2 kept as they are here`) for shoots culled further since the
  update, and `· 2 skipped` for files that could not be read
- `earlier sessions are already here` · `no earlier sessions found` · `earlier sessions not brought over · <reason>`

A recent that came over cannot be reopened from the list yet: the Mac's permission for its folder
was the old build's. Opening the folder once with ⌘O finds its decisions (the shoot is recognised
by its folder) and the recent works from then on. Until then File ▸ Open Recent says
`not available yet · open its folder once with ⌘O`, and the page's own recent cards say
`not available · <path>` as for a card that is out.

> Update `MENUS.md` and `Lumina Sets v5.dc.html` for the Mac app. Keep the look, keys and wording
> otherwise unchanged.
>
> **A. The alert's words.** Add the alert above to the app's alerts in MENUS.md (with Quit, Remove
> Working Files and the page-keeps-stopping alert of Prompt 4), with its panel's button, message
> and refusal. Change the words if you want them different; the app will use yours. Keep it to a
> title, two or three plain sentences and two buttons. Every user sees it once on a new Mac, also
> one who never had an earlier version: say if it should read differently for them, or if you
> would rather have no launch question at all and only the menu item of B.
>
> **B. A way back to it.** `Not Now` is final today: nothing in the menus opens the panel again.
> In MENUS.md the File menu becomes `Open… ⌘O · Open Recent ▸ · Bring Over Earlier Sessions… ·
> Close Shoot ⌘W · Save Keepers ⌘⏎ · Show in Finder ⌘R · Remove Working Files…`. Like Remove
> Working Files…, the item is the app's own (it opens the folder panel directly; no
> `luminaCommand` name). If Open should offer it too (a quiet link under the recents when there
> are none: `Sessions from an earlier version? Bring them over…`), call
> `lumina.bringOverEarlierSessions()`, which the app will provide; it resolves to
> `{ sessions, recents, kept, skipped }` after the panel, or `null` on Cancel.
>
> **C. The result line.** Decide the wording of the status lines above (the counts are
> `sessions`, `kept`, `skipped`). They show once, on Open, and go on the next key.
>
> **D. A recent that needs its folder opened once.** A recent can carry `needsFolder: true`
> (it came over from the earlier version; the app will send it when this lands). Show its card as
> the others, with its counts (`dec`, `kp`, `last` are the earlier session's), and one quiet line
> in place of the usual hint: `open this folder once to continue · ⌘O`. ⏎ or a click on it opens
> the folder panel (`openFolder`) instead of `libOpen`; when the picked folder is that shoot the
> card becomes an ordinary recent, and when it is another folder that one opens as usual. Do not
> say `not available`: nothing is missing, the Mac only needs to be asked once.

### How Prompt 11 is checked once its handoff lands

- `LuminaLogicTests/SetsShootImportTests.swift` (Mac and Linux) holds the import today: a store in
  the earlier format comes over byte for byte, the index without its bookmarks; a shoot in both
  stores keeps what the new one has; links, invalid ids, oversized and unreadable sessions and a
  damaged index are skipped and counted; the earlier folder is unchanged; a second import is a
  no-op; the alert's words as shipped.
- `LuminaApp.swift` adds File ▸ Bring Over Earlier Sessions… calling
  `SetsWindowController.bringOverEarlierSessions()` after MENUS.md says so; `plumbing.js` adds
  `lumina.bringOverEarlierSessions()` and `needsFolder` on recents (data, no UI), and the
  contract scenario lists them.
- By hand, once: install a sandboxed build over an unsandboxed one, see the alert, choose the
  folder, open a folder culled before and find its decisions.

## Prompt 12 — Edit v21 calls the native canvas it specifies (paste into Claude Design)

Found while syncing handoff v0.02 (Sets v8 + Edit v21, 2026-10-05). `BRIDGE-v0.02.md` §2 says
Edit calls `lumina.canvasRect`, `lumina.drag`, `lumina.roi`, `lumina.preview` and
`lumina.prefetch`, and that the app calls `window.luminaPresented`, `window.luminaHistogram`,
`window.luminaFacts` and `window.luminaEditStats`. `Lumina Edit v21.dc.html` makes none of those
calls and defines none of those hooks: its only app calls are `lumina.auto(rel)` and
`lumina.emit(type, detail)` (`dragStart`, `dragEnd`, `step`, `zoom`, `pan`, `colourAt`, `wbPick`,
`spectrum`). So the app can't place the native canvas, can't hear a look change, and can't hand
back histograms or the decoder line. Until this lands, Edit in the app shows the page's own
preview, as in the browser. `plumbing.js` will not read Edit's internals to fake it.

> In `Lumina Edit v21`, add the calls BRIDGE-v0.02 §2 describes, each guarded with
> `typeof lumina.x === 'function'` so the page still runs in a browser:
> - `lumina.canvasRect({x, y, w, h, dpr})` (CSS px, in the window) on open, on every layout change
>   and resize, and when something covers the canvas; `lumina.canvasRect(null)` when Edit hides.
>   In the app, the canvas box is transparent where the native canvas sits.
> - `lumina.preview(rel, look, px, seq)` at most once per animation frame while a look changes,
>   `look` being the canonical look string (§4), `seq` increasing. A `null` answer keeps the box
>   transparent.
> - `lumina.drag('start' | 'end')` on slider press and release.
> - `lumina.roi({x, y, w, h})` in image px while Z is held, `lumina.roi(null)` on release.
> - `lumina.prefetch([{rel, pri, px}])` on keep, ⇧P, entering Edit, cursor moves in Edit and
>   entering Save (each call replaces the last).
> - Define `window.luminaPresented(seq)`, `window.luminaHistogram({seq, r, g, b, clipHi, clipLo})`
>   and `window.luminaFacts({canvas, raw9, decoder, note})` while Edit is mounted, and remove them
>   on unmount: older pending previews drop on `luminaPresented`, the histogram and clipping
>   warnings come from `luminaHistogram`, and the facts line names the decoder from `luminaFacts`
>   (`note` "update shoot" calls `lumina.edit.updateDecoder()`; hide Colour NR, Detail and Moiré
>   while `raw9` is true).
> Nothing visible changes in the browser.

### How Prompt 12 is checked once its handoff lands

- `Tests/web/plumbing-harness.mjs`, the `edit:` checks, switch from driving `lumina.edit` by hand
  to the page's own calls: `stepEdit`, then the page's `canvasRect`, one `preview` per frame for 100
  slider events, `drag`, `roi`, and the hooks answered.
- `probe.sh edit` and `probe.sh raw9` drop `lumina.edit.layout(rect, true, {force: true})` and use
  `stepEdit` with the page's own rect.
- The contract scenario lists the calls and hooks.

## Prompt 13 — the self-test still checks v5's P toggle (paste into Claude Design)

v8's page does what CHANGES-v0.02 says: P on a kept photo moves on and never toggles. The self-test
still has v5's check `P again un-keeps` (← back to the kept photo, P, expect it un-kept), so
`?selftest` reports 22 / 23 in every browser and in the app. Until this lands, the probe's
`selftest` scenario and `Tests/web/webkit.py` expect exactly that one failure and check v8's rule
themselves.

> In `lumina-selftest.js`, replace the check `P again un-keeps` with
> `P on a kept photo keeps it and moves on`: ← back to the photo P just kept, P, and pass when it
> is still kept and the cursor has moved off it (CHANGES-v0.02: ⏎ / P / K never toggle). Nothing
> else changes.

### How Prompt 13 is checked once its handoff lands

- `?selftest` passes every check; `Tests/probe/scenarios/selftest.json` goes back to expecting no
  failures and drops its own v8 step, and `STALE` comes out of `Tests/web/webkit.py`.

## Prompt 14 — the storage meter shows a total from before the last preloads (paste into Claude Design)

`cacheParts()` keeps the meter's total for 1 s. ⌥→ in Cull preloads up to four more big-view
photos; when the meter draws inside that second it keeps the total from before them, and nothing
draws it again until the next state change. So the same screen shows 20 MB on one run and 28 MB on
the next (`08-cull-skip`, 1920 px, app vs prototype). Until this lands, the four `screens-*`
scenarios expire the memo (`_cpAt = 0`) and redraw once after ⌥→ settles, before that snapshot.

> In Sets v8, when a preload, thumbnail or cache write changes what the storage meter counts, drop
> the 1 s memo in `cacheParts()` and redraw the meter, so it always shows the current total once
> the page is idle. Keep the memo for redraws that change nothing it counts. Nothing visible
> changes.

### How Prompt 14 is checked once its handoff lands

- `probe.sh screens` passes 34 / 34 with the redraw step taken out of `Tests/probe/scenarios/screens-*.json`.

## Prompt 15 — a quick Space tap reads as a hold when the page is busy (paste into Claude Design)

Space opens the large view and notes `_spT = Date.now()`; on keyup, more than 350 ms since then
counts as a hold (peek) and closes the view again. Both times are read when the handler runs, not
when the key moved, so a tap whose keyup waits behind a long task (opening the large view decodes
and lays out the big photo) is taken for a hold and the view shuts at once. A Mac under load (the
M1 8 GB, or the CI runner) sees it; the self-test's `F held shows the focus overlay` fails on it
now and then (main, 2026-10-06: failed unsandboxed, passed sandboxed a minute later on the same
commit). Reproduced in Chromium: a single 400 ms task right after `[data-lumina=large]` appears
makes that check fail every time; without it, it passes.

> In Sets v11, judge Space's hold from the events' own `timeStamp` (keydown's and keyup's), not from
> `Date.now()` in the handlers, so a key released quickly is a tap however late the page handles
> it. In `lumina-selftest.js`, the `F held shows the focus overlay` check opens the large view, then
> waits until `luminaState().large` is true (up to 1 s) before pressing F, instead of a fixed 250 ms.
> Nothing visible changes.

### How Prompt 15 is checked once its handoff lands

- `probe.sh selftest` passes; `node` with a 400 ms task injected after the large view opens (the
  Chromium reproduction) passes the focus overlay check.

## Prompt 16 — Help ▸ Privacy and Help ▸ Support (paste into Claude Design)

The App Store asks for a privacy policy and a support page at public URLs, and they exist
(`docs/release/listing/privacy.md`, `support.md`). Nothing in the app says the same thing, so a
user who wonders where their photos go, or how to reach someone, has to find a web page. The
words should also be in the app, in the app's own look.

> Update `MENUS.md` and the Sets page for the Mac app. Keep the look, keys and wording
> otherwise unchanged.
>
> **A. Menus.** The Help menu gains `Privacy` and `Support`, after `Keyboard Shortcuts`;
> `privacy` and `support` join the command names for `window.luminaCommand`. About gains quiet
> links `Privacy · Support` next to the FAQ link that do the same.
>
> **B. Privacy sheet.** `luminaCommand('privacy')` opens a sheet titled `Privacy`, in the
> Acknowledgements sheet's style, with this text:
> `Lumina does not collect, store or share any information about you.` Then four short
> paragraphs, each with a bold lead: **No data leaves your Mac.** The app makes no network
> connections: no account, no analytics, no crash reporting of its own, no advertising.
> **Your photos.** Lumina reads only the folders and cards you choose and never changes your
> originals. Save writes rating files (.xmp) next to your photos and keeps a backup of any it
> replaces. **What it keeps.** Your decisions and recent shoots, in the app's own folder on this
> Mac; remove a shoot's working files from the Open screen. **Crash reports.** Only if you share
> analytics with developers in macOS settings, and then through Apple.
>
> **C. Support sheet.** `luminaCommand('support')` opens a sheet titled `Support`: the
> contact line `anikethcov@gmail.com · LinkedIn` (both links, handed to the Mac through the
> page's external-link call: `mailto:anikethcov@gmail.com`,
> `https://www.linkedin.com/in/anikethmaddipati`), the hint `Include your macOS version, your
> Mac model and what you did just before the problem.`, then the five questions from the
> support page as a short FAQ: which files it reads, where the ratings are, why it asks for a
> folder, why it can't save on the card, where decisions are kept.
>
> **D. Edge states.** Both sheets open from any step, change nothing in the shoot, and close
> with `esc` or ⏎. In the browser the links open in a new tab.

### How Prompt 16 is checked once its handoff lands

- `LuminaApp.swift` adds Help ▸ Privacy and Help ▸ Support calling `luminaCommand("privacy")` /
  `luminaCommand("support")`, after MENUS.md says so.
- The two links pass the external-link allowlist (`SetsExternalLinks`, being wired in by the
  trust-model work): `mailto:` to that address and the one LinkedIn URL.
- The sheets' text matches `docs/release/listing/privacy.md` and `support.md`; when one changes, so does the other.
- `probe.sh screens` gains both sheets in prototype and app mode.

## Prompt 19 — untouched Edit sliders read as live; an emptied picks-only pass goes back to all photos (paste into Claude Design)

Owner's call 2026-10-07, made in the page here ahead of the design handoff (a sync before this
lands overwrites both). Two looks read as a broken app:

- Edit drew every slider the photo has not changed with a grey label and a grey value (`#9A958D`,
  the colour of a disabled control). A photo that is "As shot" has changed none, so the whole panel
  looked locked, most of all with nothing picked yet.
- Pick's picks-only pass (⇧P) folds a row with nothing kept into its time label and a thin bar.
  Un-keeping the last photo of the pass left every row folded: a page of time labels and bars with
  no photo and nothing saying why.

> In Edit v22's `sliderRow`, a slider's label is `#EFECE6` whether or not its value was changed, and
> an unchanged value is `#B8B3AB` (changed stays `#EFECE6`; gold when active, as now). In Sets v11,
> when the picks-only pass is showing and a decision leaves nothing kept, the page goes back to all
> photos and the footer says `Nothing kept in this pass · showing all photos`. Nothing else changes.

### How Prompt 19 is checked once its handoff lands

- Edit on a photo that is "As shot": every slider label is `#EFECE6`; after Auto the changed rows'
  values are `#EFECE6` and the rest `#B8B3AB`.
- Pick: keep one photo, ⇧P, un-keep it. All photos are shown again and the footer says so.

## Prompt 20 — Crop can go back to the original (paste into Claude Design)

The crop bar has Ratio, Straighten, Turn, Cancel and Apply. The panel row says Cropping, then
Cancel and Apply. Light has `Reset light`. Nothing in Crop puts the frame back: ratio Original,
straighten 0.0°, the whole photo. `full()` already returns that crop (`x:0, y:0, w:1, h:1`,
angle 0, ratio `original`), and no control calls it. Ratio Original only changes the aspect of
the current rect. There is no hidden reset to wire up.

> In Edit v22, while Crop is open, add Reset.
>
> On the bar over the photo (Ratio, Straighten, Turn, Cancel, Apply), put `Reset` before Cancel,
> in Cancel's style (not Apply's gold). On the Cropping row in the panel, put `Reset crop` before
> Cancel, in the same place and style as `Reset light`.
>
> Both do the same thing. They set the crop back to the original full frame: Ratio Original,
> Straighten 0.0°, the rect the whole photo. One undoable crop step, the way dragging a corner
> is: ⌘Z brings the previous frame back. The footer says `Crop reset. ⌘Z undoes it.` Reset does
> not leave Crop, does not apply it, and does not cancel it. Cancel still drops the crop. Apply
> still keeps it. Nothing else changes.

## Prompt 21 — Edit opens on the current photo with nothing picked; the filmstrip separates time and leaves bursts open (paste into Claude Design)

Both are the Edit step (Edit v22, the strip under the photo). Pick’s grid is unchanged.

**What happens today.** The Edit control, ⌘3, and `luminaCommand('stepEdit')` call `setView('edit')`.
That refuses only when the shoot has no photos (`0 photos · ⌘O`). It does not look at keeps.
`editShoot` already marks every photo that is not set aside as kept when `kept()` is empty, and
the header then reads `All N · nothing picked yet · R sets one aside`. Edit does not open the
photo Pick is on. `mount0` uses the saved Edit cursor, or `firstId()` (the sample’s DSC03311,
else the first photo in the keeper order, else the first photo). With no photo on the canvas the
centre line is `No photos to edit. Keep some in Pick first.` (`canvasTxt`), the strip says
`No picks yet. Mark photos to keep in Pick.`, and outside the app the overlay is `Nothing to edit
yet` / `Every photo is set aside. ⌘Z brings one back, or ⌘2 to pick.` `keep something first` is
only the picks pass (⇧P). The filmstrip (`data-lumina="filmstrip"`) makes one group per Pick row.
The row’s time (`19:50`, the same words as the time axis and the row head) sits above the tiles,
and only when the window is at least 1100 × 760. Groups are 12 px apart; tiles inside a group are
3 px apart. A burst contributes only the frames in the keeper set, so one keep is one tile.
`key()` / `keysOf` count that burst as one, and the position reads `Scene 2 of 4 · 3 of 5`. There
is no stack badge on the strip and no gesture that opens the other frames. Pick still draws a
closed stack as one tile (the stacked shadow, the count badge, click or ⇧→ opens it) with the
time axis beside the rows.

> In Sets v11 and Edit v22, two things on the Edit step.
>
> **1. Nothing picked still opens Edit, on the photo Pick is on.** A shoot can be open with 0
> keeps. The Edit control, ⌘3, and `stepEdit` open Edit on that photo: the cursor in Pick,
> including a closed stack’s cover frame (the kept frame, or the sharpest when none is kept).
> Do not require a keep, a pick, or a non-empty picks pass. Do not show `No photos to edit. Keep
> some in Pick first.`, `No picks yet. Mark photos to keep in Pick.`, `Nothing to edit yet`, or
> `Every photo is set aside` merely because nothing is kept. Those stay for an empty shoot and
> for a shoot whose photos were all set aside. `keep something first` stays on ⇧P only. With
> nothing picked the header stays `All N · nothing picked yet · R sets one aside`, and the photo
> on the canvas is the one Pick was on, not the first photo and not the last Edit cursor.
>
> **2. The filmstrip separates time batches, and a burst is open.** The horizontal strip under
> the photo keeps one run per Pick row, in the same order as the time axis. Between runs, a gap
> wider than the gap between frames, and in that gap the row’s time — `19:50`, `20:25` — the
> same time the axis and the row head already show. The time is there whenever the strip is
> showing, not only on a wide window. Frames inside a run stay close together. A burst in that
> run is open: every frame is its own tile, the way an open stack shows its frames in Pick, not
> one tile for the keep. Nothing in the strip folds a burst back: no badge, no control, no click,
> and no ⇧→ that collapses the frames into one tile. The position counts those frames (`3 of 8`
> is eight tiles). Pick’s grid still closes stacks, and its time axis is unchanged. A burst’s
> Kept frames of a burst still share one edit (`burst ×N`); the strip only changes which frames are drawn.

### How Prompt 21 is checked once its handoff lands

- Open a shoot, keep nothing, stand on a photo that is not the first, press ⌘3 (and click Edit).
  Edit shows that photo. The canvas does not say `Keep some in Pick first.` The strip does not
  say `No picks yet.`
- The same with a closed stack as the cursor: Edit opens on its cover frame.
- ⇧P with nothing kept still says `keep something first`.
- The strip shows `19:50` and `20:25` in the gaps between those batches. A burst is one tile per
  frame, with no control that stacks them. In Pick the same burst is still one closed stack, and
  ⇧→ still opens it.

## Prompt 22 — Straighten can return to 0° (paste into Claude Design)

The crop bar has Ratio, Straighten, Turn, Cancel and Apply. Straighten turns on draw-a-line.
Holding R and scrolling adds to the current angle (`straighten` takes a delta and clamps it to
±45°). Turn (R in Crop) is the quarter-turn of the photo, a different piece of state. Nothing
sets the straighten angle itself back to 0°. `full()` returns angle 0, and no control calls it.
Prompt 20's Reset, when it lands, clears the whole crop (ratio, rect and angle). This is only
the angle: the rect and the ratio stay.

There is no key or handler on the current control that sets the angle to 0, so nothing here can
be wired up. If a free return to exactly 0° cannot be done on the current Straighten control,
the fallback is: snap to the nearest axis (0°, 90°, 180°, 270°), then step 90° at a time.

> In Edit v22, while Crop is open, the straighten angle can go back to 0.0°. That 0° is the
> angle the photo had before this straighten, not another nudge added to the current angle.
>
> On the bar over the photo, the Straighten control (or a control beside it, in Straighten's
> style, not Apply's gold) sets the angle to 0.0° and leaves the crop rect and the ratio alone.
> One undoable crop step, the way dragging a corner is: ⌘Z brings the previous angle back. The
> footer says `Straighten 0.0°. ⌘Z undoes it.` It does not leave Crop, does not apply, and does
> not cancel. Cancel still drops the crop. Apply still keeps it. The rect does not change.
>
> If that cannot be a free return to exactly 0° on the current Straighten control, snap to the
> nearest of 0°, 90°, 180° and 270°, and from then on each press steps 90°. Say which one it is
> on the control. Nothing else changes.

### How Prompt 22 is checked once its handoff lands

- Crop, straighten to about −10°, use the control. The badge reads 0.0°. The crop rect is the
  one from before the press. ⌘Z brings −10° back. Crop stays open.
- If the control snaps instead: from −10° the first press lands on 0°, and the next press steps
  90°.

## Prompt 23 — The crop frame fills the canvas (paste into Claude Design)

While Crop is open the photo and the frame sit in a small box in the middle of the Edit canvas,
with a wide margin around them. Cull is unchanged. The frame is not a hole: the picture shows
inside it.

The crop fit (`box` when Crop is open) insets 48 px under the Ratio / Straighten bar, reserves
12 px at the bottom, then draws the photo at 84% of the space that is left. Straighten's
`rotate` / `scale` cover then letterboxes inside that already small box, so a straightened photo
shrinks again. The handles and the thirds grid are on that box, so the picture has to stay lined
up with them.

> In Edit v22, while Crop is open, the photo and the crop frame fill the canvas up to a small
> margin: just clear of the Ratio / Straighten bar, and about the same margin at the sides and
> the bottom. That is the size while straightened too. The cover scale fills this frame; it does
> not shrink the photo inside a smaller box. The handles and the thirds grid stay on the frame.
> Cull does not change. The frame is not cut out of the picture. Nothing else changes.

## Prompt 24 — The angle sits off the photo, and Crop can change its grid (paste into Claude Design)

While Crop is open, `axOn` is on for the whole crop, not only while the angle is moving. The
readout (`ax.t`, `-10.9°`, and when the cover is large `· keeps n% of the photo`) is a filled
badge (`rgba(22,21,20,0.82)`) at the centre of the picture, 10 px right and 24 px above the
crosshair. On the native canvas that badge is a rectangle cut out of the photo: the page's black
shows through it, the number looks pasted on, and it smears as the angle changes. The crosshair
itself (the solid axis and the dashed one that turns) is fine. The Straighten control on the bar
already shows `angD` (`-10.9°`) off the picture.

The grid is four hairlines, at 33% and 66% each way. There is no other grid and no control to
pick one.

> In Edit v22, two things while Crop is open.
>
> **1. The angle is not a badge on the picture.** While straighten is happening — holding R and
> scrolling, turning the arc outside the frame, or drawing the S line — show the live angle,
> updating as it changes, off the picture: in the margin beside the frame, or on the Straighten
> control. Not a filled box on the trees. When the gesture ends and the angle is not 0.0°, leave
> that number off the picture so the offset from centre stays readable (`-10.9°`, and the
> `keeps n%` line when you already show it). At 0.0°, do not leave a readout on the picture.
> The crosshair can stay. Nothing is pasted over the photo.
>
> **2. A choice of grid lines.** On the crop bar, a control in Straighten's style (not Apply's
> gold) picks the lines drawn on the frame. One at a time: thirds (what it is now, 33% and 66%),
> quarters, golden, diagonals, centre cross, and none. The lines stay hairlines on the frame,
> the same weight as the thirds lines. The handles, the arc, and the dim do not change. Cull
> does not change.

### How Prompt 24 is checked once its handoff lands

- Crop, straighten to about −10°. While the angle is moving, the number updates off the picture.
  After you let go, `-10.9°` is still off the picture, and there is no filled badge on the trees.
  Back at 0.0°, that readout is gone.
- The grid control switches thirds, quarters, golden, diagonals, centre cross, and none. The
  frame and the handles stay.

## Prompt 25 — Sources stays off the row head, and a row is always justified (paste into Claude Design)

Two things in Pick, in Sets v11. Nothing else changes.

**1. Holding Shift does not cover the row head.** Holding ⇧ (about 350 ms, `addBar`), the +
beside the shoot name, and ⌘O inside a shoot open the Sources panel (`data-lumina="sources"`,
`position:absolute; top:58px; left:16px`). The top bar is 52 px, so the panel starts 6 px into
the grid and sits on the row head: the time, the photo count, and the reason on the right
(`21:00 · 6 photos`, `85 → 35 mm`, `9 min gap`). That line is the shoot info for the row. It
stays fully readable while the panel is open — holding ⇧, holding ⏎ (keep, faster), and ⇧⏎
(next unseen row) included. The panel may cover tiles. It does not cover a row head, and it
does not cover the shoot name in the top bar. The head keeps its type, its reason, and its
place; it is not redrawn inside the panel.

**2. A row of tiles is justified, and a tile that does not fit does not slip under.** The tile
line is `display:flex; flex-wrap:wrap; gap:8px` inside a row with
`padding: 0 clamp(16px, 2.2vw, 40px)` and `overflow:hidden`. `layout()` decides how many tiles
fit from a different width: `cullW - 2 * clamp(16, cullW * 0.022, 40)`. `2.2vw` is the window,
not the scroll width, so with the time axis on the content box is a few pixels narrower than
`avail`. The last tile then wraps in CSS on a line `layout()` did not give the row, and
`overflow:hidden` clips it under the row (under the next row’s head, or into the 22 px gap).
That is the white sliver and the tile that disappears off the end of a full row.

Use one width for both: the row’s content box, the same `clamp(16px, 2.2vw, 40px)` padding the
row already paints, measured on the scroll element. A tile that does not fit starts the next
line, and that line is inside the row’s height, fully visible. Do not clip a tile with
`overflow:hidden`.

Every line is justified. The first tile sits on the left padding and the last tile of the line
sits on the right padding, with equal gaps between them (`justify-content: space-between`).
That holds for every row, including a short last line and a line of one. A line never overflows,
and a tile never paints under the next row.

### How Prompt 25 is checked once its handoff lands

- Hold ⇧ on a shoot. The Sources panel opens. The row head under it (time, count, and the
  reason on the right) stays fully readable. The shoot name in the top bar stays readable.
  Releasing ⇧ closes the panel, as it does now. ⏎ held to keep, and ⇧⏎, do not cover that line.
- A row whose tiles would pass the right padding wraps the extra tile onto the next line of the
  same row, in full. No tile is clipped, and none sits under the next row’s head. The tiles on
  each line run from the left padding to the right padding, gaps equal, including a short line.

Reply with the exact blocks you changed, complete, not a description and not a partial diff:

1. The HTML for the Sources panel (`data-lumina="sources"`, the `addBarOn` block) and the row
   (`data-lumina="row"`, the `r.full` block, including the tile line).
2. The JavaScript, as full functions: `layout()`, and any other function you changed (`measure`,
   the row view that sets `r.h` and `r.head`, the tile width).
