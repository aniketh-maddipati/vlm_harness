# Keep / Import / Sort wireframes

Interactive product wireframes for Lumina’s Import → Sort → Export spine (Harrison dump→sort keepers).

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
- Export… → Make package (no FCP / ΔE claim)
- Double-click a tile (or a Kept tile) for large view; double-click the viewer or Escape to close

See `MODEL-EVAL.md` for Rec.709 / model claim boundaries (measured vs wireframe-only).
