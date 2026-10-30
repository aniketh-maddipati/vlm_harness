# 16 · Range masks: colour, luminance, depth

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-masks-range-depth` from origin/main.

**Goal.** Select by colour, by brightness or by distance, and refine any mask with them.

**Build.**
- **Colour range:** a target (Oklab), a tolerance and a smoothness, picked from the pixel under the pointer.
- **Luminance range:** an L range with soft edges; the picker sets it from the tone under the pointer.
- **Depth:** needs a model. Candidate: Depth Anything V2 **Small** (check its licence is Apache-2.0; the larger models are non-commercial), as Core ML at 518 px, cached per photo like `SetsMasks`. A model file is reach, so it needs a `TRUST.md` row and an owner ruling. **Stop and ask before adding it.**
- All three can intersect any other mask (refine "sky" to "only the bright sky").
- **UI (hands-on):**
  - ⌘-click on the photo creates a colour range from that pixel; drag ↔ widens the tolerance.
  - ⌘⌥-click does the same for luminance.
  - Depth: drag on the photo near → far sets the depth band, with a live overlay.

**Done when.** The ranges are deterministic and identical across tiers; depth (if approved) runs ≤ 300 ms per photo at `.utility` and is cached.

**Depends on:** 14.
