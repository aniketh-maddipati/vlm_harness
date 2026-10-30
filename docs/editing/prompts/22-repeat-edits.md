# 22 · Repeat edits across many photos, accurately

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-repeat-edits` from origin/main.

**Goal.** The owner's main goal. Edit one photo and carry it to a row or selection so every photo *looks* the same, solved per photo. Spec: `docs/editing/LEARNED-LOOKS.md`, section "Repeat-an-edit = match the outcome, not the sliders".

**Now.** `=` / `matchScene` copies the look and re-anchors only `ev` and `wb` from the Auto difference.

**Build.**
- **Measure:** the reference's rendered stats (256 px rest render):
  - subject luma (`SetsMasks`)
  - skin hue and chroma
  - a neutral's chroma
  - p5 / p50 / p95 luma
  - sky luma
  - the colour signature from 05, if it has landed
- **Solve:** per target photo, the global tone and WB keys (ev, wb, tint, hl, sh, wh, bl) so its render hits those stats. Coordinate descent or Gauss–Newton through `LookMath` at 256 px, in the Swift pipeline with a numpy mirror for evaluation. Creative keys (curve, HSL, grade, effects) copy unchanged; masks are re-found by kind.
- **Learned correction (rung 2):** from the owner's Lightroom CC "synced then fixed per photo" shoots. **Fitting on their edits needs their ruling; stop and ask.**
- **Scores:**
  - spread of rendered stats across the set vs a blind copy and vs today's `matchScene`
  - on owner-edited sets: slider MAE and ΔE vs their per-photo exports (`parity_personal.py`)
  - PPR10K groups as a research benchmark (never shipped weights)
  - splits by shoot
- **UI (hands-on and automatic together):**
  - Select a row → ⌘V or "Apply to row" → each photo solves, and the filmstrip shows a small residual mark on photos that couldn't match (different light).
  - **Drag on one photo with a row selected applies the same relative move to all**, re-solved.
  - Undo is one step for the whole row.

**Done when.** On 3 owner shoots, consistency spread ≤ half of blind copy's and better than `matchScene`; ΔE vs owner's own per-photo edits lower than both; a 300-photo row solves in ≤ 10 s at `.utility`.

**Depends on:** 14 for masks by kind; 05 for the signature is optional.
