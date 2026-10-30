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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Grade: colour grading (05, 05b), the flagship*

- **Do:** press anywhere. A **grade wheel blooms under your finger** (160 px), centred on that pixel's
  current colour, drawn in Oklab so equal distances look like equal changes.
  - A thin arc around it shows which tone you grabbed (shadows to highlights).
  - Drag toward a colour: the distance is the amount, with resistance that grows from the centre, so
    small moves are fine and big moves still possible. That tone and its neighbours take the colour.
  - Release and the wheel fades (120 ms).
- **Hands:**
  - ⌥↕ = lightness of that tone.
  - Pinch while pressed = blending (how far the colour spreads through the tones).
  - Two-finger rotate = spin the hue only, keeping the amount.
  - **⇧ = complementary:** a ghost dot moves the opposite region toward the opposite hue (teal against
    orange), and the two stay locked while you drag.
  - Detents tick at neutral and on the skin line's hue.
- **The tone strip** (the panel, replacing three static wheels):
  - a 12 px bar from black to white showing the graded colour at every tone;
  - three soft handles (shadows / mid / highlights) slide along it (balance), and grabbing one blooms
    the same wheel.
  - Lightroom users get the classic three wheels plus a global one behind a fold, with the same keys.
- **See:** hold **⌘** while grading for the vectorscope over the photo. The photo's colours appear as a
  soft cloud tinted by region, with the skin line as a hairline. Drag the shadow cloud itself toward a
  colour. The skin tick turns amber if skin leaves the line.
- **Repeat:**
  - grades are tone-relative, so "teal shadows" means *each photo's* shadows;
  - **drop any photo or film still onto the strip** to match its colour-by-tone;
  - apply to a selection with per-photo solve and amber residual dots.
  - Video: shot matching across clips, per shot.
- **Agent (05b):** press **/** and type what you want ("warmer, teal shadows, keep skin"). Three
  candidates fan out as tiles (the same fan as Looks, below); release on one to apply. It lands as
  ordinary strip handles you can grab.
- **Polish:** the wheel is a 1 px hairline circle with six hue ticks. The only fill is the colour you
  are pushing toward. The value reads `Shadows · teal 196° · 24`.

**Skim (video) mirror.** Already in scope (port to `LK_FS`). Add: grades reach Final Cut as a `.cube` per shot. Relative mode uses shot percentiles (held per shot). The signature is measured per shot on 8 frames. Skim's Grade UI gets the same tone strip and on-viewer wheel. Reference: compare Skim's grade with Final Cut's Color Wheels on the same values for sanity (not parity).
