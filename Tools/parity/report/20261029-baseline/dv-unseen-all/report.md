# Personal parity — baseline-all

20261030-142549 · rules `rules-v1.json` with `rawDevelop.lensShading` 0 · 468 edits of 78 RAWs · compare 1024 px long edge · space sRGB (Lightroom JPEG exports) · RAW decoder default

ΔE2000 per pixel after a 3 × 3 median, pooled with the same number of samples per frame. `frame median` is the median over frames of each frame's median. ΔL*/Δa*/Δb*/ΔC* are render − Lightroom (mean over frames).

## By bucket

| bucket | frames | median | p95 | frame median | ΔL* | Δa* | Δb* | ΔC* | shadows | midtones | highlights | skin | border − centre ΔL* |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| basic-only | 450 | 1.54 | 5.53 | 1.50 | -0.0 | -0.1 | -0.1 | -0.3 | 2.08 | 1.79 | 1.24 | 3.51 | +0.5 |
| unsupported-features | 18 | 1.50 | 5.54 | 1.46 | -0.3 | -0.2 | -0.0 | -0.2 | 1.67 | 1.84 | 1.02 | 3.14 | +1.2 |
| unsupported-features:excluding-profile | 18 | 1.50 | 5.54 | 1.46 | -0.3 | -0.2 | -0.0 | -0.2 | 1.67 | 1.84 | 1.02 | 3.14 | +1.2 |
| **all** | 468 | 1.54 | 5.53 | | | | | | | | | | |

Criteria for reference (Tools/parity/criteria.json, written for single-slider sweeps): singles median ≤ 2.0, p95 ≤ 4.0; combos ≤ 3.0 / 5.0.

## Mean ΔE by Lightroom L* decile

| bucket | 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| basic-only | 2.9 | 3.2 | 3.1 | 3.1 | 3.2 | 3.0 | 2.9 | 2.8 | 2.5 | 1.9 |
| unsupported-features | 2.1 | 2.7 | 3.3 | 3.6 | 3.6 | 3.8 | 3.4 | 2.8 | 2.4 | 1.6 |
| unsupported-features:excluding-profile | 2.1 | 2.7 | 3.3 | 3.6 | 3.6 | 3.8 | 3.4 | 2.8 | 2.4 | 1.6 |

## Mean ΔL* (render − Lightroom) by distance from the centre

Fifths of the half diagonal. A fall-off toward the corners that the sliders don't explain is lens vignetting correction (Lightroom's lens profile is on by default; Lumina has no such stage).

| bucket | 0–0.2 | 0.2–0.4 | 0.4–0.6 | 0.6–0.8 | 0.8–1 |
|---|---:|---:|---:|---:|---:|
| basic-only | -0.2 | -0.2 | -0.1 | +0.1 | +0.3 |
| unsupported-features | -1.9 | -0.5 | -0.3 | -0.1 | +0.3 |
| unsupported-features:excluding-profile | -1.9 | -0.5 | -0.3 | -0.1 | +0.3 |

| lens | frames | as-shot frames | frame median | border − centre ΔL* |
|---|---:|---:|---:|---:|
| E 35mm F2.8 F053 | 216 | 0 | 1.60 | +0.9 |
| FE 85mm F1.8 | 252 | 0 | 1.44 | +0.2 |

## Sliders (edited frames: basic-only + unsupported-features)

`ρ` is the rank correlation of the frame's median ΔE with the slider's magnitude; `ΔL*/unit` is the slope of the frame's mean ΔL* (render − Lightroom) on the slider's signed value (Exposure per stop, WB per mired of warming, others per slider unit): a negative slope on a brightening slider means Lumina's stage does less than Lightroom's.

| slider | frames active | ρ(|v|, ΔE) | ΔL*/unit | r | other |
|---|---:|---:|---:|---:|---|
| Exposure | 0 | – | – | – |  |
| WhiteBalance | 0 | – | – | – |  |
| Contrast | 0 | – | – | – |  |
| Highlights | 234 | 0.11 | +0.007 | 0.21 |  |
| Shadows | 234 | 0.12 | -0.001 | -0.04 |  |
| Whites | 0 | – | – | – |  |
| Blacks | 0 | – | – | – |  |
| Vibrance | 0 | – | – | – |  |
| Saturation | 0 | – | – | – |  |
| Clarity | 0 | – | – | – |  |
| Sharpness | 468 | – | – | – |  |
| PostCropVignette | 0 | – | – | – |  |

## Unsupported features (frames with the feature, their median ΔE)

- aiDenoise: 6 frames, frame median 1.46
- filter:Distracting People Removal: 6 frames, frame median 1.71
- filter:Enhance: 6 frames, frame median 1.31
- masks: 6 frames, frame median 1.71

White balance for non-As-Shot edits: Lightroom's as shot estimated from Apple's with -6.2 mired (MAD 3.2) and tint +4.7 (MAD 2.0), from 468 As Shot exports.

## Alignment

Every render lines up with its reference within 1 px at the comparison size.

## Worst frames

- `DSC06805__edit05` (basic-only) median 11.10, p95 18.92, ΔL* -6.2
- `DSC06797__edit05` (basic-only) median 9.83, p95 14.20, ΔL* -9.6
- `DSC06780__edit05` (basic-only) median 6.75, p95 10.99, ΔL* +0.6
- `DSC06789__edit05` (basic-only) median 6.36, p95 8.98, ΔL* -6.2
- `DSC06780__edit06` (basic-only) median 6.32, p95 9.91, ΔL* +0.9
- `DSC06780__edit03` (basic-only) median 6.07, p95 9.22, ΔL* +0.8
- `DSC06780__edit01` (basic-only) median 5.94, p95 8.79, ΔL* +1.5
- `DSC06780__edit02` (basic-only) median 5.85, p95 8.87, ΔL* +1.3

## Timing (seconds)

| import |   xmp |   as-shot | render |   renders |   decodes |   develop ms (sum) |   look+encode ms (sum) | ΔE |   pairs |   workers | report | total |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 12.5 | 7.7 | 0.0 | 128.8 | 468 | 78 | 52.8 | 75.0 | 179.4 | 468 | 6 | 0.1 | 320.7 |

## Per frame

In the run's evidence folder (~/LuminaEvidence/<root>/report/…), not committed.
