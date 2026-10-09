# Skim canvas: instant grids (branch video/skim-canvas)

Goal: the scenes/clips grid as one canvas drawn from decoded thumbnails, so moving the grouping from 1 to 500
holds 60 fps with no grey tiles; zoom is grouping (contact sheet → moments → takes → one clip); a bottom dock of
selected clips by scene, elastic. Plan (task list from the chat):
1.1 Thumbnail cache, decode once — DONE (Component.ThumbCache, makeBmp, covers pinned, 128 MB LRU, luminaSkimDebug()).
1.2 Layout as maths (zoom, window, clips, groups → rects), Node-testable, < 2 ms for 500 — DONE (see Status).
1.3 Canvas drawing (DPR-aware, visible only, placeholders, no flashes), < 4 ms full redraw for 500 in Safari.
1.4 Zoom = grouping, animated ~150 ms; pinch, slider and −/= drive it.
1.5 Hit-testing: hover, click, double-click, box, hold-and-tap, keys. Viewer stays.
1.6 Swap in for Scenes and Clips; timing on 162 fixture and the 400-clip card.
2.1–2.2 Dock: selected clips by scene, elastic, click to jump, drag out to remove, totals.
Grouping logic (takes, shot type, accidental, usable stretch) is video/skim-grouping; Rec.709 is video/skim-rec709.

## Status (2026-10-08, after 1.2)
Done:
- 1.1 ThumbCache (LOCAL-CHANGES 45). The bitmaps are made and pinned but nothing draws from them yet: tiles are
  still CSS backgrounds on blob: URLs.
- Tiles are never empty (LOCAL-CHANGES 50), still in the DOM grid. `tone()` gives a still neutral tone (`Component.PH`)
  when a clip has no frame, and the tile writes the clip's name and time · length over it (`waiting`, `phSub`,
  `data-lumina="tile-wait"`). `pic(slot, clip, i)` lays a new picture over the one the slot showed before and
  `picWait` lets go of the old one once the new one is decoded. A slot is a scene tile (`this.gSlot[g.i]`) or a
  clip's frame (`c._sl[i]`). No fade, no breathing.
- 1.2 layout maths (LOCAL-CHANGES 51): static, no DOM, in the page. `layGeo` / `laySceneGeo` (columns, tile and
  picture sizes, gaps), `layClips` (sections, rows laid out, spacers, tile rects), `layScenes` (tile rects),
  `layout({lv, z, win:{vw, cw, top, h}, groups:[{i, n}], cur:{gi, k}})` as the one way in, `layHit(rects, x, y)`.
  `tileGeo`, `sceneGrid` and the Clips windowing in `renderVals` call them, so the DOM grid and the maths cannot
  drift. `node --test Tests/web/skim-layout.test.mjs` (8 tests): equal to the pre-1.2 code over random windows,
  zooms and groupings; 500 clips in 0.002–0.008 ms median, Node on this Mac (not a browser number).
Checked in headless Chromium with the 600 and 1,500 test loads (not Safari, not the app, not a real card): while
the read ran and the scene slider was moved, no scene tile was without a picture or a placeholder.

What 1.3 needs:
- A canvas per grid inside the scroller (sticky, the scroller's size × devicePixelRatio), with a spacer of
  `layout().height`; redraw on scroll, resize, bump and slider input, one requestAnimationFrame at a time.
- Draw from `this.thumbs.get(id, i, 'g')` at the rects from `layout()`. Scenes need the cover only (pinned, so always
  there once read). Clips need 8 frames a tile: `ensure` those in the window, draw the cover stretched or the
  placeholder until they land, never clear a tile before its new bitmap is ready.
- Scenes rows are a fixed height in the maths (cover + 74 px); the DOM rows grow when a scene has more than one
  line of dots. On canvas, draw the dots in one line or as the bar. `head` is the slider's height above the grid.
- The Rec.709 preview is a CSS filter on each tile today (`pvFlt`, an SVG filter for S-Log3). On canvas: either
  `ctx.filter` per tile (check Safari supports the url() filter and what it costs) or bake it into the bitmap in
  `makeBmp` and key the cache by preview on/off. Decide by measuring; this is the main unknown.
- Text (names, times, flags, marks, the selection and current outlines) either drawn on the canvas or left as a
  thin DOM layer over it placed from the same rects. Hit-testing (1.5) starts from `layHit`.
- The < 4 ms redraw budget has to be measured in Safari with the page's clock; nothing is measured yet.
- `data-clip`, `data-gi`, `data-sec` are used by scrolling, drag-select and the tests; keep them on whatever
  stays in the DOM, or move those to the rects.
