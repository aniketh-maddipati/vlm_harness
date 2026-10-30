# 05b · Colour grading: the agent surface

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-colour-grading-agent` from origin/main.

**Goal.** `COLOUR-GRADING.md` step 6: the grading tools an agent drives, with plan → preview → apply → undo, and the intent vocabulary.

**Build.**
- Expose `grade.measure`, `describe`, `solve`, `match`, `suggest`, `apply`, `undo`, `consistency` as `window.lumina.grade.*` (bridge ops listed in `docs/release/TRUST.md`).
- Wire them to the local planner (LM Studio workflow, see the parameter-prediction spec doc). The planner emits intent → signature targets. **Never sliders from the LLM.** Numeric bounds go through a grammar.
- **Vocabulary:** warm/cool, teal-orange, matte, pastel film, bleach bypass, as signature target shapes. Add a personal vocabulary from the owner's Lightroom Color Grading values only if the owner rules it.
- **UI:**
  - A summoned prompt (never proactive) on the Grade section: type an intent → 3 candidate tiles → release applies → it lands as ordinary keys, editable.
  - For a row or selection: apply with per-photo solve and a residual flag on outliers in the filmstrip.

**Done when.**
- On 3 owner shoots: the "teal-orange, keep skin" and "match this reference" intents produce grades whose consistency beats a blind copy.
- Skin hue drift stays within the skin band.
- Undo is exact.

**Depends on:** 05.

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

**Skim (video) mirror.** Shot matching is the main video use: "match these 12 clips to this one" = signature match per shot, with residual flags on clips under different light. Same tools, run per shot (`grade.match` over clips), landing as each clip's look plus its `.cube`. This is the creator workflow's shot-to-shot colour.
