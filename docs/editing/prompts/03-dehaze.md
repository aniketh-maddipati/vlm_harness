# 03 · Dehaze: merge, slider, check

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-dehaze` from origin/main.

**Goal.** Dehaze on main with a slider, held to criteria.

**Now.** The branch `claude/dehaze-stage` (`7a4e1e6c`, `f804e8e0`) has `dhz`, fitted on the owner's Death Valley edits (by their call): DV 5.52/14.38 → 4.91/12.08, held-out 2.44/7.72 → 2.41/7.71. Its coefficient sits at its bound.

**Build.**
- Bring the branch up to origin/main: rebase or re-apply, as the stage's three copies require.
- Check it against the Dehaze rows of sweep 4 (from prompt 02, or add them yourself). The DV-fitted coefficient must generalise to one-slider sweeps.
- Look at the bound: is the form limiting? One form change at most.
- **UI:** a Dehaze row in Presence.
- **On-photo gesture:** drag ↕ on the sky or a hazy distance (sky mask from `SetsMasks` if present) moves Dehaze while Presence is open.

**Done when.** Sweep criteria met or best reported; held-out within tolerance; better scores: hue drift on sky ≤ Lightroom's, no halo at the horizon.

**Depends on:** 00; shares sweep 4 with 02.
