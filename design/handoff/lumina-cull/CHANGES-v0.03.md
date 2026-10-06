# CHANGES v0.03 (Sets v9 + Edit v22)

Built against the app contract (branch claude/v8-sync @ 92af4b6). The design is the source of truth. BRIDGE-v0.03.md has the exact call shapes.

## Roadmap and triage of the 9 asks

| # | Ask | Status | Why / what changed | Files | How the app checks it |
|---|---|---|---|---|---|
| 1 | Edit drives the native canvas (canvasRect, preview, prefetch, drag, roi, luminaPresented) | **Done** | Edit v21 made none of these calls. Edit v22 makes all of them and defines the four hooks (BRIDGE-v0.03 §1). In a mock bridge, 100 slider events gave 1 preview, and the look strings were canonical (`ev:+5.00 con:+33`). | Lumina Edit v22 | plumbing-harness `edit:` checks on the page's own calls; drop `pollRect` |
| 2 | Real Edit step + canvas rect for it | **Done** | ⌘3 / `stepEdit` already existed in v8. New: `luminaStep('edit')`, and Edit reports its own rect, so the forced layout is gone. | Sets v9, Edit v22 | probe.sh edit / raw9 use `stepEdit` |
| 3 | Self-test: drop "P again un-keeps" | **Done** | Replaced with v8's rule, "P on a kept photo keeps it and moves on". Added a step/pass state check and a row-key check. | lumina-selftest.js | `?selftest` passes all checks; selftest.json expects 0 failures |
| 4 | Storage meter shows only the settled total | **Done** | The 1 s memo is gone. The scan runs again after each write, the preview count is live, and a preload redraws. In the app the number is blank while a removal is being measured, with no timers. | Sets v9 | probe.sh screens 34/34 without the `_cpAt=0` step |
| 5 | CHANGES-v0.02 §9 cases in the handoff's tests | **Done** | 19 new cases, all passing: <8-byte head, tiled and strip previews, RGB thumb, SONY-less MakerNote, seqImage, soft/blown ×5, sidecars ×3, look string ×5. | lumina-core-v4.test.mjs | `node lumina-core-v4.test.mjs`; delete the app's `Tests/core/v8-core.test.mjs` |
| 6 | Expose the workflow/step state | **Done** | `luminaState()` gains step, pass, funnel, kept, show, tray, rowsSeen, passDone, autoAdvance, reading… A `flow` event fires on change. | Sets v9 | contract scenario reads `luminaState().step` |
| 7 | Report moved / stayed | **Done** | `moved` / `stayed` events for split, merge, drag-drop and boundary drags. `readEnd {stay}` reports whether the read kept the reader's place, so plumbing's `readMoved`/stay handling can go. | Sets v9 | scroll-read: no cursor move, `readEnd.stay === true` |
| 8 | Stable row keys + ready tile | **Done** (within the runtime) | sc-for still keys by index (runtime, can't change). `rows` is now the full row list with `row-gap` placeholders, so the index *is* the row and stays put. Rows also carry `data-key`. Tile `<img>` loses `loading="lazy"`. `leadReady` fires when the cursor's tile has decoded. | Sets v9 | probe.sh scroll `rows out of place` with plumbing's `rowKeys`/`readyTile`/`lead` removed |
| 9 | Warm-ahead: page or app? | **Done (page decides what; app decides when)** | Sets sends `lumina.prefetch` on keep, ⇧P and entering Save. Edit sends it on entering Edit and on every cursor move. | Sets v9, Edit v22 | NATIVE-EDIT probes; drop plumbing's warm-ahead block (c) |

## Other changes found while checking the contract
- **Look string grammar fixed (BRIDGE §4).** Prompt 1's text form, extended with Edit's own keys. It replaces the v0.02 "store a string" note, which didn't fix the text form. LookStringTests (Swift) should match `lumina-core-v4.test.mjs`.
- **mergeXmp now also writes `lr:hierarchicalSubject` `Lumina|pass N`.** v0.02 removed the old entry and never added the new one (BRIDGE-v0.02 §6 said both). Port `addKw` again.
- **DESIGN-ASKS 9:** `onCard()` follows `lumina.readingCard` alone. While the card is out, the button says so.
- **DESIGN-ASKS 1:** `workingFiles()` is called when Save opens. The wf block in plumbing.js can go.
- **Load fix:** the meter's storage scan used to run on every render (4 MB+ of JSON) once the memo was removed. It now runs again only after writes.
- **Bridge events are sent on a later task, never inside a render.** Firing them inside a render froze the page.

## Contract §2 items: still provided, unchanged
- All §2.1 members, §2.2 globals, §2.4 commands and §2.7 `data-lumina` markers are unchanged. Two markers are added: `row-gap`, `decoder-note`, `rendering`.
- §2.3: luminaPresented, luminaHistogram, luminaFacts and luminaEditStats now exist while Edit is mounted.
- §2.3: `luminaEditImage` / `luminaEditRect` never existed in v21. v22 defines them as read-only getters (Q1).

## Questions for the app
- **Q1.** What do you expect from `luminaEditImage` / `luminaEditRect`? v22 defines getters (`() => rect`, `() => {rel,url,seq,shown}`). If you meant setters, say so.
- **Q2.** `roi` is in image px only when the photo record has `pw`/`ph`. Edit's photos come from `editShoot()`; please confirm they carry them in the app. Otherwise it falls back to `unit:'norm'`.

## Still open (not in this handoff)
See **REMAINING-v0.03.md** for the per-element list, and *Lumina Design Asks v0.03.html* for the reference.
