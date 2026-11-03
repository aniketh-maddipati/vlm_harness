# Learned looks: per-type defaults → outcome shortcuts (running note)

Living note. Append dated lines under **Log**; keep the rest current. Older, wider spec (slider net,
planner → intent vector, measured latencies): the Claude Doc
https://claude.ai/code/artifact/a32f15d9-ecbd-463b-8ecc-406fcdd86bf9.

## Goal (owner, 2026-10-29: what the people they talk to want)
1. **Repeat my edit across many photos, accurately.** Edit one (or a few); the rest of the set should
   *look* the same, not just carry the same slider numbers. Copying sliders fails because exposure,
   light, white balance and subject differ from frame to frame. This is the main target.
2. Secondary: per-type starting points and outcome shortcuts ("clean", "warm airy", "moody"), landing
   as an ordinary look string. Summoned, never proactive; editable and undoable like any slider move.

## Repeat-an-edit = match the outcome, not the sliders
- **Today:** `=` / `matchScene` copies the look and re-anchors `ev` and `wb` from each photo's Auto
  difference. Good first step; tone, colour and local edits are still copied blindly.
- **Next: solve per photo.** Measure the reference edit's *rendered* result: subject luma (from
  `SetsMasks`), skin hue/chroma, a neutral's chroma, p5/p50/p95 of luma, sky luma if present. For each
  target photo, search the few global sliders (ev, wb/tint, hl, sh, wh, bl; 6 numbers) so its render
  hits those numbers. The renderer is the model: `lookmath.py` / `LookMath` at 256 px take
  milliseconds, so a small solve (coordinate descent, or Gauss–Newton on finite differences) per
  photo is cheap. The creative sliders (curve, HSL, grading, effects) copy unchanged; they are the
  "style".
- **Local edits follow the subject:** masks are re-found per photo (person / sky / subject,
  `SetsMasks`), never copied as pixels. A brushed mask needs a correspondence step (FeaturePrint
  region match or Vision tracking, as Skim's Follow does on video), so it ships later.
- **Ground truth already exists in the owner's Lightroom CC catalog:** shoots where settings were
  synced and then *corrected per photo*. Those per-photo corrections are exactly what a blind copy
  gets wrong. Learning them as f(difference between the photos: ToneAnchor, as-shot K, subject share,
  ISO) is rung 2 below, and it is the highest-value dataset for this goal.
- **Public benchmark for exactly this:** PPR10K (11,161 RAW portraits incl. ARW, 1,681 groups, 3
  experts, Camera Raw XMP per photo, group-consistent edits, human masks). Non-commercial research:
  measure the solve on it, never ship weights fitted on it. FiveK (5,000 DNG × 5 experts, Lightroom
  catalog with sliders, subject/light/time labels) is the per-type prior benchmark, also research-only.
  JarvisArt's MMArt-PPR10K adds instruction → Lightroom edit pairs (same licence caveat).
- **Metric:** across a set, how far the rendered stats spread from the reference (consistency), plus,
  on owner-edited sets, slider MAE and ΔE2000 vs their per-photo export. Baselines: blind copy and
  today's `matchScene`.

## Pieces (all local, all shippable)
- **Param space = the look string.** Already the only Edit state; every target is a vector of its keys.
  Normalise each key by its slider range; crop/rot excluded.
- **Photo type = features we already compute**, no new model to ship:
  - Vision `VNClassifyImageRequest` labels (already used for sky), `SetsMasks` person / sky / subject share
  - EXIF: ISO, shutter, aperture, focal, flash, as-shot K/tint
  - `ToneAnchor` (log-mean luma, spread, share above L* 80, p95): the tone sliders' own inputs
  - FeaturePrint (`SetsNear`): for nearest neighbours
  - MobileCLIP can't ship (licence); Vision suffices.
- **Targets = edited looks with known sliders.** Sources, best first:
  - the owner's Lightroom CC catalog (`settings/<sha>` readable offline)
  - `import_lr_edits.py` / embedded XMP of exports
  - FiveK's expert catalogs (research licence: fit and measure only, never ship weights trained on it
    without checking)
  - Lumina sessions themselves (`look` per photo): grows with use
  - LR slider names → look keys go through the same mapping `import_lr_edits.py` uses.

## Ladder (stop at the first rung that beats the baseline)
0. **Baseline:** Auto (`lumina.auto`) and "same as last photo" (`=` / `matchScene`). Everything must
   beat both on the held-out split.
1. **kNN look:** average the looks of the k nearest edited photos (FeaturePrint + type + EXIF), with
   exposure and WB re-anchored per photo the way `matchScene` already does. No training. Likely strong.
2. **Learned correction:** Δslider (target − reference) = f(Δ ToneAnchor, Δ as-shot K, Δ subject share,
   Δ ISO), fitted on the owner's synced-then-corrected pairs. Small, linear, explainable. Also per type:
   slider = f(ToneAnchor, as-shot K, ISO) for a cold start with no reference.
3. **Small net** (boosted trees or a 2-layer MLP, Core ML, < 1 MB): features → slider vector.
   Only if 1–2 plateau.

## Outcome shortcuts
- Within each type, cluster edited looks (k-means on normalised vectors, k ≈ 3–5). Each centroid,
  minus the type's median, is an **outcome delta**: "airy" = +ev +sh −con −clarity, warm wb…
- Shortcut = predicted base (rung 1–3) + outcome delta × strength. Drag the shortcut chip sideways
  to scale 0–150 %, as a slider drag (same `dragStart`/`dragEnd`, same canvas schedule).
- Names: the owner names clusters once. An offline VLM can propose names; nothing runs online.
- Surface: hold-V variations already show a strip of alternatives for one setting. Same grammar,
  whole look: hold L → 3–5 outcome tiles for this photo, release applies.
- Shoot level (agent vision): apply an outcome to a row/scene with per-photo re-anchoring, the
  "graded bulk edit".

## Evaluation
- Splits by shoot, never by photo (bursts leak). Report slider MAE per key and ΔE2000 of the render
  vs the editor's export (`parity_personal.py` already does the render side).
- **Owner's call before fitting on their own edits:** the 2026-09-30 ruling makes the mehendi set
  measure-only for the look stages. Learning their *style* is a different use; dehaze was fitted on
  the DV edits by their call (2026-10-29). Keep the mehendi set held out regardless.

## Open questions
- Is "type" needed at all, or does kNN on FeaturePrint already carry it? (Measure rung 1 with and
  without the type filter.)
- How many edited photos per type before a cluster is stable? Guess ≥ 30.
- Per-photographer only, or ship a starter prior from FiveK? (Licence says probably not.)

## Log
- 2026-10-29: goal reframed by owner: repeat edits across many photos accurately (primary) + hands-on
  manipulation like a physical print. Outcome-matching solve + LR "synced then corrected" pairs added.
- 2026-10-29: note started (RapidRAW parity session). Existing hooks: `lumina.auto`, `matchScene`,
  V-hold variations, `SetsNear` FeaturePrint, `SetsMasks` labels, `ToneAnchor`.
