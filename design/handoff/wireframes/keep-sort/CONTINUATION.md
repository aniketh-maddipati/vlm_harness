# Continuation — keep-sort wireframes (Harrison + Uday)

**Worktree:** `/Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron`  
**Branch:** `design/keep-input-dock-chron`  
**Paste prompt:** [`CONTINUATION-PROMPT.md`](CONTINUATION-PROMPT.md)  
**Plan (Input dock — done):** [`PLAN-input-dock-chron.md`](PLAN-input-dock-chron.md)  
**Archetype sketch:** `archive/lumina-minimal-mvp.html` (`harrison`, `uday`)

---

## Locked

- No chip strip under Drop; Files not Phone; Rec.709 default for Log; no FCP/ΔE in shipping UI
- Wireframes only under `design/handoff/wireframes/keep-sort/` unless owner promotes
- **Fidelity:** ink/boxes/labels like live Import/Sort — no hi-fi, no photo thumbs, no new palette (see CONTINUATION-PROMPT “Visual fidelity”)

---

## Done (shared spine)

- Click-enable → Input dock; Drop / AirDrop / Android; Sort now multi-vol handoff
- Sort: union chron, Kept dock, Export package shell (Ready N/M + preprocess removed 2026-10-28 — clips are just included)
- Import (2026-10-28): suggested volumes top row (path · files · GB; click opens Files at volume top); Drop + AirDrop; Drop≡dock; **files + directories** drag-droppable; directory enable/drop runs `pullVolume`/`scanPull` — pulls ACCEPT_EXT; **peripheral sense** (also pill + toast; still imported: sidecar, outside DCIM/Clips, non-dominant ext, helpers); non-accept left quietly — **no `off`/skip file class**; Files boot **fully collapsed** at top (no Downloads/phone auto-open); pinch Files → icon grid; Log prep across all suggested in SD→SSD priority, evict cache on Sort for vols not included; Prep is **Log only**; bottom “Suggested” chip gone; no “Rec.709 for Log” CTA
- README + MODEL-EVAL

### Import pull criteria (owner 2026-10-28)

- **Pulled:** `ACCEPT_EXT` (RAW, stills, video, + `lrv`/`srt`/`xmp`).
- **Also (peripheral, still imported):** sidecar/proxy; path outside DCIM/PRIVATE/Clips/MEDIA when that tree exists; ext not in the volume’s dominant primary set; tiny helpers. UI: muted `also` pill + “may be outside main shoot” in the toast — never a reject class named `off`.
- **Left:** fails accept — not pulled, no file class / no strike-through.

```bash
python3 design/handoff/wireframes/keep-sort/hotserve.py --port 8788
```

---

## Consolidated: one product, model-organised

Harrison (A/B-cam + drone, clocks off) and Uday (cam + drone, group by place) are the **same dump with the same needs**, so Sort serves both with models instead of modes. **The scene toggle is gone.** One chronological axis for every docked input, then:

| Need (both users) | How Sort covers it |
|---|---|
| Everything on one time axis | Union chron axis for all docked inputs (existing spine) |
| Clocks agree across bodies | **Auto clock-align** on load, in three beats: pill names the skew ("clock drift · ssd ~6 min fast") → shift applies, moved clips flash a dashed outline → receipt ("ssd back 6 min · clocks aligned · N inputs"). No manual steppers |
| Keep → package that opens in NLE | **Stringout package** — keeps in time order, one timeline, opens in your NLE |

**Effort reason (shared):** open the NLE on selects already in time order, not a flat dump.

**Demo mechanics (wireframe stands the model in):** `HIDDEN_SKEW` seeds three edge cases (`ssd: −6 min`, `drone: +3 min`, `phone: +50 s`). Auto-align pulls them onto the shared clock. No real sync model runs in the wireframe.

---

## Done this pass

