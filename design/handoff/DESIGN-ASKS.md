# Design asks for the next handoff (v7)

Status: open. Paste the prompt below into Claude Design, download the new handoff zip, then run
`bash Scripts/sets_sync_design.sh "<zip>"` (add `--record` once you've approved the new look).

The Mac app ships `Lumina Sets v3.dc.html` byte for byte. Anything visible has to change in the
design, then sync here with `bash Scripts/sets_sync_design.sh <zip>`. The prompt below can be pasted
into Claude Design as it is. Every item was found by the probe harness against v6 (2026-09-28).

---

## Prompt to paste into Claude Design

> Update `Lumina Sets v3.dc.html` and `lumina-core.js` for the Mac app. Keep the look, keys and
> wording otherwise unchanged. Keep the sample shoot for when the page runs in a browser.
>
> **1. App data contract.** When `window.lumina` exists, the page is running inside the Mac app. Read real data from it and don't show sample data. When it doesn't exist, keep today's sample behaviour so the prototype still works in a browser. Fields:
> - `lumina.app` (true)
> - `lumina.debug` (bool)
> - `lumina.card`: `{ name, photos, bytes, sony }`, or `null` when no card is in
> - `lumina.shoots`: recent shoots as `[{ id, t, d, cam, n, src, where }]`, the same shape as `SHOOTS`
> - `lumina.open(id)`: reopen a recent shoot
> - `lumina.persisted` (true): decisions are saved per shoot
> - `lumina.workingFiles()`: Promise resolving to the byte count of Lumina's own files for the open shoot
> - `lumina.removeWorkingFiles()`: removes those files
>
> **2. Empty shoot.** Inside the app, the page starts with 0 photos until a folder or card is opened. Today every screen reads the current photo (`c = this.f()`), which throws `TypeError: c.id` with 0 photos. Design empty states for Open, Cull, Edit and Export, and make keys that need a photo do nothing.
>
> **3. Card panel from data.** Replace the hard-coded "Sony α7 III card" and "721 photos · 11.3 GB" with `lumina.card` (name, photo count, size). For a non-Sony card, show a quiet line: "Only Sony cards are supported in this beta". With no card, don't say "copy": the beta reads in place. Replace "Insert a card to copy it · or open a shoot below".
>
> **4. Remove the demo layer when `lumina.app` is true:**
> - the "prototype · C pull card" chip
> - "C pull / insert card" in the Open key bar
> - the key C handler and `simCard`
> - `impStartOld`
> - `localStorage` load and save
> - the X→E `Proxy` in `onKey`
> - zip downloads and the strings "downloaded as lumina-xmp.zip", "Unzip into the folder…" and "Open this page in its own Chrome tab"
> - the JPEG note "JPEGs come from the 1616 px preview inside each ARW. The Mac app will render from the RAW."
> - "save test data": show it only when `lumina.debug` is true
>
> **5. Wording (ADDENDUM §4):**
> - The L-hold badge "out?" should become "not suggested", or "reject?" if you prefer.
> - "previewing {look} · ⇧A apply" should become "showing Auto · ⇧A apply".
> - The story line "doesn't change keeps or export" should become "doesn't change keepers or export".
> - Replace "Nothing saved to disk. Keepers and previews live in this tab only." when `lumina.persisted` is true, e.g. "Saved for this shoot · reopen it from Open".
>
> **6. Working files after export.** Show "Remove Lumina's working files (N MB)" for real shoots too. Take the size from `lumina.workingFiles()` and call `lumina.removeWorkingFiles()`. Today it only appears for the sample (`cleanShow: !this.real`), with made-up sizes.
>
> **7. `lumina-core.js`: grouping checklist gaps,** each with a fixture in `lumina-core.fixtures.json`:
> - **Bursts:** the α7 III records whole seconds only. A frame 1 s after a burst currently joins it (a 10-frame burst becomes 11). Decide the rule, and read the Sony `SequenceNumber` when it's present.
> - **Unreadable previews:** a missing, tiny or corrupt preview is currently dropped as "unreadable", with no placeholder, and it can't be exported. Keep it as a photo with a placeholder and a flag.
> - **Two bodies in one folder:** the checklist says sort by body serial, then time, then file number. `parseHead` doesn't read the serial (EXIF 0xA431).
> - **Wrong clock / time zone:** add "shift shoot time", with UI and keys.
>
> **8. Scrolling speed in Cull (60 fps at 721+ photos).** Measured in the app on a real 721-ARW card: Cull scrolls at p95 26–28 ms per frame (about 30 fps; the target is 16.7 ms), and the page holds about 0.9–1.1 GB. The cause is in the page: while you scroll, `cullScrolled` runs a scroll-follow computation every animation frame, and its `setState` re-renders every row and tile. Please:
> - render only the rows near the viewport (keep rows above and below as fixed-height spacers, so the scrollbar and positions don't jump);
> - skip the scroll-follow `setState` when the focused row hasn't changed.
>
> The look must stay the same: the app checks every screen pixel for pixel. (CSS `content-visibility` was tried from the app side. It cut memory about 15%, but it changed text anti-aliasing on the badges, so it's out.)
>
> **9. Window chrome.** The Mac window has a standard title bar, so the page area is 1440×856 in a 1440×900 window. Tell us whether you want a full-bleed page. If so, the top bar needs about 80 px clear on the left for the red, yellow and green window buttons.

>
> **10. Exposure story image quality.** The story cover and photo blocks use `byId[id].src`, the 360 px grid thumbnail (JPEG 0.82), so they look grainy when shown large: the cover is about 1400 px wide. Use `byId[id].lg` (the 1616 px embedded preview, which the Large view already uses) for the story cover and blocks, and keep `src` for grid tiles only. Later the app can supply a full-resolution render the same way.
---

## How each ask is checked once the new handoff lands
- **1, 3, 6:** probe `app-*` scenarios read `window.lumina`, and `plumbing.js` stops patching `SHOOTS` once the page reads the contract.
- **8:** `LUMINA_CARD_DIR=… bash Scripts/probe.sh card` paces Cull and Edit scrolling on a real card, failing above p95 17.5 ms.
- **2:** `Tests/probe/scenarios/app-empty-start.json` (fails today, is expected to pass on v7). The app then switches its sample default off (`SetsRootView.showsSample`).
- **4, 5:** the sync script's wording and demo-layer audit.
- **7:** `node lumina-core.test.mjs` plus `Tests/probe/scenarios/edge-*.json`.
