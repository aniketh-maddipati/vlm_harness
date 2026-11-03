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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Carry: repeat across photos and clips (22)*

This is the "Repeat is built in" section above, as a task of its own:
- select, then touch, with live thumbnails, `× N`, amber residual dots;
- Space (large view) as the contact sheet;
- one ⌘Z.
- Video: scenes, per shot.

*Repeat (the whole spec)*

- **A move is stored with its intent.** Examples: "this photo's shadows", "the sky", "the person",
  "skin", "this hue", "the corner". Paste, "same as last" and apply-to-selection re-solve the intent on
  each photo or clip (`prompts/22`), instead of copying numbers that only fit one frame.
- **Select, then touch.** With photos selected in the filmstrip (⇧-click, or a scene), any gesture on
  the main photo previews live on every selected thumbnail.
  - A count chip `× 24` rides beside the puck. Release applies to all; one ⌘Z undoes all.
  - Photos that couldn't match get a small amber dot. Click it for the reason ("darker light, subject
    12 % of frame vs 30 %") and a nudge.
- **Contact sheet.** **Space** is already the large view. With a selection it becomes the contact
  sheet: all of them graded, side by side, to judge consistency. Dragging on one adjusts that one, relative to the others.
- **Video.** The same, per shot: measured on a few frames and held, so nothing flickers. A scene in
  Skim is a selection.

**Skim (video) mirror.** Shot matching across clips is the creator workflow's core. Same solve: reference shot → each clip measured on 8 frames → per-clip keys → each clip's `.cube`, with residual flags on clips that don't match (different light). Held per clip, so no flicker. "Drag on one clip with a scene selected" applies to all clips in the scene.
