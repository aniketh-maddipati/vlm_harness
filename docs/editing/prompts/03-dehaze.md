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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Presence: texture, clarity, dehaze (02, 03)*

- **Do:** press on detail and a 1:1 loupe (160 px) opens at the finger, because texture is only seen
  at 100 %. Drag ↕ = amount.
  - The puck shows which control: **T**, **C** or **D**. `[ ]` cycles them (it already picks the setting to nudge; Tab stays for keyboard focus).
  - Pressing on sky or distance picks Dehaze by itself.
- **Hands:** pinch while pressed = Clarity ↔ Texture balance (fine to coarse). The full canvas shows
  the whole-photo result behind the loupe.
- **Repeat:** these don't adapt to the photo, so the values carry as they are. Halos are guarded: if
  the halo score rises, the loupe outlines the halo in a thin warm line.
- **Video:** preview only in Final Cut; the puck says so.

**Skim (video) mirror.** Preview in Skim's viewer: dark channel on a downsized frame, with the airlight held per shot. Spatial, so preview only for Final Cut. Useful for drone and landscape b-roll.
