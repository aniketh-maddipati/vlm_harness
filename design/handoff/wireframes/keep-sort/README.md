# Keep / Import / Sort wireframes

Interactive product wireframes for Lumina’s Import → Sort → Export spine (Harrison dump→sort keepers).

## Run locally

```bash
python3 design/handoff/wireframes/keep-sort/hotserve.py
# → http://127.0.0.1:8787/  (redirects to import-wf.html)
```

| Page | Role |
|---|---|
| `import-wf.html` | Import: sensed volumes (top funnel) + hero **Drop**; Files not Phone; progressive Ready; Rec.709 for Log |
| `keep-wf.html` | Sort: Kept dock always present; pinch time; drag/select grammar; Ready N/M (no Match, no vague Memory footer) |
| `index.html` / `sources-wf.html` | Redirects to Import |
| `archive/` | Earlier input/sources explorations (superseded) |

**Latest Import layout (2026-10-27):** Cards & volumes / `sd*` chip strip under Drop is **removed**. Import = sensed designation cards up top (SD, T7, phone inbox, …) as a funnel onto hero Drop. Chip strip stays gone.

See `MODEL-EVAL.md` for Rec.709 / model claim boundaries (measured vs wireframe-only).

## Sort checklist (wired in `keep-wf.html`)

- Sensed volume → Drop → confirm → Sort (`sessionStorage` handoff; axis filtered by card / drone / phone)
- Marquee on empty canvas; Shift-range and ⌘-toggle; ⌘A
- Time-rod scrub; pinch / ⌃-wheel time interval
- K keep / unkeep (selection or cursor); drag tiles onto Kept; drag Kept onto the axis to unkeep; drag Kept to reorder
- Export… → Make package (no FCP / ΔE claim)
- Double-click a tile (or a Kept tile) for large view; double-click the viewer or Escape to close
