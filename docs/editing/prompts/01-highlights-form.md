# 01 · Highlights: a new form

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-highlights-form` from origin/main.

**Goal.** Highlights within criteria. Today p95 is 7.0, and 9.9 at −100. Commit 459914e4 says the form, not the coefficients, is the limit.

**Now.** `LookMath.toneGain` / `ToneAnchor` (`LookMath.swift` ~:172–236): a local exposure through the tone curve, with the mask placed against the photo's mean.

**Build.**
- Study where it fails on the Death Valley tone set (156 photos × Highlights −100/−50/+50) with per-photo heatmaps (`~/LuminaEvidence/parity/report/`). Classify the failures: bright-sky roll-off, local-contrast loss, colour (saturation) in recovered highlights.
- Try at most 3 candidate forms, one at a time, each across all three copies:
  - mask against `high` (p95), as Shadows does
  - a two-scale base (a blurred base for the mask, the pixel for the gain)
  - highlight saturation kept in Oklab
- Keep the anchor plumbing identical across the tiers: base, region tiles, export.
- **UI:** the slider exists. Add the on-photo gesture: with the Light section open, drag ↕ on a bright area of the photo moves Highlights; on a dark area, Shadows (the tone under the pointer chooses). The same targeted gesture family as ⌥-drag on colour; document it in HELP.

**Done when.** Highlights median ≤ 2.0 and p95 ≤ 4.0 on the sweep (or the best of 3 forms reported, if none reaches it); held-out within tolerance; better scores: isolation (shadows don't move) and no added halo at sky edges.

**Depends on:** 00.
