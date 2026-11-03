# Parity baseline, 2026-10-29 → 11-03 (prompt 00)

origin/main at f3b95414 + the docs commit; `rules-v1.json` as on main, no stage locked. Numbers only; renders,
heatmaps and per-frame tables stay in `~/LuminaEvidence` (internal copies of the sweeps and the Death Valley set:
`~/LuminaEvidence/local/`, made after the T7 dropped twice mid-run). ΔE2000, median / p95. Sweeps and Death
Valley are scored with `rawDevelop.lensShading` 0 (Lightroom's lens profile is off there); held-out with the
shipped rules. Profile: the look string's default, `prof:adobe` (Adobe Color), which is what Lightroom's
exports use; `prof:camera` has no Lightroom reference and isn't scored.

Criteria (`criteria.json`): singles ≤ 2.0 / 4.0, combos ≤ 3.0 / 5.0. Held-out tolerance: ≤ +0.10 / +0.25 above
2.32 / 7.82 in total, i.e. ≤ 2.42 / 8.07.

## Per stage, against Lightroom

| stage | slider | sweep (5 photos) | worst position | Death Valley unseen (76 photos) | pass |
|---|---|---|---|---|:---:|
| exposure | Exposure | 1.31 / 5.18 | +2: 2.32 / 6.26 | – | ✗ |
| whiteBalance | Temperature | 2.02 / 5.49 | 3200 K: 2.28 / 7.04 | – | ✗ |
| whiteBalance | Tint | 1.35 / 4.04 | −60: 1.66 / 4.54 | – | ✗ |
| whitesBlacks | Whites | 1.73 / 4.59 | −50: 2.25 / 4.92 | – | ✗ |
| whitesBlacks | Blacks | 1.43 / 5.57 | −50: 1.70 / 10.91 | – | ✗ |
| tone | Highlights | 1.50 / 5.91 | −100: 1.73 / 9.04 | −100: 1.96 / 4.23 · −50: 1.30 / 3.01 · +50: 1.39 / 3.22 | ✗ |
| tone | Shadows | 1.51 / 5.20 | +100: 1.94 / 6.76 | +100: 2.06 / 5.90 · +50: 1.41 / 3.57 · −50: 1.19 / 3.26 | ✗ |
| contrast | Contrast | 1.52 / 3.90 | +50: 1.69 / 4.09 | – | ✓ (5 photos) |
| colour | Vibrance | 1.65 / 5.55 | −50: 1.68 / 5.95 | – | ✗ |
| colour | Saturation | 1.24 / 5.01 | +50: 1.53 / 6.27 | – | ✗ |
| combos | 3 sliders | 1.55 / 4.52 (50) | | | ✓ |
| base | – | 1.03 / 3.67 | | 1.05 / 3.08 (153 photos, Death Valley base) | |
| curve, mixer, clarity, sharpen, vignette | – | no Lightroom sweep yet (sweeps 4–12, PR #327) | | | – |

Death Valley columns are the median over photos of each frame's median / p95 (not pooled). Pooled over all six
tone positions: unseen half 1.53 / 5.52 (456 frames, without the 3 contaminated photos; 1.54 / 5.53 with them).

Held-out (mehendi, 109 edits): **2.38 / 8.10**: as-shot 1.73 / 6.02, basic-only 2.42 / 7.83, unsupported
features 2.97 / 9.72. The p95 is past the 8.07 cap on main already (7.93 on 2026-10-02; 8.10 by the 2026-10-28
sky run), so no stage passes "parity + held-out tolerance" and **nothing is locked**. Contrast also passes on
5 photos only (the criteria are written for 50), and `loop.sh` itself judges it with the shipped rules (lens
shading on), where it fails: 1.66 / 4.81 (`loop-contrast-dry/`).

## Files

- `sweep1/`, `sweep2/`: `parity.py` on the Lightroom CC sweeps 1 and 2 (sweep 3's white balance exports are in
  sweep 2's refs). `sweep1/report.md` was first rebuilt from the run's output when the T7 dropped; `summary.json`
  is from the rerun on the internal copy (same numbers).
- `held-out/`, `dv-tone-all/`, `dv-unseen-all/`, `dv-*-clean/`: `parity_personal.py`. `clean` leaves out DSC06742
  (masks) and DSC06841 / DSC06842 (crop), which Lightroom CC presets kept (`--exclude`).
- `loop-contrast-dry/`: `LOOP_DRY=1 loop.sh contrast`.
- `better/`: `better.py` on Lightroom's sweep 1 exports and on Lumina's sweep 1 renders.
- `skim/`: `skim_parity.py`, Skim's look on the same sweeps.
- The golden set (`golden.json`) has no photos, so there is no golden-set run.
