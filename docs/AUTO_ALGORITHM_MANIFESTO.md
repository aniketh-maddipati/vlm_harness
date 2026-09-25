# Auto algorithm manifesto: conservative, deterministic, reversible

2026-09-24. User-reported failure: Auto overexposes photographs. This document specifies the current corrective development policy; it does not claim visual acceptance or that an already-running app has changed.

## Product promise

Auto makes a restrained technical starting point. It does not make every photograph equally bright. Darkness, silhouettes, bright backgrounds and warm light can be intentional. The photographer's geometry, white balance and hand work have priority. Same source measurements and base recipe produce the same output. One activation owns one undo, and unavailable measurements never invent an adjustment.

## What was wrong in the code

The previous exposure rule was `roundTo0.05(clamp((0.46 − mean) × 3, −1.5, +1.5))`. At mean 0.15 it proposed +0.95 EV irrespective of bright highlights. Independently, shadows received +15 even without measured clipping, or up to +60 with clipping. This can combine global brightening and shadow lift. Highlight recovery is not proof that the global lift is safe.

The mean is measured from an 8-bit display-color-space bitmap with weighted RGB values. It is not a calibrated scene-linear exposure meter. Mean alone cannot establish that a dark photograph is underexposed. This is a demonstrated weakness of the rules, not yet a measured causal attribution for every photo the user saw. The active binary, base recipe, source pixels and rendered result must be recorded to finish the RCA.

## Encoded correction policy in this working tree

1. **Exposure:** retain the existing mean-based proposal as a bounded heuristic, now capped at −1.00…+0.35 EV and quantized to 0.05 EV. Invalid or out-of-range mean produces zero. The cap is a conservative development choice, not an aesthetically calibrated optimum.
2. **Positive-exposure veto:** permit a positive proposal only with a valid nonempty 32-bin histogram, a finite highlight clip fraction in 0…0.005, and the upper edge of the 98th-percentile bin below 0.80. Otherwise exposure is zero. This uses display-space headroom as a warning signal, not a conversion from histogram bins to RAW EV.
3. **Highlights:** zero when clipping is insignificant; otherwise retain bounded recovery `−min(80, clipFraction × 3000)`. Invalid fractions produce zero. No generic −20 curve on every frame.
4. **Shadows:** zero when clipping is insignificant; otherwise `min(20, clipFraction × 1000)`. No automatic +15 lift and no +60 lift. This cap reduces the stacked-lift failure; it cannot determine artistic intent.
5. **Color:** preserve the complete existing WB pair, including the as-shot sentinel. Preserve saturation/contrast from the base. Existing vibrance +8 is retained pending a separate color study; this policy does not claim a strictly neutral color transform.
6. **Geometry:** preserve crop, crop aspect and the complete existing rotation. Horizon detection never changes tone Auto geometry.
7. **Unsupported controls:** keep Whites, Blacks and Dehaze pinned to zero under the existing engine contract. Do not claim unsupported corrections.
8. **Application:** the visible Elastic Auto path remains deterministic. No model selection, random sampling, remote inference or learned preference is needed. Existing optional model experiments are not authorization to bypass this policy.

This policy reduces risk; it does not guarantee zero new clipping. Luminance can miss a clipped color channel, small specular regions can fall below the percentile, and RAW rendering is nonlinear. A future candidate-validation pass should render through the production graph and reject worsened clipping/skin or excessive brightness changes. That feedback loop is proposed, not implemented here. Do not present these numerical thresholds as universal photographic laws.

## Acceptance packet before calling this fixed

- Record app path, build revision, dirty patch hash, source hash, base recipe, measurement image/color pipeline, statistics, exact proposed controls and rendered before/after images.
- Compare as-shot, former Auto and conservative Auto on the actual affected photographs. Include daylight portraits, backlight, sunsets, night/silhouettes, high ISO, bright snow, mixed light and saturated stage lighting, across available RAW and JPEG inputs.
- Inspect highlight/skin loss, lifted blacks, noise, saturation and scene intent at equal viewing conditions. Require user preference or explicitly documented acceptance; passing numeric tests does not establish good taste.
- Repeating Auto with unchanged source statistics must not accumulate exposure. Header and per-photo Auto must agree. Undo restores the exact previous effective recipe. Hand/sidecar protection remains intact.
- Test missing/invalid measurements, dark scenes with bright clipped and unclipped highlights, limited headroom, and wholly dark distributions. Existing tests cover deterministic behavior, WB, geometry and undo; the new cases cover the positive-exposure veto.
- Do not migrate or overwrite already-saved Auto recipes silently. Existing cached/applied edits may still show the previous look. Use explicit before/Auto selection or undo during comparison and record which recipe is shown.

## Next algorithm iteration

First establish measurement provenance and native before/after acceptance. Then evaluate robust percentiles and channel headroom on a linear measurement path, followed by candidate rendering and bounded backoff. Do not simply replace the mean target with another unexplained target or use an AI score to conceal a renderer mismatch. Keep coefficients in one versioned policy and store evaluation evidence for every change.

The AI experiment plan is downstream: it may rank safe candidates or learn tone proposals after this baseline is trustworthy. It must preserve these invariants and beat the deterministic incumbent on held-out shoots. Fine-tuning is not the remedy for incorrect exposure arithmetic, stale binaries or accidental rotation.
