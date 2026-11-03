# Keep / Import / Sort wireframes

Interactive product wireframes for Lumina’s Import → Sort → Export spine (multi-vol dump → chron Keep → package).

## Run locally

```bash
python3 design/handoff/wireframes/keep-sort/hotserve.py
# → http://127.0.0.1:8787/  (redirects to import-wf.html)
```

| Page | Role |
|---|---|
| `import-wf.html` | Import: **suggested volumes** (path · size · open in Files) → **Drop** + **AirDrop** → **Input dock**; Files pinch→icons; Log prep across suggested in priority order; Prep is Log only |
| `keep-wf.html` | Sort: one chron axis for every docked input; Kept dock always present; pinch time; drag/select grammar (no Match, no Ready/preprocess — clips are just included) |
| `index.html` / `sources-wf.html` | Redirects to Import |
| `archive/` | Earlier input/sources explorations (superseded) |

## Import grammar (locked)

- **Top row = suggested volumes** (sensed/valid cards — SD, T7, DJI, …; not Phone). Cards show name · files · GB · path. Click opens Files at the volume top; double-click toggles enable; drag onto **Drop** or the **Input dock** = enable.
- **Hero Drop** — drop a volume/folder or file (or drag a suggested card / Files row). Drop and the Input dock share one acceptor (`acceptImportDrop`). Enabling a directory runs `pullVolume` / `scanPull`: **ACCEPT_EXT are pulled** (including peripheral media). Non-accept is left quietly — no `off` / skip file class. Among pulls, objective **peripheral sense** marks “also” (still imported): sidecar/proxy (`lrv`/`srt`/`xmp`), path outside DCIM/Clips/MEDIA when that tree exists, extension not in the volume’s dominant primary set, tiny helpers. Toast example: `T7 · pulled 3 · 1 also (jpg) · may be outside main shoot · 3 left (db, log, txt)`. Files show a muted **also** pill + tooltip why — never strike-through / reject styling.
- **AirDrop pane** under Drop (same dotted wireframe idiom) — arm / receive wireless; arrivals land in the dock as **Phone** (not Inbox). Files pane stays **Files** (not Phone).
- **Input dock** — drop target identical to Drop; one tile per enabled volume (file counts, no Ready n/m); **Sort now** hands off docked vols (no readyDone/readyTotal).
- **Files + directories drag** — every file row and every directory row is `draggable` onto Drop/dock (parent volume if known, else media/AirDrop path). Invalid OS drops still toast “Not a valid import” / “Can't import that”.
- **Boot Files** — tree at the top of the pane, **everything collapsed** (`open: false`); sensed volumes stay first in order. No auto-open of Downloads / home-downloads / phone on boot.
- **Prep is Log only** — footer Prep card is the Log step; RAW / masks / near / dust / grade stay out of Import. No RAM / offload UI.
- **No Cards & volumes / `sd*` chip strip under Drop.** Chip strip stays gone.

## Sort grammar (chron first, pretty later)

- One chronological contact sheet for **all** docked inputs (union of sources), as time-stamped runs anchored to the clock, with a **bare hairline** wherever the clock gap passes 20 min — separated by time, no stack labels.
- **B&W wireframe palette only** — `--ink` / `--mute` / `--line` / `--fill` / `--bg`, plus the two functional accents: kept green and danger red. No amber, no gradients: picks are dashed ink, focus/flash states are ink, the Clean warn is danger red.
- **Fill-frame cards.** The frame is the card; name + duration / gamma / soft ride its bottom edge as paper chips; hovering a tile preview-plays it (play mark + running hairline). Every card states gamma — **Log** or **709**; soft marks the cull pass. Soft-shadow edges; state marks stay crisp.
- **Minimal motion** — 140 ms fades; pinch is continuous (live compositor scale toward the next level, lands on TI levels, anchored under the pointer); no layout-animating transitions, no hover lift, no stagger.
- **No Ready N/M, no preprocess** — every clip is just included on the axis, readable from the first paint. (Owner, 2026-10-28.)
- **Add more at will** — **+ Add clips** (or `A`) returns to Import with already-included vols held in the dock; enable more, then **Back to Sort**. Keeps / place / clock shift survive the round trip.
- Keep / unkeep / reorder Kept dock; Export package; double-click **full-screen large view** (axis collapses to a loupe strip).
- Rec.709 default on for Log — no “matches FCP” / ΔE in shipping UI (see `MODEL-EVAL.md`).
- **Cull grade minimum (large view only):** Exposure · Contrast · Warmth · Color, on the whole clip or one outlined layer. Rec.709 is the Log display transform (top bar), not a slider. Full grade stays in the NLE.

