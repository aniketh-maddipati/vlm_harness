# Skim canvas: instant grids (branch video/skim-canvas)

Goal: the scenes/clips grid as one canvas drawn from decoded thumbnails, so moving the grouping from 1 to 500
holds 60 fps with no grey tiles; zoom is grouping (contact sheet → moments → takes → one clip); a bottom dock of
selected clips by scene, elastic. Plan (task list from the chat):
1.1 Thumbnail cache, decode once — DONE (Component.ThumbCache, makeBmp, covers pinned, 128 MB LRU, luminaSkimDebug()).
1.2 Layout as maths (zoom, window, clips, groups → rects), Node-testable, < 2 ms for 500.
1.3 Canvas drawing (DPR-aware, visible only, placeholders, no flashes), < 4 ms full redraw for 500 in Safari.
1.4 Zoom = grouping, animated ~150 ms; pinch, slider and −/= drive it.
1.5 Hit-testing: hover, click, double-click, box, hold-and-tap, keys. Viewer stays.
1.6 Swap in for Scenes and Clips; timing on 162 fixture and the 400-clip card.
2.1–2.2 Dock: selected clips by scene, elastic, click to jump, drag out to remove, totals.
Grouping logic (takes, shot type, accidental, usable stretch) is video/skim-grouping; Rec.709 is video/skim-rec709.
