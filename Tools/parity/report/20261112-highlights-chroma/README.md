# Highlights colour: a chroma term in the tone stage, 2026-11-12

The LLF prototype (`claude/highlights-llf-proto-d2f69d` `ff6ea0d2`) showed that the tail of Highlights −100 is colour,
not locality. This adds a predictable chroma term, with no per-photo oracle. Numbers only. Renders and logs are in
`~/LuminaEvidence/hl-chroma`. Prototype: `Tools/parity/hl_chroma/`. Base: `claude/great-kepler-bb12b6` (camera profile, #354)
with `claude/blacks-lightcraft` (#352) merged in.

## What Lightroom does (`measure.py`, `clipcheck.py`)

On Lightroom's base → its Highlights exports, Death Valley tone set (153) and sweep 1 (5), Oklab chroma of Lightroom vs
today's tone stage, C-weighted log2 ratio:

- It all sits in the brightest tones. Below base Oklab L 0.8 the ratio is within ±0.04. Above it, −100 gives
  +0.10 (L 0.85), +0.18 (0.90) and +0.58 (0.95): Lightroom keeps or returns colour as it pulls highlights down. +50 gives
  −0.08, −0.14 and −0.49: it washes them toward white. It holds with clipped base pixels left out.
- It is roughly linear in the slider (−50 is about half of −100).
- Per photo it barely varies (sd 0.08 log2 at −100). It follows absolute brightness, not the photo's anchor.

## Form

After the tone curve: `out' = y + (out − y)·s`, y = luma of out, with
`s = 2^(k · highlights/100 · smoothstep(lo, hi, perceptual(base)))`. Here `base` is the tone stage's blurred luma, and (k, lo, hi)
is `highlightsChromaDown/Lo/Hi` below 0 and `highlightsChromaUp/Lo/Hi` above. s is capped so no channel goes below 0. Luma is
kept, grey stays grey, and the term is off at 0. That is 3 coefficients per side.

The fit was on DV even half (dev, 77) at 256 px, scored on mean ΔE76 + ¼ p95. It gave k −2.15 / lo 0.860 / hi 1.135
below 0 and k −10.21 / lo 0.777 / hi 1.640 above 0. A mask on the photo-relative luma (× the Highlights normaliser nh) was
fitted too and lost (−100 unseen p95 4.62 vs 4.31). So did a strength scaled by the photo's Highlights gain (4.64).

## Shape on Lightroom's base (ΔE2000 median / p95 at 512 px, pooled)

| position | set | today | + chroma | per-photo chroma LUT (oracle) |
|---|---|---|---|---|
| −100 | dev | 1.58 / 5.80 | 1.54 / 5.15 | 1.54 / 5.16 |
| | unseen | 1.65 / 4.71 | **1.58 / 4.31** | 1.61 / 4.41 |
| | sweep | 1.16 / 9.52 | 1.15 / 8.38 | 1.26 / 8.46 |
| −50 | dev | 0.88 / 2.83 | 0.86 / 2.51 | 0.86 / 2.49 |
| | unseen | 0.91 / 2.35 | 0.89 / 2.18 | 0.90 / 2.19 |
| | sweep | 0.74 / 4.82 | 0.72 / 4.35 | 0.75 / 4.60 |
| +50 | dev | 0.88 / 2.54 | 0.82 / 2.25 | 0.82 / 2.13 |
| | unseen | 0.90 / 2.38 | **0.85 / 2.06** | 0.85 / 2.02 |
| | sweep | 0.76 / 4.16 | 0.72 / 3.93 | 0.74 / 3.79 |

The global 6-coefficient form matches a chroma table fitted per photo on the answer. On today's curve, that is about all
a chroma-only term can do. The LLF oracle's 3.16 at −100 also needs a per-photo luma curve, which is a separate problem.

## Real renders (lumina-render, RAW → Lumina's whole chain)

Sweep 1, Highlights, 15 pairs (`parity.py`, dev), pooled median / p95:

| position | before | after |
|---|---|---|
| all | 1.32 / 7.61 | **1.27 / 7.33** |
| −100 | 1.38 / 11.12 | 1.36 / 11.05 |
| −50 | 1.21 / 6.79 | 1.19 / 6.78 |
| +50 | 1.36 / 5.04 | 1.30 / 4.90 |

Death Valley unseen half, 78 photos × 6 positions (`parity_personal.py`, forced renders; none seen by the fit). Columns:
median of frame medians / median of frame p95s, and the mean of frame p95s:

| position | before | after |
|---|---|---|
| −100 | 1.91 / 4.82 · 6.16 | **1.73 / 3.93 · 5.78** |
| −50 | 1.26 / 3.48 · 4.59 | 1.19 / 3.32 · 4.45 |
| +50 | 1.49 / 3.96 · 4.90 | 1.45 / 3.59 · 4.80 |
| Shadows −50 / +50 / +100 (controls) | unchanged | unchanged |
| all 468, pooled | 1.53 / 7.42 | 1.50 / 7.37 |

Held-out mehendi (109 edits, forced renders, the same machine and binary build for both columns). The adoption gate is
+0.05 median and +0.10 p95:

| set | before | after |
|---|---|---|
| all 109 | 2.18 / 7.97 | **2.18 / 7.95** |
| basic-only 76 | 2.26 / 7.54 | 2.25 / 7.51 |

**Adopted.** The dev sets improve, the unseen DV half improves, and held-out mehendi is flat to slightly better.

## Checks

- `make parity-check`: Metal ≡ Swift ≡ numpy, worst 0.0000 at hl −100 / −50 / +50 / +100 and 0.0044 on a mixed look.
  The ramp gained three bright colour patches, so the term is exercised. Before this change no patch reached it.
- Grey ramp is unchanged at every Highlights value, so it stays monotonic and grey stays grey.
- `LookMathTests.testHighlightsChromaKeepsLumaAndGrey` checks that luma is kept, grey stays grey, the direction is right per
  sign, dark colours are untouched and no channel goes below 0.
- LuminaLogicTests 614 / 0 (1 skipped) before the new test. LookMathTests + LookPipelineTests 58 / 0 with it.
  Parity tool tests 128 OK.
- Not measured: canvas latency (`probe.sh edit`, screen-owning). The kernel gains one branch, one `pow` and one `exp2`
  per pixel when Highlights ≠ 0.

## Open

- +100 is extrapolated (no +100 sweep exists). k_up is large: a pixel at perceptual luma 1.3 loses most of its chroma at +100.
- What is left of −100's tail (sweep p95 ~11 real, 8.4 on Lightroom's base) is the per-photo luma curve, as the LLF
  prototype found.
