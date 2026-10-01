# Design asks for the next handoff (after v5)

Status: open. Paste the prompt below into Claude Design, download the new handoff zip, then run
`bash Scripts/sets_sync_design.sh "<zip>"` (add `--record` once you've approved the new look).

The Mac app ships `Lumina Sets v5.dc.html` byte for byte. Anything visible has to change in the
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

## How each ask is checked once the new handoff lands

- 1: `Tests/web/plumbing-harness.mjs` and `probe.sh smoke` (`app-smoke`: the Save screen shows the row before any save). Remove the `wf` block in `plumbing.js`'s view loop.
- 2: `probe.sh edge` with a case-sensitive fixture (the v3 `app-xmp-both` scenario, rewritten for v5).
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
