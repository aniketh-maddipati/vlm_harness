# Develop eval — auto arms against the photographer's own hand edits

Stream D of `docs/ELASTIC_PLAN.md`. `design/mvp-test-plan.md` §4 says Develop ships only
when it beats the tester's own final hand edits. This is the measuring stick, with the
owner as the first tester. It **measures** against those edits; it does not fit anything
to them (§4.6 gates taste-model work behind a ruling).

## What it measures

Every arm is an `EditRecipe` rendered through Lumina's own graph on the **authoritative
tier** — exposure and white balance baked onto `CIRAWFilter`, then `applyLook` and
`applyGeometry` — and compared with the photographer's export of the same frame in pixel
space. The hand edit's crop, sharpening and noise reduction are carried into every arm so
that geometry and detail never enter the distance; straighten is zeroed for the pixel
comparison (the hand edits rotate nothing) and reported separately.

| arm | recipe |
|---|---|
| `neutral` | as-shot decode, no tone or colour — the "do nothing" baseline; on untouched frames it *is* the decoder gap |
| `lrMapped` | the hand edit's own Lightroom sliders copied 1:1 onto the fields Lumina renders (exposure, WB, contrast, highlights, shadows, vibrance, saturation); whites / blacks / texture / clarity / dehaze / vignette dropped because the engine does not render them |
| `oracle` | coordinate descent over those same eight fields, minimizing ΔE against the export — the floor no slider-only proposal can beat (a local search from `lrMapped`, so an upper bound on the true floor) |
| `auto` | `AutoDevelop.recipe(for:stats:)` from `session.imageStats()`, exactly what the product applies |
| `autoSubject` | the same rules fed subject-weighted statistics: face boxes when Vision finds faces, else its attention saliency map, else global (an eval-only spike of Stream B) |
| `autoWB` | only the white balance the auto pass writes — is "native Kelvin, tint 0" really as-shot? |
| `model` | `ModelAutoDevelop.proposal` against the local Qwen2.5-VL on loopback (D67); gated on `TEST_RUNNER_LUMINA_LIVE_MODEL=1` |

Distances, on 384 px resamples of both images: mean CIE76 ΔE\*ab in Lab from sRGB, PSNR,
and the signed mean L\* difference (Lumina minus export — positive means Lumina is
brighter), each over the full frame and the central 50 % (which separates vignetting and
lens-profile differences from tone). Slider distances are per-field MAE against the
Lightroom values plus the share of frames where a proposal moved a control the same way the
photographer did. Two diagnostics ride along: `tierGap`, the same recipe rendered on the
interactive tier versus the authoritative one (preview ≡ export), and `wbDrift`.

## Running it

Everything stays on this machine. Raws, exports, previews and the numeric outputs live
outside the repo; the truth file names frames by camera number only.

```bash
# 1. Truth: the 2012 develop fields from the exports' embedded XMP (exiftool, numbers only)
python3 Scripts/harness/eval/lr_truth.py ~/jeevana_mehendi_2026 ~/Pictures/lumina-harness/mehendi-94 \
  ~/Pictures/lumina-harness/eval-out/truth.json

# 2. Render and measure (fixture-gated; skips loudly with no eval set)
TEST_RUNNER_LUMINA_EVAL_RAW_DIR=~/Pictures/lumina-harness/mehendi-94 \
TEST_RUNNER_LUMINA_EVAL_EDIT_DIR=~/jeevana_mehendi_2026 \
TEST_RUNNER_LUMINA_EVAL_TRUTH=~/Pictures/lumina-harness/eval-out/truth.json \
TEST_RUNNER_LUMINA_EVAL_OUT=~/Pictures/lumina-harness/eval-out/mehendi-94 \
TEST_RUNNER_LUMINA_LIVE_MODEL=1 \
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' -test-timeouts-enabled NO \
  -only-testing:LuminaLogicTests/DevelopEvalHarnessTests test-without-building

# 3. Summarize
python3 Scripts/harness/eval/report.py ~/Pictures/lumina-harness/eval-out/mehendi-94/metrics.json \
  --out ~/Pictures/lumina-harness/eval-out/mehendi-94/summary.md
```

`TEST_RUNNER_LUMINA_EVAL_LIMIT=3` makes a smoke run. About 7 s per frame with the model arm.
Each finished frame is appended to `frames.jsonl` in the output folder and a relaunch skips
what is already there, so a run that is killed part-way (the test host quits with code 0 when
another session runs `pkill Lumina`) resumes instead of starting over. Delete the file for
a fresh run.
`TEST_RUNNER_LUMINA_EVAL_CONTACT_DIR=<folder>` additionally writes one JPEG per frame with the
panels neutral · auto · model · oracle · hand edit, left to right — pixels, for the
photographer's own review, in a folder outside the repo.

The public cross-check is MIT-Adobe FiveK (five retouchers per frame, research licence).
`Scripts/harness/eval/fivek_fetch.py` pulls an even-stride subset, reducing each ~30 MB
expert TIFF to a 1024 px sRGB PNG on the way, and writes a slider-free `truth.json` for the
same harness; its catalog is Process Version 2010, so it is compared in pixel space only.

## The eval set

109 frames from one shoot (Sony ILCE-7M3, FE 85 mm f/1.8), edited by the owner in
Lightroom 18.3 / Process Version 15.4. What the hand edits actually use:

