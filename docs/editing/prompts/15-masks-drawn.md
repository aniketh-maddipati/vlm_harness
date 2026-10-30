# 15 · Drawn masks: brush, linear, radial

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-masks-drawn` from origin/main.

**Goal.** The three hand-drawn mask kinds, with the pen-first feel.

**Build.**
- **Keys:**
  - brush strokes as compact vector paths (points + radius + feather + pressure) inside the look string or a side store referenced by it. **Decide with the owner which, since the look string's size matters.**
  - linear: two points + feather.
  - radial: centre, radii, angle, feather, inside/outside.
- **Raster:** `LookMasks.raster` already turns outlines into antialiased coverage planes; extend it to strokes and gradients. Masks follow crop / turn / straighten / perspective (`PhotoMasks`).
- **Combination:** the existing add / subtract / intersect; each mask has opacity.
- **UI (hands-on, Sort editor grammar):**
  - Pen: any stroke paints; Force Touch pressure = flow. ⌥ erases.
  - Drag in from an edge = linear gradient; two-finger rotate turns it.
  - ⇧-drag on the photo = radial from the centre.
  - The loupe sits at the pen tip.
  - Each new mask lands in the Masks panel (prompt 14) with its local sliders.
- **Data:** Lightroom linear/radial masks via XMP, if they import (save one from the UI first and copy its structure). Otherwise compare geometry analytically.

**Done when.** Strokes render identically on canvas, tiles and export; latency held while painting; undo per stroke; the look string stays small (budget agreed with the owner).

**Depends on:** 14.