## Sort checklist (wired in `keep-wf.html`)

- Sensed volume → click / Drop → Input dock → Sort now (`sessionStorage` multi-vol handoff)
- Marquee on empty canvas; Shift-range and ⌘-toggle; ⌘A. Marquee paints picks in place (no canvas rebuild under the pointer) and pinch never fires under a marquee or rod scrub
- Time-rod scrub; pinch / ⌃-wheel time interval (1 s … 2 days). Pinch is magnitude-based and continuous (live scale, level lands with no residue, tile under the pointer re-anchored); pinching out past the coarsest level closes the large view
- K keep / unkeep (selection or cursor); drag tiles onto Kept; drag Kept onto the axis to unkeep; drag Kept to reorder
- Pick layers: click / ⌘-click toggles selection; no per-tile outline editor
- Auto clock-align on load, told in three beats: **see the skew** → **watch the fix** → **read the receipt**; pill fades 5 s after
- Hairline time-gap breaks on the axis (no labels)
- **Saving to** opens a folder sheet (fake FS tree · Open in Finder · New folder · Move to); moves land on the Clean **destination ledger**
- Export… → stringout package (no FCP / ΔE claim)
- ⏎ (or double-click a Kept tile) → full-screen large view: the frame fills the width, scrub + neighbours under it, one **340 px** rail — Color / Outline / Heal (1 / 2 / 3), Keep. Color = Stills rows (drag the row, dblclick resets). Outline = the pen: Find everything → layers; draw a closed shape → a layer; draw over a picked layer's edge → that run redrawn; tap empty = fill; ⇧-draw grows, ⌥-draw carves; each layer clicks out / in (⇧-click solos). Close: Esc, ×, double-click stage, or pinch out past top TI
- Clock-align proof: **vertical stems on the time rod only** (hollow = as stamped, arrowhead = aligned; label `drone · 3m` up the rail). Edge cases on the dump: long back (ssd 6m), medium forward (drone 3m), short nudge (phone 50s). Axis strip only — never over tiles, no scroll repaint

## One product, model-organised (consolidated)

There is **no scene toggle and no per-user mode**. Harrison (A/B-cam + drone, clocks off) and Uday (cam + drone, group by place) are the same dump with the same needs, so Sort does the work for both with models instead of modes. One chronological axis for every docked input, then:

- **Auto clock-align, in three beats** — you never need to know your clocks were off. A sync pass (the app's audio / feature match) estimates each drifting source's offset: (1) a beat after the axis paints the pill names the skew ("clock drift · ssd ~6 min fast", title says what it did to your view: those clips sit six minutes later than they were shot); (2) the shift applies and the moved clips flash a dashed outline while the axis re-sorts; (3) the receipt ("ssd back 6 min · clocks aligned · N inputs", title: "The dashed-outline clips moved on the axis"). A body that stamped +6 min fast lands beside the clips it was shot with. There are no source chips in the header and no −/+ steppers; the pill is the whole clock story, and it fades away 5 s after the receipt (a tile's source still shows in its thumbnail stand-in and the viewer's info pills).
- **Time-gap breaks** — where the clock jumps past 20 min the axis draws a bare hairline. Cam and drone clips from the same stop sit in one span; a move to the next overlook breaks the line. No labels: the separation is by time alone.
- **Stringout package** — Export frames the keeps as "N keeps · GB · stringout in time order", sub "Keeps in time order · one timeline · opens in your NLE".

The wireframe stands the sync model in with `HIDDEN_SKEW` (the skew the sync model is told to find); no real sync model runs here.

See `MODEL-EVAL.md` for Rec.709 / model claim boundaries (measured vs wireframe-only).

## Handoff (Harrison + Uday wireframes)

New chat: paste [`CONTINUATION-PROMPT.md`](CONTINUATION-PROMPT.md) · context [`CONTINUATION.md`](CONTINUATION.md) · plan [`PLAN-input-dock-chron.md`](PLAN-input-dock-chron.md).  
Archive scenes: `archive/lumina-minimal-mvp.html` (`harrison`, `uday`).
