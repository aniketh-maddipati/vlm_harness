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
