# Parity report — tone-eval-20261028

20261028-125315 · rules `Lumina/Sets/Look/rules-v1.json` · 30 pairs · 5 images · px 2048 · space srgb

Stage under test: **tone**

Criteria (singles): median ≤ 2.0, p95 ≤ 4.0; combos: median ≤ 3.0, p95 ≤ 5.0.

## Per slider

| slider | stage | pairs | median | p95 | mean | shadows | midtones | highlights | skin | pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Highlights | tone | 15 | 1.58 | 7.00 | 2.38 | 0.91 | 2.19 | 3.16 | 3.43 | ✗ |
| Shadows | tone | 15 | 1.63 | 5.85 | 2.17 | 1.31 | 2.34 | 2.08 | 4.17 | ✗ |

### Highlights by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -100.0 | 5 | 1.71 | 9.94 | 2.93 |
| -50.0 | 5 | 1.50 | 6.24 | 2.18 |
| 50.0 | 5 | 1.57 | 5.14 | 2.02 |

### Shadows by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 1.41 | 5.06 | 1.88 |
| 50.0 | 5 | 1.48 | 4.88 | 1.96 |
| 100.0 | 5 | 1.94 | 7.13 | 2.68 |

## Per stage

| stage | sliders | median | p95 | pass |
|---|---|---:|---:|:---:|
| tone | Highlights, Shadows | 1.61 | 6.42 | ✗ |

## Worst five pairs

- `DSC06215__Highlights__-100` median 2.51, p95 13.18
- `DSC05860__Shadows__100` median 1.09, p95 8.85
- `DSC06490__Shadows__-50` median 0.79, p95 8.23
- `DSC05917__Highlights__-100` median 1.88, p95 7.98
- `DSC06215__Highlights__-50` median 2.08, p95 7.98

## Error by reference L* decile (mean ΔE, all pairs)

| 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.50 | 3.10 | 3.07 | 4.32 | 4.94 | 5.05 | 4.29 | 3.82 | 3.50 | 3.26 |

## Residual and change

_(the loop writes one paragraph here per iteration: what the residual looks like and what changed)_
