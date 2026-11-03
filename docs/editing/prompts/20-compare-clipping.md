# 20 · Before/after split, clipping overlay

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-compare-clipping` from origin/main.

**Goal.** Comparing and checking without leaving the photo.

**Now.** Hold `\` or force-click = before; the histogram's clip hovers. No split view, no on-image clipping.

**Build.**
- **Split view:** **B** toggles it (Y is Redo). Drag the divider like sliding a print over its negative; the native canvas draws both halves (before = neutral look on the same base), so no page image is involved.
- **Clipping overlay:** **J**-hold is taken by heal (18), so use **K**-hold. Highlights red, shadows blue, computed on rest renders per channel. Clipping hovers in the histogram light it too.
- **Before = which before?** ⇧\ compares with the previous state (undo step) instead of neutral.
- Keys and gestures in HELP.

**Done when.** Both run at canvas latency; the overlay matches the histogram's counts; pixel tests on a ramp.

**Depends on:** none.

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Compare (20)*

- **Do:** **B** splits the photo: before on the left, now on the right. Drag the divider like sliding a
  print over its proof.
- **See:** hold **K** for clipping: red highlights, blue shadows; zebras on video. Hold `\` for before.
  ⇧`\` compares with your last step.
- **Polish:** the divider is a 1 px line with a 12 px grip that appears on hover.

**Skim (video) mirror.** Video conventions: zebras (adjustable IRE) instead of red/blue clipping, a waveform and a vectorscope in Skim's viewer, and split view on the viewer. The same keys where free (K for zebras, B for split).
