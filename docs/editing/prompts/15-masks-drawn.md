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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Drawn masks: pen, gradient, radial (15)*

- **Do:**
  - Pen: any stroke paints; pressure = flow; ⌥ erases. Edges snap to the photo (refined).
  - Drag in from the frame's edge = a gradient; two-finger rotate turns it.
  - ⇧-drag = a radial from its centre.
- **Repeat:** drawn shapes carry by geometry (same framing) or, on video, by Follow. A small chip warns
  when a photo's framing differs.
- **Polish:** the loupe at the pen tip; strokes draw as a 1 px gold edge only while active.

**Skim (video) mirror.** Pen strokes, linear and radial on the viewer: static by default, "follow" to track them (the Follow path). Exported as mattes. The Sort editor's pen-first grammar applies to both.
