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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Looks: presets, LUTs, learned looks (19, 23)*

- **Do:** hold **L** and 3–5 looks **fan out around the pointer** as live tiles of *this* photo.
  - Move toward one and it grows and previews on the canvas; the distance from the centre = strength.
  - Release applies; release in the centre cancels.
- **Hands:** drop a `.cube` file or a reference photo onto the fan to add it. Learned outcomes (23) and
  presets (19) share the fan.
- **Repeat:** a look applied to a selection is solved per photo.
- **Polish:** tiles are 72 px with 4 px corners; no labels until hover; 120 ms bloom.

**Skim (video) mirror.** LUTs are video's native language. Skim reads `.cube` (camera and creative LUTs), applies it in `LK_FS` (3D texture), and writes each clip's look out as `.cube` for Final Cut. Presets are shared between stills and Skim where the keys overlap; keys Skim doesn't have are listed when applying.
