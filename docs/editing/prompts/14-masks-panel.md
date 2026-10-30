# 14 · Masks panel on the existing AI masks

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-masks-panel` from origin/main.

**Goal.** The masks Lumina already finds (Vision person, subject, object, sky, background; guided-filter edges; add / subtract / intersect; `mask:` locals) become visible and editable. This is the biggest UI gap.

**Now.** `lumina.masks` / `showMask` exist in `plumbing.js` (~:259, :1240); `SetsMasks.swift`, `LookMasks.swift`, pipeline blend (~:396–405). v23 has no Masks panel. See `docs/masking/BACKLOG.md` (item 12) and DESIGN-ASKS 28/29 (history only).

**Build (UI-led):**
- A Masks section: the list of masks found for this photo (thumbnails), each with in/out, invert and opacity; local sliders under it (the existing local keys: ev con hl sh wh bl vib sat clr).
- Follow the Sort editor grammar (memory ruling 2026-10-28): layers you click out and back in; ⇧-click solos; no mask-kind buttons wall.
- **Hands-on:**
  - Click a subject on the photo to select its instance mask (Vision instance masks); the outline shows.
  - Drag ↕ on it = local exposure, ↔ = local warmth (needs local `wb`, which comes in prompt 17; until then ↔ = saturation).
  - **O** toggles the overlay.
- Masks are re-found per photo, never copied as pixels. "Same as last" carries the mask *kind* plus locals. This is a hook for prompt 22.

**Done when.** Every found mask is listable, toggleable and adjustable; canvas ≡ export (`probe.sh edit` mask scenario); the Adaptive Sky/Subject Lightroom sweep (sweep 13, the owner's) is measured for shape (IoU against Lightroom's mask, via its local's footprint) and blend.

**Depends on:** none (uses existing native masks).
