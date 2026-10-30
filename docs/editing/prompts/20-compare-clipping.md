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
