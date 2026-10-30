# 05 · Colour grading (full design)

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-colour-grading` from origin/main.

**Goal.** Build `docs/editing/COLOUR-GRADING.md` steps 1–5: the stage, the Lightroom fit, the page UI, the hands-on controls, the colour signature and solver. Step 6 (agent tools) is prompt 05b. Read the design doc in full; it is the spec.

**Build** (summary; the doc has the detail):
- **Stage:** Oklab (a,b) tint per region with a chroma envelope (no coloured blacks), a separate lift, partition-of-unity regions on Oklab L, and Balance/Blending.
  - Absolute mode (Lightroom parity) and relative mode (photo percentiles, the default for repeat-across).
  - Luminance per region as a tone-curve move.
  - Soft gamut compression in Oklab, skin protection.
- **Keys:** Skim's names `grade.<sh|mid|hi|all>.<h|s|l>`, `grade.blend`, `grade.bal`, plus `grade.rel`, `grade.lift`, `grade.skin`. Their look-string form needs owner sign-off before it lands (a shared key name).
- **Sweep 6:** wheels × 4 hues × sat 25/50, lum ±50, blending 25/75, balance ±50, plus 10 combos. Fit the absolute mode; measure the relative one.
- **UI:**
  - A Grade section in Edit: tone strip plus three wheels and a global one.
  - On-photo press → a wheel under the finger around that pixel's colour; ⌥↕ lightness.
  - Hold-key vectorscope with skin line; ⇧ complementary; reference match (drop a photo).
- **Skim:** port the same maths to `LK_FS` (Skim's GLSL) so video and stills match. Check with `Tests/web/skim-look.test.mjs`.
- **Signature + solver:** `grade.measure` / `solve` / `match` / `consistency` in Swift, with a numpy mirror.

**Done when.**
- Parity criteria on sweep 6 (absolute mode).
- Better scores: blacks don't lift, hue doesn't drift on skin, and the relative mode spreads less than absolute across the 156 photos.
- `consistency` reported on 3 owner shoots.
- canvas p95 ≤ 16 ms.

**Depends on:** 00, 04 (the mixer's Oklab bands and skin band).
