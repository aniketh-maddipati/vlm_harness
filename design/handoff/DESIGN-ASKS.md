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

> **9. The Edit step's canvas is native.** The Mac draws the Edit picture itself, in a Metal view
> laid exactly over your canvas rect (no `<img>` on the slider path); the page keeps drawing the
> filmstrip, sliders, facts line and histogram. Please, in the Edit step:
> (a) **Report the canvas rect.** Expose `window.luminaEditRect()` → `{x, y, w, h}` of the canvas
> in CSS px from the page's top-left (or `null` when Edit isn't showing), and call
> `lumina.edit.layout(rect, visible)` on layout and on resize. Leave the canvas area empty (a
> transparent or dark box) so the native view shows through.
> (b) **Tell the Mac what the sliders do.** On entering Edit for a photo call
> `lumina.edit.enter(p.path, lookString)` (and `lumina.edit.leave()` on leaving); on every slider
> value call `lumina.edit.look(lookString, {drag: true})` while the thumb is held and
> `lumina.edit.look(lookString, {key: true})` for a keystroke; call `lumina.edit.dragStart()` /
> `lumina.edit.dragEnd()` around a drag. The Mac keeps only the newest value, renders a quarter-size
> picture while dragging and the full one at rest. When the view is zoomed, pass the visible region
> as `{roi: {x, y, w, h}}` in fractions of the frame.
> (c) **Image fallback.** Without Metal the Mac hands you pictures instead: set
> `window.luminaEditImage(url, seq, tier)` and show `url` in your Edit `<img>` (revoke nothing; the
> Mac does). `lumina.edit.facts().canvas` is `'native'` or `'image'`.
> (d) **The facts line.** Set `window.luminaEditFacts(text, facts)` and show `text` at the end of
> the facts line: `canvas: native · raw 9: yes`, then `raw 9 · region` while the loupe refines,
> `refining…` when its first tile is slow, `raw 9 · slowed by thermal state` when the Mac is hot,
> and `raw 9 available · update the shoot?` when a newer decoder is present (a click calls
> `lumina.edit.updateDecoder()`). `facts.raw9` tells you whether RAW 9 is active.
> (e) **Histogram, clipping and the model's facts.** Set `window.luminaEditStats(stats)`:
> `stats.histogram` = `{r, g, b}` of 64 bins, `stats.clipHi` / `clipLo` fractions, and, when the
> loupe has refined a region, `stats.facts = {sharpness, clipHi, clipLo, source: 'raw9-region'}`.
> Draw the histogram and the clipping overlay from these only (they arrive after full-quality
> renders, never mid-drag), and when `facts.source === 'raw9-region'` prefer its sharpness and
> clipping to the JPEG's for that tile's flag words (`soft`, `clipped`) and show `raw 9 · region`
> next to them.
> (f) **The loupe.** While G is held at 100 %, call `lumina.edit.loupe(true, roi)` with the
> visible region (and `lumina.edit.loupe(false)` on release): the Mac refines that region with
> RAW 9 and replaces the picture there.
>
> **10. Detail ▸ noise reduction.** One slider, *Luminance noise reduction* 0 … 100, written into
> the look string as `nr:35` (a develop parameter: the Mac re-develops the base when it changes, so
> a drag on it is slower than the other sliders; treat it as a keystroke slider). While
> `lumina.edit.facts().raw9` is true, hide *Colour noise reduction*, *Detail* and *Moiré* (RAW 9
> ignores them); show them when it is false.
>
> **11. Export's result block.** Show `result.decoder` when it is set (`raw 9`, or
> `raw 8 + raw 9 · 1 file fell back`, or `raw 9 · slowed by thermal state`) as one line under the
> counts.

## How each ask is checked once the new handoff lands

- 1: `Tests/web/plumbing-harness.mjs` and `probe.sh smoke` (`app-smoke`: the Save screen shows the row before any save). Remove the `wf` block in `plumbing.js`'s view loop.
- 2: `probe.sh edge` with a case-sensitive fixture (the v3 `app-xmp-both` scenario, rewritten for v5).
- 3: `__lumina.unsaved()` in `plumbing.js` becomes a call to `window.luminaUnsaved`; the contract scenario checks it exists.
- 4, 5: by eye.
- 6: a probe Tab walk scenario.
- 8: `probe.sh scroll` (`scroll-read`: read-end.json shows no cursor move and under 200 px scrolled by the app; the keep
  made while reading survives), `Tests/web/plumbing-harness.mjs` (during read / reopen during read). Then drop
  plumbing's `readMoved` / `stay` handling and its refresh pacing in `grow`, and review ONDIR.
- 7: `probe.sh scroll` (`scroll-fast`, `scroll-fast-2560`: blank-tile % and upscale min per tile size) and the WebKitGTK
  sandbox's `scroll` suite; `card-clock.json` measures unchanged in both modes. Then drop plumbing's warm-ahead
  block (c) and review its `readOne` repeat (a) against the new ONDIR.
- 9–11: `Tests/web/plumbing-harness.mjs` (the `edit:` checks, image path), `probe.sh edit` and `probe.sh raw9`
  (`edit-canvas`, `raw9`: today they force the canvas up with `lumina.edit.layout(rect, true, {force: true})`
  because the page has no Edit step; once it does, replace that with the page's own step change and
  `luminaEditRect`), and the contract scenario gains `luminaEditRect`, `luminaEditImage`, `luminaEditFacts`,
  `luminaEditStats` in its hook list. Then drop plumbing's `pollRect` fallback.
