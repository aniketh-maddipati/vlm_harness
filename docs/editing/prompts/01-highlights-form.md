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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Light: exposure, highlights, shadows, whites, blacks (prompts 01, 02 for vibrance)*

- **Do:** press anywhere and drag ↕. The tone under the finger chooses the slider: blacks, shadows,
  highlights or whites. ⌘-drag ↕ is exposure for the whole photo.
- **Hands:** while pressed, a thin tone bar (black → white, 4 px) beside the puck marks where your tone
  sits. The pixels in that band glow faintly on the photo (a 20 % luminance key) so you see what moves.
- **Repeat:** stored as "this photo's band"; re-solved per photo with the tone anchor, so "lift the
  shadows" lifts *each* photo's shadows by the same look.
- **Polish:** the histogram lights the band you hold; nothing else changes on screen.

**Skim (video) mirror.** Port the chosen Highlights/Shadows form into Skim's `tone()`, replacing its polynomial approximations. The photo anchor becomes a shot anchor (measured on 8 frames, held for the clip, so it doesn't flicker). LUT-able once per shot, so add it to the shot's `.cube`. The viewer's drag-↕-on-a-bright-area gesture applies too.
