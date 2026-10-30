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
