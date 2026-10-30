# 23 · Learned starting points and outcome shortcuts

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-learned-looks` from origin/main.

**Goal.** `LEARNED-LOOKS.md` rungs 1–3 and its outcome shortcuts: a better starting point than Auto for each kind of photo, and a few named outcomes that land as ordinary keys.

**Build.**
- **Features** (no new shipped model): Vision scene labels, `SetsMasks` shares, EXIF, `ToneAnchor`, FeaturePrint.
- **Targets:** looks with known sliders: the owner's Lightroom CC catalog and XMP (the owner's ruling needed for fitting), Lumina sessions, and FiveK for research benchmarking only.
- **Rung 1:** kNN look (re-anchored like `matchScene`).
- **Rung 2:** per-type regression.
- **Rung 3:** small Core ML net, only if 1–2 plateau.
- Every rung must beat Auto and "same as last" on held-out shoots.
- **Outcome shortcuts:** k-means within type → centroid deltas → named once by the owner. Shortcut = predicted base + delta × strength.
- **UI:**
  - Hold **L** (looks) for 3–5 outcome tiles of this photo, rendered on the canvas tier; release applies. Same grammar as V-hold variations.
  - Drag a tile sideways to set its strength. Summoned, never shown unasked.

**Done when.** Rung chosen with numbers (slider MAE, ΔE vs owner exports, split by shoot); tiles render ≤ 150 ms each; the result lands as editable keys; undo is exact.

**Depends on:** 22 shares the measuring code; the owner's ruling on data.
