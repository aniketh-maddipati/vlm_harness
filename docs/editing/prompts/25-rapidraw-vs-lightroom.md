# 25 · Measure RapidRAW against Lightroom; adopt its formula wherever it wins

Run the agent loop in `docs/editing/prompts/LOOP.md` (measurement first, then one stage at a time).
Branch `claude/edit-rapidraw-vs-lr` from origin/main.

**Goal (owner, 2026-11-03).** "Match the Lightroom parity baseline, but if RapidRAW is just as good, copy
its formula." So: measure RapidRAW's sliders on the same Lightroom sweep Lumina is measured on, then,
slider by slider, adopt RapidRAW's *form* wherever it is closer to Lightroom than Lumina's.

**Licence, the rule that bites.** RapidRAW is AGPL-3.0. Lumina is a closed App Store app, so **no RapidRAW
code** may enter the repo, translated or not. Its formulas (the maths: a curve, a mask shape, an order of
operations) are ideas: re-derive them in our own code, in all three copies (`LookMath`, `LookKernels`,
`lookmath.py`), with a comment citing the RapidRAW file and line the idea came from (AGENTS.md: "ideas
only, cited in a comment, never code"). If a form can't be expressed without transcribing its code line
by line, describe it in words first and implement from the description.

**Step 1: RapidRAW renders of the sweep.**
- RapidRAW is installed at `/Applications/RapidRAW.app`. Find a batch or headless export path:
  - its repo's `export_processing.rs` mentions headless/batch export;
  - otherwise write its per-image sidecar settings (see its adjustments format) for each sweep position
    and batch-export from the app. The app is driven only with the owner's OK; computer use asks first.
- Sweep 1–2 positions (`~/LuminaEvidence/parity/sweep`, `sweep2`): map each Lightroom slider to its
  closest RapidRAW slider, and write the mapping down (scale, sign, ranges). Exposure is linear gain into
  its tonemapper, Highlights/Shadows are luma-weighted against a blur, WB is a multiplier: say where no
  fair mapping exists.
- Fit only the *scale* of each RapidRAW slider (one number, to its best ΔE at Lightroom's ±50). This
  compares forms, not unit choices. Use RapidRAW's "basic" tonemapper and AgX both, base matched to
  Lightroom's base export where possible.
- Exports go to `~/LuminaEvidence/parity/rapidraw/`, never the repo.

**Step 2: score.**
- `Tools/parity` on the RapidRAW renders: per slider and position, median/p95 ΔE2000 vs Lightroom.
- The better scores (`better.py`) too.
- One table: Lumina vs RapidRAW vs criteria, per slider (add to `RAPIDRAW-PARITY.md`, "Measured").
- Side-by-side images for the worst cases: Lightroom | Lumina | RapidRAW, in the
  `~/LuminaEvidence/review-*` style, sent to the owner.

**Step 3: adopt where RapidRAW wins.**
- For each slider where RapidRAW's form beats Lumina's on the sweep **and** on the unseen Death Valley
  half:
  - implement the form (clean-room, cited) in all three copies;
  - refit its coefficients with `fit.py`;
  - run the held-out set.
- Adopt only within the held-out tolerance in AGENTS.md. Note the held-out is already past its cap on
  main (2.38 / 8.10 vs 8.07); **stop and ask the owner** how to treat the cap before adopting anything.
- One stage per round, with no other change in it.

**Done when.** RapidRAW is measured on every sweep-1/2 slider with a fair mapping. The comparison table and
images are with the owner. Each slider where RapidRAW wins has been tried in Lumina and adopted or
rejected with numbers.

**Skim (video) mirror.** Score Skim's look against RapidRAW's on the same positions (`skim_parity.py`).
Where RapidRAW's form beats Skim's display-referred approximations, port the clean-room form into the LOOK
block (it bakes into the `.cube`, PR #333).
