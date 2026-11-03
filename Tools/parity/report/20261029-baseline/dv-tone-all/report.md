# Personal parity — baseline-all

20261030-143315 · rules `rules-v1.json` with `rawDevelop.lensShading` 0 · 156 edits of 156 RAWs · compare 1024 px long edge · space sRGB (Lightroom JPEG exports) · RAW decoder default

ΔE2000 per pixel after a 3 × 3 median, pooled with the same number of samples per frame. `frame median` is the median over frames of each frame's median. ΔL*/Δa*/Δb*/ΔC* are render − Lightroom (mean over frames).

## By bucket

| bucket | frames | median | p95 | frame median | ΔL* | Δa* | Δb* | ΔC* | shadows | midtones | highlights | skin | border − centre ΔL* |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| basic-only | 151 | 1.05 | 3.12 | 1.03 | +0.2 | -0.1 | +0.0 | -0.2 | 1.60 | 1.08 | 0.88 | 2.44 | +0.1 |
| unsupported-features | 5 | 1.05 | 3.53 | 1.01 | +0.0 | -0.2 | +0.1 | -0.2 | 1.59 | 1.19 | 0.79 | 3.48 | +0.5 |
| unsupported-features:excluding-profile | 5 | 1.05 | 3.53 | 1.01 | +0.0 | -0.2 | +0.1 | -0.2 | 1.59 | 1.19 | 0.79 | 3.48 | +0.5 |
| **all** | 156 | 1.05 | 3.13 | | | | | | | | | | |

Criteria for reference (Tools/parity/criteria.json, written for single-slider sweeps): singles median ≤ 2.0, p95 ≤ 4.0; combos ≤ 3.0 / 5.0.

## Mean ΔE by Lightroom L* decile

| bucket | 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| basic-only | 2.0 | 2.3 | 2.0 | 1.9 | 2.0 | 1.8 | 2.0 | 1.9 | 1.5 | 1.1 |
| unsupported-features | 1.5 | 2.1 | 2.8 | 4.0 | 3.4 | 2.1 | 2.2 | 1.8 | 1.8 | 1.0 |
| unsupported-features:excluding-profile | 1.5 | 2.1 | 2.8 | 4.0 | 3.4 | 2.1 | 2.2 | 1.8 | 1.8 | 1.0 |

## Mean ΔL* (render − Lightroom) by distance from the centre

Fifths of the half diagonal. A fall-off toward the corners that the sliders don't explain is lens vignetting correction (Lightroom's lens profile is on by default; Lumina has no such stage).

| bucket | 0–0.2 | 0.2–0.4 | 0.4–0.6 | 0.6–0.8 | 0.8–1 |
|---|---:|---:|---:|---:|---:|
| basic-only | +0.1 | +0.1 | +0.2 | +0.2 | +0.2 |
| unsupported-features | -0.8 | +0.1 | -0.1 | +0.1 | +0.4 |
| unsupported-features:excluding-profile | -0.8 | +0.1 | -0.1 | +0.1 | +0.4 |

| lens | frames | as-shot frames | frame median | border − centre ΔL* |
|---|---:|---:|---:|---:|
| E 35mm F2.8 F053 | 72 | 0 | 1.08 | +0.3 |
| FE 85mm F1.8 | 84 | 0 | 1.02 | -0.0 |

## Sliders (edited frames: basic-only + unsupported-features)

`ρ` is the rank correlation of the frame's median ΔE with the slider's magnitude; `ΔL*/unit` is the slope of the frame's mean ΔL* (render − Lightroom) on the slider's signed value (Exposure per stop, WB per mired of warming, others per slider unit): a negative slope on a brightening slider means Lumina's stage does less than Lightroom's.

| slider | frames active | ρ(|v|, ΔE) | ΔL*/unit | r | other |
|---|---:|---:|---:|---:|---|
| Exposure | 0 | – | – | – |  |
| WhiteBalance | 1 | 0.13 | -0.012 | -0.03 | Δb*/mired -0.135 (r -0.40) |
| Contrast | 0 | – | – | – |  |
| Highlights | 0 | – | – | – |  |
| Shadows | 0 | – | – | – |  |
| Whites | 0 | – | – | – |  |
| Blacks | 0 | – | – | – |  |
| Vibrance | 0 | – | – | – |  |
| Saturation | 0 | – | – | – |  |
| Clarity | 0 | – | – | – |  |
| Sharpness | 156 | – | – | – |  |
| PostCropVignette | 0 | – | – | – |  |

## Unsupported features (frames with the feature, their median ΔE)

- aiDenoise: 2 frames, frame median 1.12
- filter:Distracting People Removal: 2 frames, frame median 1.01
- filter:Enhance: 1 frames, frame median 1.00
- masks: 1 frames, frame median 1.21

White balance for non-As-Shot edits: Lightroom's as shot estimated from Apple's with -6.1 mired (MAD 3.2) and tint +4.7 (MAD 2.0), from 155 As Shot exports.

## Alignment

Every render lines up with its reference within 1 px at the comparison size.

## Worst frames

- `DSC06779__edit01` (basic-only) median 6.32, p95 9.70, ΔL* +0.9
- `DSC06780__edit01` (basic-only) median 5.91, p95 9.03, ΔL* +1.1
- `DSC06781__edit01` (basic-only) median 4.84, p95 8.92, ΔL* +0.8
- `DSC06707__edit01` (basic-only) median 2.09, p95 3.60, ΔL* +0.3
- `DSC06714__edit01` (basic-only) median 1.46, p95 2.69, ΔL* -0.3
- `DSC06795__edit01` (basic-only) median 1.45, p95 2.87, ΔL* -0.8
- `DSC06708__edit01` (basic-only) median 1.45, p95 2.40, ΔL* +0.2
- `DSC06796__edit01` (basic-only) median 1.45, p95 2.81, ΔL* -0.9

## Timing (seconds)

| import |   xmp |   as-shot | render |   renders |   decodes |   develop ms (sum) |   look+encode ms (sum) | ΔE |   pairs |   workers | report | total |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 58.1 | 3.4 | 21.0 | 197.7 | 156 | 156 | 157.7 | 39.6 | 68.3 | 156 | 6 | 0.0 | 324.2 |

## Per frame

In the run's evidence folder (~/LuminaEvidence/<root>/report/…), not committed.
