# Blacks: LightCraft's form, 2026-11-11

Blacks moved from Lumina's one-coefficient perceptual lift (`blacksPerUnit` / `blacksPower`) to LightCraft's Process V4
Blacks (MIT; form and fitted numbers from storytold/lightcraft `c5d60d2f`, `tools/light_v3_fits/blacks.json`, notice in
`Lumina/Resources/THIRD-PARTY-NOTICES.txt`). Nothing refitted: LightCraft fitted it on 19 photos of its own, so every
set below is unseen by the fit. Whites unchanged. Numbers only; renders stay in `~/LuminaEvidence/local/parity/blacks-ab`.
ΔE2000 median / p95, main = `b606e3ab`, same machine, same data.

**Why this form:** RapidRAW `c8216a45` and LightCraft `c5d60d2f` were scored with the same sweep scorer
(`rapidraw_parity.py`; the LightCraft variant swaps the renderer). Matched to Lightroom's base, LightCraft's Blacks
(1.35 / 4.61) was the only slider of either closer to Lightroom than Lumina's (1.43 / 5.57). On Lightroom's own base
export (shape only, no base difference): Lumina's form 1.02 / 3.98, LightCraft's 0.81 / 3.62.

| set | main | LightCraft Blacks |
|---|---:|---:|
| Sweep 1 Blacks, 20 pairs (lens shading 0) | 1.43 / 5.57 | **1.17 / 5.29** |
| · −50 | 1.70 / 10.91 | 1.33 / 9.38 |
| · −25 | 1.23 / 3.77 | 1.25 / 3.90 |
| · +25 | 1.11 / 3.64 | 1.12 / 3.67 |
| · +50 | 1.68 / 4.05 | 1.12 / 3.87 |
| Sweep 2 combos, 50 (15 with Blacks) | 1.55 / 4.52 | 1.58 / 4.55 |
| Held-out mehendi, 109 edits (shipped rules, forced renders; main twice, identical) | 2.35 / 8.00 | **2.34 / 7.98** |
| · basic-only, 76 | 2.41 / 7.71 | 2.39 / 7.69 (skin 3.01 → 2.83, shadows 1.95 → 2.08) |

Death Valley sets have no Blacks positions: unchanged by construction. `make parity-check`: Metal ≡ Swift ≡ numpy
(worst 0.0038 on the default ramp, 0.0000 at bl −100 / +50 / +100 with wh +30 / −50 with con +20).
LookPipelineTests / LookMathTests / LookStringTests / LookCanvasTests 98 / 0; parity tool tests 128 OK.

Not measured: the Mac canvas latency with the new kernel (`probe.sh edit` / `edit-cold`, screen-owning).
