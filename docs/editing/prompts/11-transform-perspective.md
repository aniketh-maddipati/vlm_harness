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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Crop and perspective (11)*

- **Do:** C. A grid lies over the print.
  - Drag a corner to keystone, like tilting a print toward the light.
  - Two-finger rotate straightens, with detents at 0° and at the horizon Lumina found.
- **Hands:**
  - **U** = upright: the grid glides to the fix in 160 ms, then it's yours to adjust.
  - Draw along two lines that should be parallel and they become parallel.
  - F / ⇧F flips.
- **Repeat:** tripod series copy the numbers; handheld series re-detect lines per photo. In Final Cut,
  native transform keys.
- **Polish:** the grid is thirds only, 1 px at 22 %; it fades while you rotate except near the horizon.

**Skim (video) mirror.** Straighten, flip, and keystone map to Final Cut's own transform and distort parameters in the `.fcpxml` (`adjust-transform`, distort corners), so they export natively rather than baked. Same grid-corner gesture on Skim's viewer. Check the `.fcpxml` imports into Final Cut 12.4 (the existing export-proof routine).
