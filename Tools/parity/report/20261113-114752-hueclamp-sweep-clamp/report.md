# Parity report — hueclamp-sweep-clamp

20261113-114752 · rules `/private/tmp/claude-501/-Users-aniketh-vlm-harness--claude-worktrees-highlights-chroma-9dc0cc/1f148c70-8d2b-4929-8de7-41107300643f/scratchpad/rules-clamp.json` · 140 pairs · 5 images · px 2048 · space srgb

Criteria (singles): median ≤ 2.0, p95 ≤ 4.0; combos: median ≤ 3.0, p95 ≤ 5.0.

## Per slider

| slider | stage | pairs | median | p95 | mean | shadows | midtones | highlights | skin | pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Exposure | exposure | 30 | 1.02 | 4.94 | 1.62 | 0.97 | 1.23 | 1.14 | 4.99 | ✗ |
| Contrast | contrast | 20 | 1.42 | 4.97 | 1.93 | 1.10 | 2.02 | 1.23 | 3.93 | ✗ |
| Highlights | tone | 15 | 1.27 | 7.33 | 2.27 | 0.88 | 2.65 | 2.48 | 3.52 | ✗ |
| Shadows | tone | 15 | 1.41 | 6.08 | 2.09 | 1.52 | 2.17 | 0.94 | 4.09 | ✗ |
| Whites | whitesBlacks | 20 | 1.50 | 4.92 | 1.95 | 0.90 | 2.17 | 2.19 | 3.83 | ✗ |
| Blacks | whitesBlacks | 20 | 1.27 | 7.12 | 2.05 | 1.14 | 1.77 | 1.00 | 5.18 | ✗ |
| Vibrance | colour | 10 | 1.53 | 6.54 | 2.39 | 0.97 | 3.44 | 1.63 | 5.17 | ✗ |
| Saturation | colour | 10 | 1.45 | 5.06 | 1.94 | 0.95 | 1.77 | 2.14 | 4.63 | ✗ |

### Exposure by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -2.0 | 5 | 0.88 | 2.94 | 1.22 |
| -1.0 | 5 | 0.92 | 3.97 | 1.34 |
| -0.5 | 5 | 0.91 | 4.20 | 1.40 |
| 0.5 | 5 | 1.01 | 5.08 | 1.68 |
| 1.0 | 5 | 1.06 | 5.83 | 1.83 |
| 2.0 | 5 | 1.34 | 7.04 | 2.28 |

### Contrast by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.92 | 5.05 | 2.26 |
| -25.0 | 5 | 1.29 | 4.67 | 1.80 |
| 25.0 | 5 | 1.04 | 4.66 | 1.64 |
| 50.0 | 5 | 1.49 | 5.36 | 2.00 |

### Highlights by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -100.0 | 5 | 1.36 | 11.05 | 2.89 |
| -50.0 | 5 | 1.19 | 6.78 | 2.06 |
| 50.0 | 5 | 1.30 | 4.90 | 1.85 |

### Shadows by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.15 | 5.11 | 1.73 |
| 50.0 | 5 | 1.30 | 5.01 | 1.85 |
| 100.0 | 5 | 1.85 | 7.50 | 2.70 |

### Whites by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.48 | 5.14 | 1.83 |
| -25.0 | 5 | 0.89 | 4.16 | 1.44 |
| 25.0 | 5 | 1.63 | 4.94 | 2.03 |
| 50.0 | 5 | 2.31 | 5.10 | 2.48 |

### Blacks by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.39 | 10.59 | 2.66 |
| -25.0 | 5 | 1.35 | 5.51 | 1.92 |
| 25.0 | 5 | 1.26 | 5.11 | 1.82 |
| 50.0 | 5 | 1.17 | 5.15 | 1.79 |

### Vibrance by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.88 | 6.79 | 2.73 |
| 50.0 | 5 | 1.34 | 5.38 | 2.04 |

### Saturation by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.22 | 4.16 | 1.62 |
| 50.0 | 5 | 1.76 | 5.60 | 2.26 |

## Per stage

| stage | sliders | median | p95 | pass |
|---|---|---:|---:|:---:|
| exposure | Exposure | 1.02 | 4.94 | ✗ |
| whitesBlacks | Whites, Blacks | 1.38 | 5.74 | ✗ |
| tone | Highlights, Shadows | 1.36 | 6.73 | ✗ |
| contrast | Contrast | 1.42 | 4.97 | ✗ |
| colour | Vibrance, Saturation | 1.48 | 6.12 | ✗ |

## Worst five pairs

- `DSC06215__Highlights__-100` median 2.26, p95 14.52
- `DSC06707__Blacks__-50` median 5.97, p95 12.02
- `DSC06490__Exposure__2` median 2.57, p95 11.96
- `DSC06490__Highlights__-100` median 0.65, p95 9.80
- `DSC06490__Blacks__-50` median 0.00, p95 9.72

## Error by reference L* decile (mean ΔE, all pairs)

| 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.42 | 3.02 | 2.87 | 3.27 | 3.79 | 4.00 | 3.68 | 3.08 | 2.78 | 3.15 |

## Residual and change

_(the loop writes one paragraph here per iteration: what the residual looks like and what changed)_
