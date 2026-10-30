# 11 · Transform: perspective, upright, flip

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-transform-perspective` from origin/main.

**Goal.** Perspective correction you can do by hand or let Lumina propose.

**Now.** Crop, straighten (±45°, drawn line), 90° turns. No flip, no perspective.

**Build.**
- **Keys:** `persp:v,h` (vertical/horizontal keystone), `flip:h|v`, folded into the crop geometry (`geometryPlaced`), with masks transformed too.
- **Auto upright:** Vision `VNDetectHorizonRequest` plus line/rectangle detection gives a proposed homography. Ideas from RapidRAW's guided upright: user-drawn guides → vanishing points → homography; then the largest inscribed crop. Ideas only.
- **UI (hands-on):**
  - In Crop, a 3×3 grid. Drag its corners to keystone, like tilting a print.
  - **U** proposes upright: the grid jumps, and you adjust it.
  - Draw two guide lines (like S for straighten) and Lumina makes them parallel.
  - Two-finger rotate straightens.
  - in Crop, F flips horizontally, ⇧F vertically (H and V are taken).

**Done when.** On 20 architecture frames, verticals within 0.5° after Auto; manual grid at canvas latency; export geometry ≡ canvas.

**Depends on:** 10 (lens warp comes first in the geometry).
