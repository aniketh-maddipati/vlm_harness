# 19 · Presets, LUTs, Lightroom import

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-presets-luts` from origin/main.

**Goal.** Named presets with strength, `.cube` LUTs, and Lightroom presets and XMP read in.

**Build.**
- **Presets:** a named look-string fragment (only the keys it sets), stored per user (container, not per shoot). Strength 0–150 %, scaled per key from rest.
- **LUT:** `.cube` (and HALD) through `CIColorCube`, with `lut:<name>/<strength>` and the file copied into the container. Opening a user file goes through the existing picker; the sandbox read needs a `TRUST.md` row. Choose display-referred vs scene-referred placement.
- **Lightroom import:** extend `Tools/parity/import_lr_edits.py`'s key mapping into Swift. A Lightroom preset `.xmp` or a photo's sidecar → look keys, covering the Basic, Curve, HSL, Color Grading, Detail and Effects keys Lumina has; report the keys it can't map.
- **UI:**
  - A presets strip in Edit. Hover = live preview on the canvas; click applies; drag the chip sideways = strength.
  - "Save look as preset" from the current photo, choosing which sections.

**Done when.** The owner's Lightroom presets import with the unmapped keys listed; preset strength is linear from rest; LUT renders identically on all tiers.

**Depends on:** none (more keys map as features land).
