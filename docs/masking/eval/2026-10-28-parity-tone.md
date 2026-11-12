# Edit-look parity — tone stage baseline — 2026-10-28

`parity.py --stage tone --limit 5` against
`/Volumes/T7/Lumina/evidence-mac/parity/sweep/refs.json` with ARWs from
`…/sweep/raw`, rules `Lumina/Sets/Look/rules-v1.json`, px 2048, sRGB.

Report: `Tools/parity/report/20261028-125315-tone-eval-20261028/` (also under
`/Volumes/LuminaFactory/parity-evidence/report/…`).

| slider / stage | pairs | median ΔE2000 | p95 | pass (≤2.0 / ≤4.0) |
|---|---:|---:|---:|:---:|
| Highlights | 15 | 1.58 | 7.00 | ✗ |
| Shadows | 15 | 1.63 | 5.85 | ✗ |
| **tone** | 30 | **1.61** | **6.42** | ✗ |

Worst: `DSC06215__Highlights__-100` (median 2.51 / p95 13.18).

## Held-out (T7 evidence, not re-fit today)

From `/Volumes/T7/Lumina/evidence-mac/parity-personal/report/20261002-220945-mapper-clamp/`
(109 edits / 94 RAWs, rules-v1, 1024 px long edge):

| bucket | frames | median | p95 |
|---|---:|---:|---:|
| as-shot | 16 | 1.74 | 6.04 |
| basic-only | 71 | 2.45 | 7.86 |
| **all** | 109 | **2.37** | **7.93** |

`make parity-check` PASS earlier today (worst 0.0021). No `loop.sh` coefficient change
was adopted: stages stay `"locked": false` until a fit clears the held-out gate
(+0.05 median / +0.10 p95 on personal).
