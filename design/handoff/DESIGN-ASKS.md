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

## How each ask is checked once the new handoff lands

- 1: `Tests/web/plumbing-harness.mjs` and `probe.sh smoke` (`app-smoke`: the Save screen shows the row before any save). Remove the `wf` block in `plumbing.js`'s view loop.
- 2: `probe.sh edge` with a case-sensitive fixture (the v3 `app-xmp-both` scenario, rewritten for v5).
- 3: `__lumina.unsaved()` in `plumbing.js` becomes a call to `window.luminaUnsaved`; the contract scenario checks it exists.
- 4, 5: by eye.
- 6: a probe Tab walk scenario.
