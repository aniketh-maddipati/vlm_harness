# Parity report — baseline-sweep1

20261029-225343 · rules `rules-v1.json` at 8f2b343a with `rawDevelop.lensShading` 0 (Lightroom's lens profile is off in the sweeps) · 140 pairs · 5 images · px 2048 · space srgb.
Refs: `~/LuminaEvidence/parity/sweep/refs.json` (Lightroom CC sweep 1). Full report + summary.json + heatmaps: `~/LuminaEvidence/parity/report/20261029-225343-baseline-sweep1` (T7). Copied here from the run's output.

Criteria (singles): median ≤ 2.0, p95 ≤ 4.0; combos: median ≤ 3.0, p95 ≤ 5.0.

## Per slider

| slider | stage | pairs | median | p95 | mean | shadows | midtones | highlights | skin | pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Exposure | exposure | 30 | 1.31 | 5.18 | 1.81 | 0.95 | 1.62 | 2.00 | 2.89 | ✗ |
| Contrast | contrast | 20 | 1.52 | 3.90 | 1.84 | 0.94 | 1.84 | 1.92 | 3.12 | ✓ |
| Highlights | tone | 15 | 1.50 | 5.91 | 2.17 | 0.90 | 2.41 | 3.11 | 3.55 | ✗ |
| Shadows | tone | 15 | 1.51 | 5.20 | 2.01 | 1.33 | 1.86 | 1.88 | 3.27 | ✗ |
| Whites | whitesBlacks | 20 | 1.73 | 4.59 | 2.03 | 0.92 | 2.14 | 2.53 | 3.55 | ✗ |
| Blacks | whitesBlacks | 20 | 1.43 | 5.57 | 1.97 | 1.36 | 1.70 | 2.00 | 2.57 | ✗ |
| Vibrance | colour | 10 | 1.65 | 5.55 | 2.14 | 0.89 | 2.70 | 1.86 | 2.75 | ✗ |
| Saturation | colour | 10 | 1.24 | 5.01 | 1.76 | 0.89 | 1.56 | 1.61 | 2.98 | ✗ |

## By position (median / p95)

| slider | positions |
|---|---|
| Exposure | −2: 1.05 / 4.72 · −1: 1.00 / 3.78 · −0.5: 0.99 / 3.44 · +0.5: 1.24 / 4.10 · +1: 1.61 / 4.82 · +2: 2.32 / 6.26 |
| Contrast | −50: 1.93 / 4.00 · −25: 1.52 / 3.73 · +25: 1.22 / 3.74 · +50: 1.69 / 4.09 |
| Highlights | −100: 1.73 / 9.04 · −50: 1.34 / 5.00 · +50: 1.48 / 4.56 |
| Shadows | −50: 1.15 / 3.95 · +50: 1.41 / 4.24 · +100: 1.94 / 6.76 |
| Whites | −50: 2.25 / 4.92 · −25: 1.35 / 3.96 · +25: 1.34 / 3.86 · +50: 2.21 / 4.84 |
| Blacks | −50: 1.70 / 10.91 · −25: 1.23 / 3.77 · +25: 1.11 / 3.64 · +50: 1.68 / 4.05 |
| Vibrance | −50: 1.68 / 5.95 · +50: 1.63 / 4.22 |
| Saturation | −50: 1.09 / 3.08 · +50: 1.53 / 6.27 |

## Per stage

| stage | sliders | median | p95 | pass |
|---|---|---:|---:|:---:|
| exposure | Exposure | 1.31 | 5.18 | ✗ |
| whitesBlacks | Whites, Blacks | 1.55 | 4.94 | ✗ |
| tone | Highlights, Shadows | 1.51 | 5.57 | ✗ |
| contrast | Contrast | 1.52 | 3.90 | ✓ |
| colour | Vibrance, Saturation | 1.40 | 5.35 | ✗ |

## Worst five pairs

- `DSC06707__Blacks__-50` median 6.47, p95 12.37
- `DSC06707__Exposure__-2` median 1.95, p95 11.97
- `DSC06215__Highlights__-100` median 2.87, p95 11.41
- `DSC05860__Shadows__100` median 1.11, p95 9.16
- `DSC06215__Exposure__2` median 2.32, p95 8.54

## Error by reference L* decile (mean ΔE, all pairs)

| 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.31 | 2.51 | 2.50 | 2.97 | 3.50 | 3.81 | 3.67 | 3.59 | 3.51 | 3.51 |