1. **Consolidated** the Harrison/Uday scene-toggle demos into one self-organising Sort: removed `SCENES`, the toggle UI, and `?scene=`; one dump covers both users.
2. **Auto clock-align** (`autoAlign()`, `clockSkews()`, `fmtDelta()`): three beats — 900 ms after boot the pill names the skew while the axis stays as stamped; +1.4 s the shift applies, moved clips get `c.moved` (dashed outline, shares `.inbound` styling) and the axis re-sorts; receipt pill, flash cleared +2.6 s.
3. **Removed the chapter feature entirely** (owner correction — simplify): no axis chapter headers, no chapter binning, no Export chapter list, no rename handler, no `chapterMap`/`chapters` state, no `.chapter`/`.ch-*`/`.xch` CSS. (The Clean flow's "Review not kept" Soft/Rest screen stays — it groups rejected clips, not the axis.) Time-gap breaks later returned as **bare hairlines** (no labels), and the per-source clock-stepper chips were removed — see the two 2026-10-28 sections below for the current surface.

## Bigger cards, pills, no stack labels, less motion (2026-10-28)

Owner pass on feel: "jittery … bigger cards … no stack labeling, basically separated by time … maximize space on card, minimize space on info, just use pills … the minimum important for log processing and color grading."

- **De-jitter:** `--dur` 320→140 ms, `--dur-fast` 180→100 ms; removed every layout-animating transition (tile width, tile gap, thumb height, run margin/padding, canvas padding) so pinch reflows instantly; hover `translateY` lift gone; `card-in` is a plain fade; the per-run `animation-delay` stagger is gone (tiles no longer carry the `animation` at all).
- **Bigger cards:** `TW` ladder 148–300 → 168–356, column cap 6 → 5, width clamp 320 → 400 px (typical grid now ~333 px tiles).
- **No stack labeling:** the stack row is a bare hairline (`<div class="stack">`, no count/title/rename/`state.stacks`); the time-gap binning (`stackMap`, `gapMin` 20 min) stays only to place the line. Export dropped the stack-name list — back to plain stringout copy.
- **Pills:** tile info is one row — name + pills for **duration · Log · soft** (the minimum for log-processing/grading decisions; Log is the ink-outlined pill since it flags the Rec.709 transform). GB left the tiles (still in the dock sum + Export). Same pill idiom on Kept dock tiles and the large view's info row (which keeps its fuller meta: src · time · dur · GB · Log · soft).
- **Steppers gone (same pass):** the per-source −/+ clock-shift buttons, offset readouts, `shiftSrc`/`fmtShift` and the chip click handler are removed. `state.shift` stays as the model's internal record (`clipSec` reads it). Later the same day: the header's source chips themselves (phone · drone · card · ssd) were removed too — pure decoration once the steppers were gone — so the align pill is the only clock surface. `paintSrcChips` and `.src-chips`/`.sc` are deleted; `SRC_LABEL` stays for the pill copy, and a clip's source still appears in its thumbnail stand-in and viewer info pills.
- **"Place" → "Saving to" (same pass):** the fold-bar pill reads "Saving to \<dir\>"; the footer's "not kept stay on Place" became "not kept stay in the folder". `state.place` keeps its name internally; the Export sheet already said "To \<dir\>/Package".

## Pinch smoothness, log pills, fuzzy cards, Add-at-will (2026-10-28, second pass)

Owner: "the pinch zoom jitters and conflicts with drag select … need log info as a pill and more fuzzier boundaries for the cards … a button to add more to the sort at will."

- **Pinch, smooth:** the ⌃/⌘-wheel path was sign-based (`Math.sign(deltaY) × 0.18` per tick, threshold 0.28, residue kept) — two ticks fired a level and gesture-end wobble flapped it back. Now magnitude-based (`PINCH_STEP` 48 px of travel per level), the accumulator resets to zero when a level fires (no residue = built-in hysteresis), clamps at ±STEP at the ends, and clears after 180 ms of quiet. The two-finger pointer pinch applies a level only 0.6 past the one already applied (boundary wobble can't flap). Verified with synthetic wheel events: two −20 ticks no-op, the third steps one level, +8×3 wobble holds, a real reverse steps back.
- **Pinch vs drag-select:** pinch never fires while a marquee or a rod scrub owns the canvas (`mq.on` / `state.scrubbing` guards), and the marquee no longer calls `renderCanvas()` per move — `paintPicks()` diffs `state.picked` onto the live tiles' `.pick` class, so hit rects stop flickering under the pointer.
- **Gamma pill on every card:** tiles, Kept dock tiles and the viewer info row now state **Log** or **709** — a non-Log clip is a fact, not a missing pill.
- **Fuzzier card boundaries:** a card's resting edge is a soft shadow (`--card-shadow`, deepens on hover), not a hairline; radius 12→14 (dock pics 4→8). State marks (on / pick / kept) stay crisp and now compose with the soft shadow instead of replacing it.
- **+ Add clips:** fold-bar button (or `A`) goes back to Import with included vols restored in the dock — add more, then **Back to Sort**. Sort keeps / place / clock shift held in `sessionStorage`.
- **Clock-align proof:** vertical stems **on the time rod** (hollow origin → arrowhead; vertical `src · 6m` label). No was/now, no paths over tiles. Edge cases: ssd −6m, drone +3m, phone +50s. SVG is a 52px axis strip; does not repaint on scroll.
- **Quiet chrome (same pass):** the align pill fades 5 s after its receipt (`.gone`, keeps its space — a story, not furniture); the "every 30 s" pop-in (`ti-say`, the `say` param on `setTi`) is gone — the flashing zoom word is enough; the fold bar title is condensed — "Sort · N · M in".

## Ready + preprocess removed from Sort (2026-10-28)

Owner: "no need for ready and preprocess, just included." Gone from `keep-wf.html`: the Ready N/M pill (`#ready-pill`, `paintReady`), the unread-tile state and its "…" thumbs, the `tickDevelop` preprocess interval that developed tiles near the cursor, `readyDone`/`readyTotal` state and the handoff's ready fields, and `unread` on the demo clips and inbound AirDrop appends. Every clip paints as a normal tile at once. Import later dropped its own RAM/offload UI and Ready handoff fields (thin `preCache` prep only). `soft` (focus flag) stays; it's a clip judgment, not readiness.

## Amber purged from Sort + Export (2026-10-28)

The B&W restraint, applied to the whole Sort page and the Export / Clean sheets: `--amber` is gone from the palette (replaced by a `--danger` variable for the red the `.danger` button already used). Every amber state got a B&W idiom — picked tiles are a dashed ink border (marching-ants), cursor + pick is a heavier ink ring, the marquee is an ink rect with an ink wash, the ti-feed flash / "every 30 s" word / dock focus / dock-tile outline / insert bar / play-mark / inbound outline are ink, the day divider is a plain `--line` hairline (no gradient), run dates are `--mute`, and the Clean sheet's warn is danger red. Left alone: the kept-green accent everywhere, the Rec.709 knob green, and the dock's existing backdrop blur (pre-existing page idiom, not a new addition).

## Full-screen large view + cull grade minimum (2026-10-28)

Owner: large view full screen with grid collapsed into a loupe like Stills; Mask + Heal; research the minimum for colour grading and wire only that.

**Layout (Stills loupe grammar, B&W wireframe):**
- `.body.large-on` is `104px | 1fr` — the chron axis collapses to a thin loupe strip (tiny thumbs, no run marks / rod / pills); the viewer fills the rest.
- Viewer is `stage | 240px rail`: dominant `cv-stage` + rail with name/info, **Mask** / **Heal** tools, grade sliders, Keep, Close.
- Open: double-click a tile (or Kept tile). Close: Esc, Close · Esc, double-click stage (when no tool), double-click empty rail, or pinch out past the coarsest TI.

**Mask / Heal (thin):** toggle buttons; click the stage to place a dashed subject rect (Mask) or a spot circle (Heal). Stand-ins only — not a real mask editor.

**Cull grade minimum (decided):**
- **Rec.709** — already the Log display transform (top-bar switch). Not duplicated as a slider.
- **Exposure** — first cull question on a take (`ev` in LookString).
- **WB** — second-body / mixed light (`wb` temp offset; tint left to the NLE).
- **Contrast** — third and last cull move (`con`).
- Out of scope here: vibrance/sat, curves, HSL, local grade — those belong in the NLE after the stringout. Wireframe stores per-clip `{ev,wb,con}` in `state.looks` with no pixel math (B&W ink stage).

**Right rail (wider + furling + files):** default `minmax(320px, 360px)`. Mask·Heal and Grade are `<details class="furl">`. Files lists every clip (src · time · dur · GB · gamma · soft · kept); truncated to 5 with **…and N more** — one click unfurls, double-click furls (click timer so a double-click doesn’t unfurl-then-furl). Click a file row → that clip on the stage + loupe scroll. Import Files tree uses the same grammar on **… N more** / **All files**.

## Clock-align proof — vertical on the rod (2026-10-28)

Replaced elbow-over-tile paths. After the correction beat, **vertical stems on the time rod**: hollow origin = as stamped, arrowhead = aligned, vertical label `src · 6m` (no was/now). Edge cases: ssd −6m, drone +3m, phone +50s. SVG is a **52px axis strip inside `.canvas`** (scrolls with content, no scroll repaint) — never over tiles, never fights canvas smoothness. Click a stem focuses that skew (pill + `.skew-focus`).

## Continuous pinch + fill-frame cards + hover play (2026-10-28, third pass)

- **Pinch, continuous:** wheel and two-finger pinch share one model. Travel toward the next TI level scales the sheet live (compositor `transform` on `.canvas`, origin at the pointer, no reflow) toward that level's card size (`levelScale` via `tileSize(ti)`); regroup-only levels get a small breath, the ends give 2% and stop. Crossing a level lands it, resets the accumulator (no residue → no flap), drops the transform in the same frame and re-anchors the tile under the pointer (`pinchAnchor` → `scrollTop` fix). Release settles back to 1 in `--dur`. Pointer pinch measures from the spread at the last landed level (`PINCH_RAW` 0.8), so a reversal needs a full level back. Still never under marquee / rod scrub; loupe holds still in large view (pinch-out past the top still closes it). Verified: −20/−20 previews 1.048→1.097, the third lands 15 s at 356 px with the anchor tile within 2 px, ±8 wobble holds.
- **Fill-frame cards:** the meta row is gone; the frame is the card. Name + dur · Log/709 · soft ride the frame's bottom edge as paper chips (`.frame .ov`) — overlay chosen over under-line (zero extra height, readable over any picture). State marks moved to an `::after` ring (`--mark`) so on / pick / kept stay crisp over the frame. One `frameHtml()` for sheet tiles and Kept dock tiles.
- **Hover preview play:** 120 ms rest on a tile (sheet or dock) → `.playing`: ink play mark + 2 px hairline running the take's length (`--pdur`, clamped 2–12 s). Stand-in, no decoder. Off under marquee / pinch / scrub / drag and on the loupe strip. Double-click still opens large view.

## Solid axis + dotted offset brackets (2026-10-28, fourth pass)

Owner: "make the time axis more solid and accommodative of the off-shoot dotted brackets parallel that indicate the different time offsets that were corrected … not on the frames."

- **Solid rod:** 4 px ink spine (0.78 → 1 on hover/scrub), positioned by `--rod-x` (46 px). Each run's `.dot` is now a **node on the rod** (paper ring, ink border; kept-all fills green) instead of a dot under the label. `--gut` widened to `clamp(132px, 15vw, 164px)`; run labels start at `--rod-x + 16px`.
- **Offset brackets:** each corrected source gets a **dotted bracket in its own lane left of the rod** (12 px lanes, first drift closest): leaves the rod at the as-stamped time (hollow circle on the rod), runs parallel, returns with an arrowhead into the rod at the corrected time. Label `src · 6m` is rotated in the lane and knocked out of the dots. Never on frames; SVG still lives inside `.canvas` (scrolls with content, no scroll repaint); click a bracket still focuses that skew. Supersedes the "vertical stems on the rod" drawing — same proof, now off-shoot brackets.

## Brackets carry the info · T7 edge cases · large view · defaults (2026-10-28, fifth pass)

- **Align pill gone** (`#align-pill { display:none }`). The dotted brackets are the whole clock story: each label reads `T7 A-cam · back 6 min`, `T7 B-cam · fwd 1 h · time zone`, `T7 FX3 · fwd 50 s`. As-stamped end is measured **live** (beside the in-sync clip nearest the file's own stamp), so brackets stay true at every zoom; a correction inside one run still gets a 22 px bracket. Lanes are fixed 12 px left of a fixed rod (`--rod-x` 46) so they never collide when zoomed in.
- **Edge cases all on the T7** (`t7-road` → `ssd`, `t7b`, `t7c`): A-cam −6 min, B-cam +1 h (wrong time zone), FX3 +50 s. Phone and drone are in sync.
- **Default zoom = fewest rows** (`fewestRowsTi()` at boot, ties keep the finer level).
- **Keep / not kept only:** dock reads "Keep · …", picks toast "N picked · K keeps them", viewer decision is keep / not kept.
- **Large view = old Skim + Stills info:** strip of neighbours on top (position "1 of 32" · frames · keep / not kept), the 16:9 frame centred with an 8-tick scrub line and `00:01.8 of 00:08.2 · frame 1 of 8` under it, hover scrubs; **Clip** column left (source · recorded · duration · size · gamma · focus · decision, plus Files with "…and N more"), **Grade** column right (Mask·Heal, Exposure·WB·Contrast, Keep, Close). The loupe column is gone in large view.

### Import — ⏎ to Sort · clickable “… N more” · pinch → file previews (2026-10-28)
- **⏎ = Sort now** when the dock holds ≥1 input (plain Enter; not in inputs, not with Preview / Add-source sheet / Prep card open; other buttons keep their own Enter). Works from body, Files rows, suggested cards, volume squares (Enter on an *included* square now hands off; Space still opens it in Files). Nothing staged + focus on page → “Enable an input first” toast. Quiet `⏎` under the Sort now button.
- **“… N more” everywhere** uses one helper `bindMoreClick` → `expandMoreNode` / `collapseMoreNode` (220 ms click timer; dblclick furls “All N files”). Wired on Files rows (list + preview frames) and `.src-more` in the volume panel (note: that panel is never opened today — `unfurledId` is never set — so it’s wired but unseen). `_moreMeta` now keeps `sourceId` across furl/unfurl.
- **Pinch Files = previews, not the tree.** Whole-tree icon grid + coloured squares/kind labels removed. ctrl/⌘-wheel (and Safari gesture*) handled only on `#files-drop` → page/dock/volumes never zoom. Pinch in: 70 px magnitude push flips to previews (accumulator reset + 320 ms lock per flip; jitter test = 0 flips). Only PRIMARY_EXT media files (RAW/stills/video) + their “… N more” render as grey 16:9 frames (ext label, name centred under) in a Finder-like grid per folder; volumes, folders, sidecars stay rows. Further pinch grows frames continuously (`--fs-tile` 120→267 px). Pinch never resizes list text (⌘+/− still does); label reads `previews · N%`.

## 2026-10-28 — Pinch model (smooth zoom)
- Split, as in Stills: plain pinch (⌃/⌘-wheel, two-finger pointer) = card SIZE only; ⌥-pinch or a pinch that starts over the time axis (gutter) = TIME grouping. Mode is locked per gesture.
- Size ladder is independent of TI: `state.zf` = columns dropped from `colsMax()` (≤5, ≥160 px cards) down to one height-capped frame; `zfMax()` stops where the frame stops growing. Axis gutter/labels compact with zf; rodX fixed at 46.
- Size travel is log-scale: rung cost = PINCH_K(60)·|ln size ratio| in wheel px (Chrome trackpad ⌃-wheel ≈ −100·ln scale), so cards track the fingers ~1.7×. Between rungs a live transform scales about the anchor tile; at a rung the layout lands at exactly that size (no visual size jump), scrollTop + a translate (FLIP, glides out ×0.93/event) keep the anchor under the pointer. Travel carries across rungs; ends hold still (no rubber band). Quiet 200 ms → momentum (140 ms projection) lands the nearer rung with a 240 ms ease-out.
- Time ladder is finer (27 levels, 1 s … 2 days; TI_DEF = 7 = 30 s), steps every 18 px, accumulator resets per step, run under the pointer pinned by scrollTop.
- Collapsed grouping (largest run ≤ 2 rows): `effZf()` grows frames until that run, as a balanced grid, fills the screen height (grow-only; a pinch-out sets `state.fitOff`, cleared by a regroup).
- `.canvas-wrap`: `overflow-anchor: none`; `overflow-x: hidden` outside the large view.
- `?debug=pinch` → `window.__pinchLog` (per event: mode, ti, zf, travel, scale, FLIP offset, anchor rect, ms).

## Masks in the large view — Lightroom mobile, applied to video (2026-10-28, sixth pass)

- **Masks panel** (right column, replaces the Mask stand-in): list of masks on the clip (glyph · "Mask 1 · Subject" · N keys · ×) and `+ Subject · + Sky · + Lasso · + Linear · + Radial`, then **Overlay · O**, **Track**, **Heal**. Selecting a mask scopes the Exposure / WB / Contrast sliders to it (`state.looks["<clip>#<mask>"]`); clicking off it returns to the whole clip.
- **Interactive outlining** on the stage (SVG over the frame, 1600×900 units): the selected mask is marching-ants ink with point handles. Drag a point to reshape, click an edge to add a point, ⌥-click a point to remove it. Radial = two rings with centre / width / height handles. Linear = start, mid and end lines with two handles, washed beyond the start. Lasso = draw freehand; the stroke thins to ~14 editable points.
- **Video:** every edit writes a **key** at the current scrub time (snaps within half a frame); between keys the outline glides (point-for-point interpolation, and new points are inserted in every key). Keys show as diamonds on the scrub line (selected mask solid, others hollow). Subject and Sky are found **and tracked** on creation (8 keys, stand-in drift); **Track** re-tracks any mask from the current frame. Hover-scrub pauses while a mask is selected or the lasso is armed, so the frame never slides under the outline.
- **Overlay (O):** an ink wash over the masked areas (Lightroom's red overlay, in B&W). **Esc** leaves the lasso / selected mask before it closes the large view.
- State: `state.masks[clipId] = [{ id, kind, name, keys:[{ t, g }] }]`, `maskSel`, `mkOverlay`, `mkDraw`. Stand-ins only: no real segmentation or tracking.

## 2026-10-28 — Final Cut package + Rec.709 (`lumina-pipeline.js`)
- Owner: "run rec709 and the package builder for fcpx" — Final Cut export is now explicit (overrides the old no-FCP-claim note for Export; still no ΔE claims).
- `lumina-pipeline.js` (no deps; ES module + `window.LuminaPipeline`, loaded with `<script type="module">`): `slog3ToRec709(rgb)` = Sony S-Log3 → linear → S-Gamut3.Cine→709 matrix (linear light, matches Sony's published matrix to 5e-5) → tone map → BT.709 OETF. Tone map = neutral axis of Skim's `SL3T` (fitted to Final Cut 12.4's Sony camera LUT). Input = video-range code (cv−64)/876. Reference: 18% grey (cv 420) → 0.488, black (95) → 0.026, 90% white (598) → 0.899. `buildCube(33)`, `gammaOf(clip)` (profile → Sony M01.XML CaptureGammaEquation → wireframe `log` + source).
- `buildFcpxml(handoff)`: FCPXML 1.10 (as Skim, import-proven), one event + one project, kept clips in axis order (file time + `state.shift`), whole-frame rational times, timeline at the most common named format. Sony S-Log3/S-Gamut3.Cine assets carry `customLUTOverride="35 (Sony_SLog3_SGamut3Cine_v2)"` (Final Cut's own Camera LUT, from Skim LOCAL-CHANGES 143/145); drone D-Log arrives as shot. `buildPackage` → `.fcpxml` + `.cube` + README (paths are placeholders: `ssd/t7b/t7c` → `/Volumes/T7/Road trip/Clips/{A-cam,B-cam,FX3}`); page downloads one stored zip.
- Page: Export sheet, Final Cut selected → quiet line `Final Cut · N clips · Log → Rec.709 LUT applied`; the Rec.709 switch drops the override. Make package → Open in Final Cut downloads `<place> stringout.zip`.
- Tests: `node lumina-pipeline.test.mjs` (18 pass; xmllint against `fcpxml-1.10-subset.dtd`, a hand-written subset, not Apple's DTD). Needs a real Final Cut import: mixed 29.97/23.98 in one spine, the override on these placeholder files.

### Import — drag any file / directory anywhere · auto-sort · consent sheet (2026-10-28)
- **Every Files row drags** (list rows + preview frames; “… N more” never). A drag carries the whole selection as `application/x-lumina-nodes` (old source/dir/files types still set).
- **Targets:** Drop, the dock, and the **whole page** (document drop; Files itself ignores row drags). While dragging: one dashed ink edge + one line `Drop anywhere · N files` (`body.page-drop`, capture-phase dragover, 350 ms idle hide). OS drops show `N items`.
- **Auto-sort:** `handleNodeDrop` → `countPull` (ACCEPT_EXT, `… N more` counted by sample ext) → `commitNodeDrop` enables the owning volume(s) via `enableVol` (pull + “also” sense unchanged). Toast `Added N · left M out (not media)`. Inclusion is still per volume, so dropping one file brings in its volume; the toast counts only what was dropped. OS files: accepted ones land through the Phone/AirDrop path, the rest are left out.
- **Consent sheet** (`#drop-sheet`, B&W, Esc / backdrop = Cancel, ⏎-to-Sort blocked while open). Not valid (no readable media anywhere): “<dir> has no clips or photos Lumina can read” + OK, nothing added. Loose subfolders: one checkbox per subfolder (on if it holds media), first 3 then “… N more” (click unfurls, double-click furls), buttons Cancel / Only this folder / Include subfolders. Camera trees (card / drone / phone, DCIM / PRIVATE / Clips / MEDIA / NNNMSDCF) never ask. Several dirs in one drop: one grouped sheet. Unchecked subfolders get `skip`, and `scanPull` passes over them quietly (no reject class).
- Demo data: ~/Pictures now has Family / Exports / Scans (pdf only) / Screenshots / Wallpapers. Documents (pdf only) is the invalid case. T7 and Lightroom ask about Road trip and Selects.
- Fixed: a stale `dragId` (rows re-render on dragstart, so their dragend never fires) could enable the last volume on a later OS drop. It is now cleared on the document drop/dragend.
- Not done: real Finder **folders** (only file names are read; no `webkitGetAsEntry` walk).


## Selection + Export + fluid scrub + Skim loupe (2026-10-28)

Owner: marquee stuck / brighter picks / persistent only Shift·⌘A·⌘⇧A; Export full-bleed facts; fluid rod; dblclick pick toggle; Skim large grammar.

### Selection grammar
- **Persistent `state.picked` only from:** Shift (range / shift-marquee), ⌘A (all), ⌘⇧A (current run/row), ⌘-click toggle, **tile dblclick toggle**, run-mark click.
- **Ephemeral:** plain marquee paints bright picks but `pickSticky=false` — cleared by click-outside or plain tile click (cursor only).
- **Tile dblclick** = pick toggle (persistent). **Empty-canvas dblclick** = clear all picks. Large view opens with **Enter** (not tile dblclick). Esc still clears picks.
- Marquee ends cleanly (`mq.on` false, class removed, pointer capture released). `paintPicks()` during drag; no canvas rebuild per move. Pinch still gated on `mq.on` / `state.scrubbing`.
- Picks: brighter ink wash + solid ring (B&W); marquee rect stronger wash.

### Export (full-bleed, facts only)
- Full-viewport `.export-stage` with spacing `--ex-edge` / `--ex-gap` / `--ex-pad` (clamp). Panes: XML · Folder · Save/Clear. Responsive 3→2→1.
- **XML rows** = filename + path + **fact chips** (FCP/Premiere, N keeps, Rec.709/Log, LUT, Mask, Heal, graded — or `keeps` if nothing edited).
- **Destination** always visible (top path + foot dest). FS flows like Import (navigate/pick folder). **New folder** = `YYYY-MM-DD_<place>_FCP|Premiere`. Save summary = counts · path · XML names · chips — no prose. Clear ledger = package/XML leftovers; **Delete media · off** (deprecated).

### Fluid time rod
- Continuous scrub: playhead tracks pointer Y 1:1 (transition off while `.scrubbing`); rAF-coalesced moves; light `.on` cursor paint — **no** `renderCanvas`/`selectClip` per move; viewer/dock commit on pointerup. Fatter 36px hit; proof marks `pointer-events:none` so they never block the rod.

### Large view (old Skim Clip)
- Neighbour strip + 16:9 stage + scrub bar + time `mm:ss.s of … · frame N of 8`. Facts as pills. ←→ scrub in large; ⇧←/⇧→ (shift+arrows via selectClip) neighbours; Space play; Esc / dblclick stage / pinch-out close; Enter opens.

## Minimalist large view · pen-first outlining · Stills-size rail (2026-10-28, seventh pass)

Owner: "simplify … pare it down and put the frame front and center", "go minimalist", "next level intuitive and accurate tracing like you would with a pen", "shortcuts to get larger areas", "break up the clip … clicking [layers] out and then back in at will", then "take a page out of the current stills ux and make the right pane much larger controls". Commits `ee5601bd`, `d67487bf` on `design/keep-input-dock-chron`.

- **Layout:** `.app:has(.body.large-on)` hides the fold bar, dock and foot. `.lv-main` = frame column | **340 px** `.lv-rail` (280 under 1100 px). The frame is `min(100cqw, (100cqh − 96px) × 16/9)` in a size container, scrub line + time + neighbour strip under it. Rail: name + × · `.lv-sub` (src · time · dur · gamma · kept) · `.ed-tabs` Color / Outline / Heal (`state.ed`, keys 1 / 2 / 3, `setEd`) · one `.ed-pane` at a time · Keep (46 px) at the bottom.
- **Color:** `state.looks[key] = { ev, con, wb, sat }`, key = clip or `clip#layer` (`gradeKey`). Rows are `.sl` (Stills' grammar): label + value, full-width track with a centre tick, fill drawn from centre, knob; **the row is the pointer surface** — drag (ev 1 stop / 120 px, others 1 / 2 px), dblclick = 0, horizontal wheel nudges, ← → / ⇧ step a focused row, `0` zeroes. `G_MAX` sets each row's range. `.ed-target` chip names the target (× back to the whole clip). Reset all.
- **Outline:** layers are the old masks (`state.masks[clip]`, `kind: "lasso"` + `pts`) plus `auto` / `hand` / `fill` / `inv` / `out` flags. `findLayers()` adds named layers by source (`FIND` table) and tracks them. The stage is always the pen in Outline (`state.ed === "mask"`): pointerdown starts `mkDrag = { pen, pts, w, pick, on, grow, carve }`; move smooths (0.3 of the last point), snaps 60 % toward an outline point within 0.025 when `state.snap`, tracks pressure; the **loupe** (`#pen-loupe`, 132 px, 3×) copies the mask svg's body + lines around the tip. Up: travel < 0.02 = a tap (pick / unpick, or **fill a region** when nothing is under it); ⇧ / ⌥ = `brushRun` (outline points under a 0.05 brush move out from / in toward the layer's centre, every key); a stroke whose ends sit within 0.05 of the picked layer's outline = `redrawRun` (the shorter arc between the nearest points is replaced; other keys move with their centroid); otherwise the thinned stroke (≥ 0.022 apart) closes into a new `Traced N` layer, tracked. Rows: glyph · name · found / traced · **in / out dot** (`data-mk-io`, ⇧-click solos); out layers paint `.mk-body.out` with the `#mk-hatch` pattern and the preview label says `· N out`. Invert = even-odd body with the frame rect. Delete / ⌫. Hint line changes with the state.
- **Heal:** unchanged stand-in (one dot per clip), now its own pane with Clear.
- Gone: `paintFacts`, `paintFileList`, the furls, `#v-mask` / `#v-heal` / `#mk-track` / `#mk-add`, `addMask(kind)`, `state.mkDraw`, `<input type="range">`.

## Editor stand-ins made honest (2026-10-28, eighth pass)

NEXT 1 (continuous pinch) and NEXT 2 (fill-frame cards + hover play) had already landed (third pass, then the pinch model); checked, not touched.

- **Redraw a run, by shape:** `redrawRun` replaces the run at this frame, then in every other key carries the same stroke by that key's own run ends (start / end offsets blended along the stroke). The rest of each key keeps its own outline; point counts stay matched, so it still glides. Verified: a bulge drawn at 0.0 shows at the clip's end with the same shape, moved +252 / −20 units with that key; the other points unchanged.
- **Loupe:** really 3× now (viewBox = 44 px of frame for a 132 px bubble; it was ~1×). It sits **behind the pen** — on the side the stroke came from, direction eased — and swings round the tip near a frame edge instead of covering it.
- **Heal, several spots:** `state.heals[clip] = [{ id, x, y, r, t0, dx, dy }]`. Click adds a spot, drag out sizes it, drag a spot moves it, ⌥-click removes, Clear / Clear all. Each spot is a ring the patch's size with a centre dot and drifts with the take (stand-in follow). Export facts count spots. `healOn` and the single `#v-heal-dot` are gone.
- **Copy / paste look:** ⌘C / ⌘V (and Copy look · Paste in the Color pane). Large view: copies / pastes the target (whole clip or the picked layer). Sheet: ⌘C copies the cursor clip's look, ⌘V pastes onto every picked clip. Toasts name the look (`ev +0.50 · warm +12`); not taken while text is selected.
- **Edits survive + Add clips:** looks, layers and heal spots ride the `lumina-keep-session` handoff; layer / spot ids continue past what came back.

## Space · pinch in the large view · Lightroom-style Color (2026-10-29, ninth pass)

Owner: "large view needs to be done via space and space again to click out. hold space is preview, pinch zoom applies. controls should fill half length screen", then "needs to include color grading controls and fine control of sky blues and exposure correction … LR mobile or DaVinci Resolve" as the reference.

- **Space:** a tap (< 280 ms) opens the large view; tap again closes. **Hold = preview:** from the sheet it opens, plays while held and closes on release; in the large view it plays while held and stays. A real play loop (rAF, ~30 fps, the take's own length, loops) replaces the old +0.08 bump. Enter still opens, Esc still closes. Ignored while Export / Saving-to is open.
- **Pinch in the large view:** ⌃/⌘-wheel on the frame zooms 1×–8× about the pointer (the point under it holds: 0.300 → 0.2996 at 605 %); two-finger scroll or a drag pans; double-click goes back to fit; a pinch out at 1× closes the view (old grammar). The transform is clipped to the frame's own box (`clip-path`), so the scrub line and rail never move; the time line shows `· 605%`. Zoom resets on a new clip. No hover-skim while zoomed. Pen, heal and the loupe stay under the cursor (loupe scaled back to 132 screen px, 3× of what is on screen, kept inside the visible part).
- **Color = Lightroom mobile's groups**, B&W ink, `Light · Color · Mix · Grade` under the target chip:
  - **Light** (exposure correction): Exposure ±4 · Contrast · Highlights · Shadows · Whites · Blacks; **Auto** = a deterministic stand-in per clip (toast says no pixels are read).
  - **Color:** Temp (`wb`) · Tint · Vibrance · Saturation.
  - **Mix** (sky blues): Red … Magenta chips (a dot on edited ones), Hue / Saturation / Luminance for the chosen hue. Opens on **Blue** when the target is a Sky or Water layer.
  - **Grade** (Lightroom's colour grading, Resolve's wheels): Shadows · Midtones · Highlights · Global (` ·` on edited zones), one ink wheel (R Y G C B M; angle = hue, distance = strength, readout `H 231° · S 70`), Luminance, Blending (default 50), Balance.
  - Rows: drag the whole row (ev 1 stop / 120 px, others the range / 400 px), **⌥-drag = ¼ for fine control** (wheel too), double-click resets, sideways wheel nudges, ← → step. One delegated handler; rows update in place.
  - The look is a nested object read by path (`ev`, `mix.blue.s`, `grade.mid.h`), missing = default; copy / paste deep-clone it; the toast and Export's "graded" count read any non-default value.
- **Half height:** the active pane is at least 50vh and Light's rows spread to fill it; rail children no longer shrink, so a tall group (Grade) scrolls the rail instead of running under Keep.
- Gone: `G_IDS`, `G_MAX`, `syncGradeUI`, `setG`, the four static rows.

## Pending (owner — next paste)

Nothing open from the last brief. Candidates: a real frame under the loupe once there is one; heal spot pick + per-spot size after placing (today: size only while placing); paste a look onto a range of clips from the large view's strip.
