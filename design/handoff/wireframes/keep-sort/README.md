# Keep / Import / Sort wireframes

Interactive product wireframes for Lumina’s Import → Sort → Export spine (multi-vol dump → chron Keep → package).

## Run locally

```bash
python3 design/handoff/wireframes/keep-sort/hotserve.py
# → http://127.0.0.1:8787/  (redirects to import-wf.html)
```

| Page | Role |
|---|---|
| `import-wf.html` | Import: sensed cards (click to enable) → **Input dock** + hero **Drop**; AirDrop/Android land in the dock; Files not Phone; progressive Ready; Rec.709 for Log |
| `keep-wf.html` | Sort: one chron axis for every docked input; Kept dock always present; Ready N/M; pinch time; drag/select grammar (no Match, no vague Memory footer) |
| `index.html` / `sources-wf.html` | Redirects to Import |
| `archive/` | Earlier input/sources explorations (superseded) |

## Import grammar (locked)

- **Sensed cards on the top rail** (SD, T7, phone inbox, …) — click to enable into the Input dock; double-click an on card to turn off. Drag onto Drop = enable.
- **Hero Drop** — OS files, AirDrop, Android send. Inbound bursts become / grow the Inbox tile in the dock.
- **Input dock** (always present) — one tile per enabled volume with Ready n/m; **Sort now** hands off the set of docked vols.
- **No Cards & volumes / `sd*` chip strip under Drop.** Chip strip stays gone.
- Files pane stays Files (not Phone).

## Sort grammar (chron first, pretty later)

- One chronological contact sheet for **all** docked inputs (union of sources).
- Tiles can start unread; preprocess develops near the playhead; **Ready N/M** climbs and is **not** a gate.
- New AirDrop / Android files **append by clock** while Sort is open.
- Keep / unkeep / reorder Kept dock; Export package; double-click large view.
- Rec.709 default on for Log — no “matches FCP” / ΔE in shipping UI (see `MODEL-EVAL.md`).

## Sort checklist (wired in `keep-wf.html`)

- Sensed volume → click / Drop → Input dock → Sort now (`sessionStorage` multi-vol handoff)
- Marquee on empty canvas; Shift-range and ⌘-toggle; ⌘A
- Time-rod scrub; pinch / ⌃-wheel time interval
- K keep / unkeep (selection or cursor); drag tiles onto Kept; drag Kept onto the axis to unkeep; drag Kept to reorder
- Auto clock-align on load (pill: "clocks aligned · N inputs"); per-source −/+ steppers as override
- Chapters auto-segment by time gap; click a chapter title to rename
- Export… → stringout package + chapter list (no FCP / ΔE claim)
- Double-click a tile (or a Kept tile) for large view; double-click the viewer or Escape to close

## One product, model-organised (consolidated)

There is **no scene toggle and no per-user mode**. Harrison (A/B-cam + drone, clocks off) and Uday (cam + drone, group by place) are the same dump with the same needs, so Sort does the work for both with models instead of modes. One chronological axis for every docked input, then:

- **Auto clock-align** — a beat after the axis paints, a sync pass (the app's audio / feature match) estimates each drifting source's offset and snaps it onto the axis. The pill in the top bar reads "clocks aligned · N inputs". A second body that stamped +6 min fast lands beside the clips it was shot with. Per-source **− / + steppers** on each source chip remain as the manual override; the offset shows on the chip.
- **Chapters segment themselves** — the axis bins into a chapter wherever the clock gap between consecutive clips exceeds a threshold (12 min). Headers read "Chapter N"; click a title to rename it. This covers Uday's overlooks and any day's natural breaks.
- **Stringout package** — Export frames the keeps as "N keeps · GB · stringout in time order", sub "Keeps in time order · one timeline · opens in your NLE", and lists the chapters with kept counts.

The wireframe stands the models in with `HIDDEN_SKEW` (the skew the sync model is told to find) and the gap threshold in `state.gapMin`; no real sync / segmentation model runs here.

See `MODEL-EVAL.md` for Rec.709 / model claim boundaries (measured vs wireframe-only).

## Handoff (Harrison + Uday wireframes)

New chat: paste [`CONTINUATION-PROMPT.md`](CONTINUATION-PROMPT.md) · context [`CONTINUATION.md`](CONTINUATION.md) · plan [`PLAN-input-dock-chron.md`](PLAN-input-dock-chron.md).  
Archive scenes: `archive/lumina-minimal-mvp.html` (`harrison`, `uday`).
