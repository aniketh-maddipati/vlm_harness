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

*Light: exposure, highlights, shadows, whites, blacks (prompts 01, 02 for vibrance)*

- **Do:** press anywhere and drag ↕. The tone under the finger chooses the slider: blacks, shadows,
  highlights or whites. ⌘-drag ↕ is exposure for the whole photo.
- **Hands:** while pressed, a thin tone bar (black → white, 4 px) beside the puck marks where your tone
  sits. The pixels in that band glow faintly on the photo (a 20 % luminance key) so you see what moves.
- **Repeat:** stored as "this photo's band"; re-solved per photo with the tone anchor, so "lift the
  shadows" lifts *each* photo's shadows by the same look.
- **Polish:** the histogram lights the band you hold; nothing else changes on screen.

**Skim (video) mirror.** Clarity and Texture need a blur pass: a second WebGL pass at reduced size in Skim's viewer. They are spatial, so not LUT-able: preview only in Final Cut unless a native render is added later, and the UI says so. Check flicker on a T7 clip; the edge-aware base must be stable frame to frame.