| control | frames | mean | range |
|---|---:|---:|---|
| Exposure | 92 | +0.33 EV | −0.2 … +1.0 |
| Highlights | 89 | −40 | −78 … 0 |
| Shadows | 90 | +31 | −20 … +59 |
| Whites | 86 | +13 | −5 … +47 |
| Blacks | 86 | −15 | −34 … 0 |
| Contrast | 88 | +5 | −12 … +22 |
| Vibrance | 87 | +12 | 0 … +20 |
| Saturation | 58 | 0 | −3 … +5 |
| Custom white balance | 22 | | Auto 6, Custom 16 |
| Post-crop vignette | 20 | | −39 … 0 |
| Dehaze / Texture / Clarity | 15 / 9 / 6 | | small |
| Crop | 18 | | no rotation anywhere |
| Masks / heal | 1 / 1 | | |

Tone curve linear and HSL untouched on every frame; camera profile Adobe Standard; lens
profile on. Sixteen frames were left at defaults, which is what calibrates the decoder gap.
Whites and Blacks appear on 86 frames — the two controls Lumina does not render.

## Results — run 1, 2026-09-22 (before any engine change)

109 frames, model arm on, 13.7 min. Full tables in the run's `summary.md`; the numbers that
matter:

| arm | edited frames ΔE (n = 93) | L\* bias | untouched frames ΔE (n = 16) |
|---|---:|---:|---:|
| `neutral` | 10.71 | −7.9 | **5.12** (the decoder gap) |
| `lrMapped` — your own sliders | 15.54 | +11.8 | 5.12 |
| `oracle` | **6.16** | +0.4 | 4.01 |
| `auto` | 19.40 | +16.4 | 26.09 |
| `autoSubject` | 19.46 | +16.5 | 26.05 |
| `autoWB` — auto's white balance only | 11.56 | −7.8 | — |
| `model` | 21.63 | −8.5 | — |

**1. Doing nothing beats auto by 2×, and copying the photographer's own sliders is worse
than doing nothing.** Both render 12–16 L\* too bright. The oracle repairs this by pulling
exposure down a mean **0.93 EV** while keeping the hand highlight/shadow values (highlights
MAE 0.00 — the search never found a better highlights value at all).

**2. Root cause, confirmed on a grey ramp:** `DevelopRenderGraph.applyLook` maps
`CIHighlightShadowAdjust` wrongly.

| parameter | Core Image range (default) | what `applyLook` sends | effect |
|---|---|---|---|
| `inputShadowAmount` | −1 … 1 (0) | `1 + shadows/100` | shadows = 0 already sends **1.0 = maximum lift**; every positive value saturates at the same maximum |
| `inputHighlightAmount` | 0 … 1 (1) | `1 − highlights/100` | recovery (negative highlights) sends > 1, clamped to 1 = **no-op**; positive values darken — sign inverted |

The filter runs whenever highlights *or* shadows is non-zero, so any recipe that touches
either gets the full shadow lift and no highlight recovery. That is the +12 L\* on
`lrMapped`, the +16 L\* on `auto` (whose default curve is −20 / +15), and why the oracle
could not move highlights. Ramp check: shadow amounts 1.0, 1.37 and 1.6 give the same mean;
highlight amounts 1.2 and 1.47 equal identity.

**3. Oracle ceiling.** After subtracting the 5.1 ΔE decoder gap, the eight rendered sliders
get within about 1 ΔE of the hand edits on average. The residual correlates only weakly with
how much whites / blacks / vignette the edit used (r = 0.27; 5.15 vs 6.33 ΔE below and above
20 units), so a tone curve is not the first thing missing — the mapping is. Re-measure after
the fix before deciding on a curve.

**4. Preview ≡ export.** Measured on six frames after correcting an orientation artifact in
the harness (the texture-backed interactive image rasterizes upside down; the harness now
compares it flipped): `neutral` 0.45 ΔE and `lrMapped` 1.38 ΔE between tiers — the two tiers
agree — but `auto` **9.63 ΔE**. `AutoDevelop` writes the camera's native Kelvin as an absolute
`temperature`; the authoritative tier treats that as as-shot, the interactive tier applies it
as a `CITemperatureAndTint` shift from 6500 K. On the authoritative tier alone, auto's white
balance moves the render 3.6 ΔE mean / 12.6 max from as-shot because native tint is dropped
(`autoWB`).

**5. Subject-weighted metering barely moves exposure** on this set: mean |Δ| 0.06 EV, ≥ 0.10 EV
on 20 of 109 frames (faces found on 61, saliency used on 48). This contradicts the earlier
spike's 0.23 EV, which measured embedded previews rather than the interactive tier at
`RawIntent.neutral`, and used no floor weight. With the shadow-lift bug dominating, no
metering change is measurable yet.

**6. Straighten:** auto proposed a non-zero angle on 28 of 109 frames; the hand edits rotate
none. Horizon detection on people shots is a liability, not a correction.

**7. Model arm:** every frame answered (0 fallbacks) and it is the farthest arm. It restyles:
contrast MAE 18 (band edge), highlights moved the wrong way on every frame the photographer
touched them, saturation MAE 15. The band is doing the bounding; the proposals are not
corrections.

**8. Cost:** 7.5 s per frame including the model; 84 look evaluations and 35 decodes per
oracle.

### What to change, in order

1. `applyLook`: `inputShadowAmount = clamp(shadows/100, −1, 1)`,
   `inputHighlightAmount = clamp(1 + highlights/100, 0, 1)` for recovery; positive highlights
   cannot be expressed by this filter and must be documented as such. Then re-run.
2. `AutoDevelop`: stop writing `temperature`; as-shot is the sentinel, and carrying native
   tint needs a field `ImageStats` does not have. Re-measure `tierGap` and `autoWB`.
3. Gate the horizon straighten on something stronger than "Vision returned an angle".
4. Only then look at the auto coefficients — today they are measured through a broken filter.
