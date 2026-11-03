# Skim's look vs Lightroom — sweeps 1–2

2026-11-03 10:18 · Skim `LOOK-BEGIN` block (design/handoff/lumina-skim/Lumina Skim v3.dc.html) on Lightroom's base export · compare 1024 px · ΔE2000 after a 3 × 3 median · criteria median ≤ 2.0, p95 ≤ 4.0 (combos ≤ 3.0 / 5.0).

Temperature / Tint: scored at the best-matching Skim value per photo and position (see below), the most Skim's shape can do.

| slider | pairs | median | p95 | mean | pass |
|---|---:|---:|---:|---:|:---:|
| Blacks | 20 | 1.49 | 5.08 | 2.06 | ✗ |
| Contrast | 20 | 1.24 | 3.57 | 1.49 | ✓ |
| Exposure | 30 | 3.28 | 12.25 | 4.33 | ✗ |
| Highlights | 15 | 1.50 | 8.54 | 2.58 | ✗ |
| Saturation | 10 | 1.17 | 4.13 | 1.60 | ✗ |
| Shadows | 15 | 1.66 | 7.67 | 2.47 | ✗ |
| Temperature | 20 | 3.67 | 15.75 | 5.07 | ✗ |
| Tint | 20 | 2.16 | 8.78 | 3.29 | ✗ |
| Vibrance | 10 | 1.39 | 4.91 | 1.85 | ✗ |
| Whites | 20 | 1.16 | 5.32 | 1.50 | ✗ |
| combo | 50 | 2.10 | 6.65 | 2.58 | ✗ |

## By position (median / p95)

| slider | positions |
|---|---|
| Blacks | -50: 3.12 / 13.00 · -25: 1.30 / 3.58 · 25: 0.87 / 1.96 · 50: 2.27 / 3.95 |
| Contrast | -50: 1.71 / 3.87 · -25: 1.05 / 2.34 · 25: 1.03 / 2.40 · 50: 1.54 / 4.17 |
| Exposure | -2: 6.40 / 10.94 · -1: 4.26 / 9.48 · -0.5: 2.36 / 6.12 · 0.5: 2.51 / 4.55 · 1: 3.80 / 7.60 · 2: 7.29 / 16.75 |
| Highlights | -100: 2.14 / 12.99 · -50: 1.33 / 6.90 · 50: 1.36 / 6.74 |
| Saturation | -50: 0.98 / 3.08 · 50: 1.60 / 4.83 |
| Shadows | -50: 1.25 / 4.48 · 50: 1.45 / 4.58 · 100: 2.98 / 9.57 |
| Temperature | 3200: 9.40 / 18.84 · 4000: 3.46 / 6.29 · 6500: 1.89 / 6.10 · 10000: 5.53 / 10.24 |
| Tint | -60: 4.19 / 7.20 · -20: 1.34 / 4.67 · 20: 1.58 / 6.09 · 60: 5.61 / 9.83 |
| Vibrance | -50: 1.60 / 5.41 · 50: 1.26 / 4.51 |
| Whites | -50: 1.52 / 3.21 · -25: 1.12 / 2.27 · 25: 0.70 / 2.37 · 50: 1.61 / 7.08 |

## White balance: best Skim value per position

| slider | Lightroom | Lightroom move (mired / tint) | Skim value (median over photos) |
|---|---:|---:|---:|
| Temperature | 3200 | -116 | -100 |
| Temperature | 4000 | -54 | -100 |
| Temperature | 6500 | +42 | +100 |
| Temperature | 10000 | +96 | +100 |
| Tint | -60 | -56 | -100 |
| Tint | -20 | -16 | -40 |
| Tint | 20 | +24 | +70 |
| Tint | 60 | +64 | +100 |

