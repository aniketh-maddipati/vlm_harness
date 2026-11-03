# Parity report — baseline-sweep2

20261030-141446 · rules `rules-v1.json` at 8f2b343a with `rawDevelop.lensShading` 0 (Lightroom's lens profile is off in the sweeps) · 95 pairs · 5 images · px 2048 · space srgb

Criteria (singles): median ≤ 2.0, p95 ≤ 4.0; combos: median ≤ 3.0, p95 ≤ 5.0.

## Per slider

| slider | stage | pairs | median | p95 | mean | shadows | midtones | highlights | skin | pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Temperature | whiteBalance | 20 | 2.02 | 5.49 | 2.42 | 1.43 | 2.46 | 2.46 | 4.25 | ✗ |
| Tint | whiteBalance | 20 | 1.35 | 4.04 | 1.79 | 1.04 | 1.82 | 2.13 | 3.24 | ✗ |
| base |  | 5 | 1.03 | 3.67 | 1.45 | 0.89 | 1.21 | 1.88 | 2.51 |  |
| combo |  | 50 | 1.55 | 4.52 | 1.93 | 0.94 | 2.14 | 2.36 | 3.29 | ✓ |

### Temperature by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| 3200.0 | 5 | 2.28 | 7.04 | 2.91 |
| 4000.0 | 5 | 1.69 | 4.20 | 2.06 |
| 6500.0 | 5 | 1.56 | 4.43 | 1.98 |
| 10000.0 | 5 | 2.45 | 5.31 | 2.71 |

### Tint by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -60.0 | 5 | 1.66 | 4.54 | 2.09 |
| -20.0 | 5 | 1.14 | 3.96 | 1.58 |
| 20.0 | 5 | 1.17 | 3.57 | 1.52 |
| 60.0 | 5 | 1.60 | 3.94 | 1.99 |

## Per stage

| stage | sliders | median | p95 | pass |
|---|---|---:|---:|:---:|
| whiteBalance | Temperature, Tint | 1.64 | 4.85 | ✗ |

## Worst five pairs

- `DSC06490__Temperature__3200` median 1.85, p95 9.47
- `DSC05917__Temperature__3200` median 2.90, p95 7.66
- `DSC06490__Temperature__10000` median 1.56, p95 6.54
- `DSC06215__Temperature__10000` median 2.34, p95 6.26
- `DSC05917__combo02` median 1.78, p95 6.19

## Error by reference L* decile (mean ΔE, all pairs)

| 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.14 | 2.50 | 2.54 | 2.80 | 3.38 | 3.85 | 3.64 | 3.57 | 3.42 | 3.47 |

## Residual and change

_(the loop writes one paragraph here per iteration: what the residual looks like and what changed)_
