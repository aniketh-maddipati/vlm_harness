# 17 · Full adjustment set inside masks

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-local-adjustments` from origin/main.

**Goal.** Everything you can do globally, you can do inside a mask: wb/tint, curve, HSL, sharpen, nr, texture, dehaze, grade.

**Now.** Locals: ev con hl sh wh bl vib sat clr (`mask:<id>/…`).

**Build.**
- Run the same stages through the mask after the global ones (the pipeline already does this for the current keys); extend the parser and the kernels.
- Watch the canvas cost: a mask with many locals is a new stage set, so warm it (`LookWarmPlan`).
- **UI:** the Masks panel's local sliders gain the same sections as global (Light / Colour / Effects / Grade), collapsed by default. Every on-photo gesture works inside the selected mask.

**Done when.** Each local key passes identity and ramp tests; mask locals ≡ global maths with a full mask (ΔE 0); latency held with 3 masks × 5 locals.

**Depends on:** 14, and each global feature it extends.

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Masks: subject, sky, person, objects (14, 17)*

- **Do:** click a subject and **it lifts**: a soft outline glow, everything else dims to 70 %. From now
  on *every* task's gesture applies inside it: grade the person, lighten the sky. Esc puts it down.
- **Hands:**
  - A slim left rail of layer thumbnails: click a layer out or in, ⇧-click solos it.
  - "Find everything" lists what Lumina found.
  - Hold **O** to see the mask.
- **Repeat:** masks are stored by kind ("the person", "the sky") and found again on each photo; on
  video, Follow tracks them.
- **Polish:** the lift is the only shadow in the UI.

**Skim (video) mirror.** Locals over Skim mattes: the same keys, applied in the viewer through the matte. To Final Cut: matte plus the correction as its own `.cube`, layered in the `.fcpxml`. Check it imports.
