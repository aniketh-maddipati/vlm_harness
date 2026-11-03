# Parity report — contrast-0

20261103-100535 · rules `Lumina/Sets/Look/rules-v1.json` · 20 pairs · 5 images · px 2048 · space srgb

Stage under test: **contrast**

Criteria (singles): median ≤ 2.0, p95 ≤ 4.0; combos: median ≤ 3.0, p95 ≤ 5.0.

## Per slider

| slider | stage | pairs | median | p95 | mean | shadows | midtones | highlights | skin | pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Contrast | contrast | 20 | 1.66 | 4.81 | 2.05 | 1.02 | 2.18 | 2.07 | 4.27 | ✗ |

### Contrast by position

| value | pairs | median | p95 | mean |
|---:|---:|---:|---:|---:|
| -50.0 | 5 | 2.20 | 4.97 | 2.45 |
| -25.0 | 5 | 1.63 | 4.67 | 2.02 |
| 25.0 | 5 | 1.29 | 4.50 | 1.73 |
| 50.0 | 5 | 1.62 | 5.01 | 2.00 |

## Per stage

| stage | sliders | median | p95 | pass |
|---|---|---:|---:|:---:|
| contrast | Contrast | 1.66 | 4.81 | ✗ |

## Worst five pairs

- `DSC06490__Contrast__-50` median 1.51, p95 7.68
- `DSC06490__Contrast__-25` median 1.03, p95 7.39
- `DSC06490__Contrast__25` median 0.58, p95 7.08
- `DSC06490__Contrast__50` median 0.42, p95 6.97
- `DSC06215__Contrast__50` median 1.68, p95 5.45

## Error by reference L* decile (mean ΔE, all pairs)

| 0–10 | 10–20 | 20–30 | 30–40 | 40–50 | 50–60 | 60–70 | 70–80 | 80–90 | 90–100 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.24 | 2.86 | 2.43 | 2.72 | 3.62 | 4.19 | 3.84 | 3.27 | 2.86 | 2.88 |

## Residual and change

_(the loop writes one paragraph here per iteration: what the residual looks like and what changed)_
