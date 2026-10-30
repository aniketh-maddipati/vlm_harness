# 02 · Clarity, Texture, Vibrance on the page

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-clarity-texture` from origin/main.

**Goal.** Clarity fitted and exposed; Texture added; Vibrance given its slider.

**Now.**
- Clarity renders natively (`clr`, `LookMath.clarity` ~:502) with unfitted round coefficients and no page slider.
- Vibrance (`vib`) is fitted, but only Auto sets it.
- No Texture.

**Build.**
- **Texture** (`tex`): local contrast at a small radius (fine detail: skin pores, foliage), protected from noise and from edges. Clarity (`clr`) is the mid-radius twin. Both are edge-aware: guided filter or bilateral base, not a plain Gaussian, so there are no halos. Measure the halo score.
- **Sweep:** add `--sweep 4` to `lr_cc_sweep.py` with Texture and Clarity at ±25/±50/±100 (and Dehaze, for prompt 03) on 30–50 photos from the 156 pool. Stop for the owner, then fit.
- **UI:**
  - Light section gets Vibrance under Saturation.
  - New "Presence" rows: Texture, Clarity (and Dehaze once 03 lands).
- **On-photo gesture:** with Presence open, a two-finger horizontal swipe on the photo scrubs the setting under the pointer. That gesture already exists for sliders; extend it to the canvas only if it doesn't fight next/previous photo. Otherwise use ⌥-drag ↔ on the photo.

**Done when.** Texture and Clarity: parity criteria on the sweep; halo score no worse than Lightroom's exports; canvas p95 ≤ 16 ms at `small` (blurs are the costly part: check `LookWarmPlan` warms them).

**Depends on:** 00.
