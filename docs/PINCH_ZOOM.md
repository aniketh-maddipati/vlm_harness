# Trackpad gestures

Travel only. Nothing here writes a cull, a recipe, or a selection.

## Rank

| Rank | Gesture | Where | What it does |
|---|---|---|---|
| 1 | Pinch | Open photograph | Zoom, anchored at the fingers. Fit is the floor, sensor 1:1 is the ceiling, with a short rubber-band. |
| 1 | Pinch | Table | Column density, already installed. Unchanged. |
| 2 | Two-finger glide | Open photograph | Pans while zoomed. At fit, a horizontal glide pages to the next or previous frame. One glide, one frame. |
| 2 | Two-finger glide | Table | Scrolls the sheet, already installed. |
| 3 | Double-click | Table | Opens the photograph. Already installed. |
| 3 | Double-click | Open photograph | Returns to the table. Already installed. Not a zoom. |
| 4 | Two-finger double-tap | Open photograph | Toggles fit and 2×, anchored at the tap. |
| — | Press and hold | Open photograph | Before, already installed. Release returns. |
| — | Force-press | — | Not installed. The contract allows it only as a spare loupe, and hold-Space is Before. |
| — | Rotate, three-finger swipe, two-finger tap | — | Not installed. Rotate is the straighten slider. A swipe must not keep or reject. |

## Installed on the open photograph

`FocusZoom` holds zoom and pan. `FocusZoomMonitor` watches pinch, glide, and two-finger double-tap over the picture and does not take clicks, so double-click and hold-before still fire. The Metal leaf is the same view; it only receives the new zoom and pan. A sharper frame rebases zoom so the point under the cursor stays.

Still out: drawing the neighboring frame during the page, and asking for a 1:1 region when the resident bitmap runs out of pixels.
