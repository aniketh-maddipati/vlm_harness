# Personal parity — baseline-held

20261030-142127 · rules `Lumina/Sets/Look/rules-v1.json` · 109 edits of 94 RAWs · compare 1024 px long edge · space sRGB (Lightroom JPEG exports) · RAW decoder default

ΔE2000 per pixel after a 3 × 3 median, pooled with the same number of samples per frame. `frame median` is the median over frames of each frame's median. ΔL*/Δa*/Δb*/ΔC* are render − Lightroom (mean over frames).

## By bucket

| bucket | frames | median | p95 | frame median | ΔL* | Δa* | Δb* | ΔC* | shadows | midtones | highlights | skin | border − centre ΔL* |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| as-shot | 16 | 1.73 | 6.02 | 1.64 | -0.9 | +0.3 | +0.1 | -0.3 | 1.41 | 2.11 | 1.39 | 2.66 | -0.1 |
| basic-only | 71 | 2.42 | 7.83 | 2.33 | -0.9 | +0.3 | -0.3 | -0.9 | 1.95 | 2.75 | 2.04 | 3.08 | -1.4 |
| unsupported-features | 22 | 2.97 | 9.72 | 2.97 | +1.0 | +0.8 | +0.5 | +0.1 | 2.27 | 3.73 | 2.87 | 3.37 | +2.4 |
| unsupported-features:excluding-profile | 16 | 3.03 | 9.12 | 2.97 | +1.5 | +0.8 | +0.4 | -0.0 | 2.46 | 3.16 | 3.03 | 2.87 | +3.0 |
| **all** | 109 | 2.38 | 8.10 | | | | | | | | | | |

Criteria for reference (Tools/parity/criteria.json, written for single-slider sweeps): singles median ≤ 2.0, p95 ≤ 4.0; combos ≤ 3.0 / 5.0.

## Mean ΔE by Lightroom L* decile

| bucket | 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| as-shot | 1.2 | 2.1 | 2.6 | 2.8 | 3.0 | 3.4 | 2.8 | 2.3 | 2.4 | 2.7 |
| basic-only | 2.0 | 2.8 | 2.8 | 3.1 | 3.8 | 4.4 | 4.0 | 3.4 | 3.3 | 3.3 |
| unsupported-features | 2.2 | 3.5 | 3.8 | 3.9 | 4.3 | 5.6 | 5.1 | 4.0 | 3.4 | 4.0 |
| unsupported-features:excluding-profile | 2.3 | 3.6 | 3.7 | 3.5 | 3.9 | 5.2 | 4.8 | 4.0 | 3.5 | 4.7 |

## Mean ΔL* (render − Lightroom) by distance from the centre

Fifths of the half diagonal. A fall-off toward the corners that the sliders don't explain is lens vignetting correction (Lightroom's lens profile is on by default; Lumina has no such stage).

| bucket | 0–0.2 | 0.2–0.4 | 0.4–0.6 | 0.6–0.8 | 0.8–1 |
|---|---:|---:|---:|---:|---:|
| as-shot | -0.5 | -0.6 | -0.9 | -1.1 | -0.7 |
| basic-only | -0.0 | -0.3 | -0.8 | -1.3 | -1.6 |
| unsupported-features | +0.1 | -0.0 | +0.6 | +1.8 | +2.4 |
| unsupported-features:excluding-profile | +0.2 | +0.3 | +0.9 | +2.3 | +3.3 |

| lens | frames | as-shot frames | frame median | border − centre ΔL* |
|---|---:|---:|---:|---:|
| E 28-75mm F2.8 A063 | 13 | 3 | 3.38 | -4.1 |
| FE 85mm F1.8 | 96 | 13 | 2.23 | +0.1 |

## Sliders (edited frames: basic-only + unsupported-features)

`ρ` is the rank correlation of the frame's median ΔE with the slider's magnitude; `ΔL*/unit` is the slope of the frame's mean ΔL* (render − Lightroom) on the slider's signed value (Exposure per stop, WB per mired of warming, others per slider unit): a negative slope on a brightening slider means Lumina's stage does less than Lightroom's.

| slider | frames active | ρ(|v|, ΔE) | ΔL*/unit | r | other |
|---|---:|---:|---:|---:|---|
| Exposure | 92 | 0.12 | -2.074 | -0.31 |  |
| WhiteBalance | 23 | 0.11 | -0.006 | -0.03 | Δb*/mired +0.006 (r 0.06) |
| Contrast | 88 | 0.23 | -0.037 | -0.07 |  |
| Highlights | 89 | 0.02 | -0.004 | -0.04 |  |
| Shadows | 90 | 0.17 | -0.013 | -0.11 |  |
| Whites | 86 | 0.57 | -0.066 | -0.46 |  |
| Blacks | 86 | 0.33 | +0.046 | 0.17 |  |
| Vibrance | 87 | 0.40 | -0.047 | -0.10 | ΔC*/unit -0.107 (r -0.44) |
| Saturation | 58 | 0.07 | -0.029 | -0.02 | ΔC*/unit +0.098 (r 0.14) |
| Clarity | 6 | 0.32 | +0.102 | 0.12 |  |
| Sharpness | 0 | – | – | – |  |
| PostCropVignette | 20 | 0.25 | -0.117 | -0.39 |  |

## Unsupported features (frames with the feature, their median ΔE)

- aiDenoise: 8 frames, frame median 3.37
- dehaze: 15 frames, frame median 3.40
- lensBlur: 2 frames, frame median 2.01
- profile: 6 frames, frame median 3.07
- texture: 9 frames, frame median 3.67

White balance for non-As-Shot edits: Lightroom's as shot estimated from Apple's with -5.5 mired (MAD 1.6) and tint +2.3 (MAD 1.6), from 86 As Shot exports.

## Alignment

Every render lines up with its reference within 1 px at the comparison size.

## Worst frames

- `DSC08417__edit01` (unsupported-features, texture, dehaze, aiDenoise) median 6.80, p95 14.68, ΔL* +4.9
- `DSC08417__edit02` (unsupported-features, texture, dehaze, aiDenoise) median 6.80, p95 14.68, ΔL* +4.9
- `DSC08310__edit01` (basic-only) median 4.77, p95 8.60, ΔL* -4.3
- `DSC08193__edit01` (unsupported-features, texture, dehaze, profile, aiDenoise) median 4.20, p95 11.74, ΔL* +5.4
- `DSC08276__edit01` (unsupported-features, profile) median 4.10, p95 11.88, ΔL* -3.9
- `DSC08276__edit02` (unsupported-features, profile) median 4.10, p95 11.88, ΔL* -3.9
- `DSC08280__edit01` (unsupported-features, texture, dehaze) median 4.08, p95 7.62, ΔL* -3.1
- `DSC08228__edit01` (unsupported-features, dehaze) median 3.97, p95 6.13, ΔL* +4.2

## Timing (seconds)

| import |   xmp |   as-shot | render |   renders |   decodes |   develop ms (sum) |   look+encode ms (sum) | ΔE |   pairs |   workers | report | total |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.8 | 0.1 | 0.0 | 37.5 | 109 | 0 | 15.7 | 17.4 | 42.1 | 109 | 6 | 0.0 | 80.5 |

## Per frame

In the run's evidence folder (~/LuminaEvidence/<root>/report/…), not committed.
