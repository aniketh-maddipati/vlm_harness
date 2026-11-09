# 24 · Slider precision: continuous values, rich range, down to the infinitesimal

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps,
checks, stop rules and finish). Branch `claude/edit-slider-precision` from origin/main.

**Goal.** Any slider can move by an arbitrarily small amount and land anywhere in its range. The fine
end feels smooth, never steppy, from the slider, the photo, the keyboard and the trackpad alike. The
whole chain (page → look string → Metal → export) keeps that precision, so a tiny move is a real,
rendered change.

**Now (measured 2026-11-03 on main).**
- The page snaps every value to its step: `clampV` rounds to `st` from `static SL`, which is Exposure
  0.05 EV, Temperature 10 K, and 1 unit for everything else.
- ⇧ (×0.25) and ⌥ (×0.1) slow the drag but still land on the step, so you can't go finer than it.
- The canvas renders in `rgba16Float`, so the GPU end has room.
- `LookString.format` writes fixed decimals per key. Read it to see which keys would truncate a finer
  value.

**Build.**
- **Store continuous values.**
  - Drags, gestures and typed values keep full precision in the look state.
  - The step becomes a *display* rounding and a keyboard nudge size, not a clamp.
  - Look string decimals per key: enough to hold ⌥-fine moves, for example ev 3 decimals (0.001 EV),
    wb whole K, tint and the ±100 sliders 1 decimal, curve points 4 decimals as now.
  - `LookStringTests`: a page string with the new precision parses and round-trips. Old strings still
    parse.
- **Precision ladder, consistent everywhere** (slider, on-photo drag, the hand kit's puck, the trackpad):
  - plain: 1 unit per ~2 px;
  - ⇧: ×0.25;
  - ⌥: ×0.1;
  - ⇧⌥: ×0.02 (new).
  - Velocity-aware: a very slow drag (< 20 px/s) lowers the gain smoothly by up to another 4×. Big
    sweeps stay fast, and creeping lands on fine values without a modifier. The ladder holds detents
    (prompt 00c) unchanged.
- **The readout follows the precision.**
  - The puck and the row show the extra decimal while a fine drag is active (`Exposure +0.347`), and the
    normal rounding at rest.
  - Typing a value accepts decimals.
  - `, .` nudge by the step; ⌥`, .` by a tenth of it.
- **Rich range.** Whether a slider needs more than ±100 (Lightroom's limits) is the owner's call;
  don't widen ranges without asking. Only the *resolution* inside the range changes.
- **Rendering keeps it.** Check that a 0.001 EV and a 0.1-unit move change the canvas and the export
  (render two looks that differ by one fine step and assert a non-zero, monotonic difference on a ramp).
  Make sure no stage quantises a coefficient on the way: kernel uniforms, `rules-v1.json`, the
  `lumina://render` query string, and session persistence.
- **Monotonic and smooth.** Ramp tests per stage: output as a function of slider value at fine steps
  (for example 0.1 units over the whole range) is monotonic, with no flat runs or jumps. That would
  show where a form has a plateau (for example a `smoothstep` edge) that fine control would expose.
  Report any stage that fails; fixing forms is that stage's own prompt.

**Done when.** A ⇧⌥ slow drag can land on any value to the stated decimals; the look string, canvas and
export carry it; ramp monotonicity holds at fine steps for every stage, or the failures are listed;
canvas latency is unchanged (`probe.sh edit`); and the owner tries it in Lumina Dev (`hot-build-pusher`)
and approves the feel.

**Depends on:** 00c (the gesture ladder lives in the hand kit's dispatch).

**Skim (video) mirror.** The same continuous values and modifier ladder in Skim's look sliders (`lkClean`
rounds to whole numbers today). The `.cube` export (PR #333) bakes whatever precision the look holds.
