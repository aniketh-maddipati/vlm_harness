# Look eval: Skim's look sliders against graded frames

How much of a professional grade Skim's own Color card (Light, Color, Mix, Grade) can reproduce, and whether a
look fitted on one graded frame carries to another shot: the question behind a "match this look" feature.
Measures only; nothing here ships.

| File | What it does |
|---|---|
| `lookmath.py` | The page's LOOK block (`lkPx`, `lkSl3`, `lkIn`, `lkPreview`, `lkClean`) in numpy, vectorised over pixels |
| `look_ref.mjs` | The page's own LOOK block, read out of `Lumina Skim v3.dc.html` and run in Node, for the parity test |
| `fit.py` | Bounded least squares on CIELAB residuals: every slider held to its real range (`lkRange`), grade wheels as a point in the unit square, the result rounded the way the page stores it and scored with the page's maths (ΔE2000) |
| `colour.py` | sRGB → CIELAB, ΔE2000, the 32 px checkerboard split, a smoothed 33³ LUT (for scale and for the clip frames' Rec.709 conversion); from the PST50 measurement scripts so numbers line up |
| `pst50.py` | The PST50 run: `pairs` (every pair, global / + Mix / + Grade / every slider, per-group ablations), `transfer` (style-source clips, look clusters), `cross` (each look on every other pair) |
| `report.py` | Numbers-only report → `report/pst50.md` + `report/pst50.json` |
| `test_lookeval.py` | Port ≡ page (Node, 1e-9 on random looks, all three input modes), the page's tables and ranges, ΔE2000 on Sharma's pairs, a known look recovered from a synthetic frame |

```bash
make lookeval-test                                  # synthetic only; PY=~/LuminaEvidence/venv-parity/bin/python on the Mac
PY=~/LuminaEvidence/venv-parity/bin/python
python3 Scripts/test_guard.py run --name lookeval-pairs --limit 3600 -- /bin/sh -c \
  "for k in 0 1 2 3 4 5 6 7 8 9 10 11; do OMP_NUM_THREADS=1 $PY -I -W ignore Tools/lookeval/pst50.py pairs \$k 12 & done; wait"
$PY -I -W ignore Tools/lookeval/pst50.py transfer   # needs ffmpeg and the clips in pst50/video
$PY -I -W ignore Tools/lookeval/pst50.py cross
$PY -I -W ignore Tools/lookeval/report.py
```

Data: `/Volumes/T7/Lumina/datasets/pst50` (`LUMINA_PST50`), read only. Evidence (JSON per pair, the clip frames):
`~/LuminaEvidence/lookeval` (`LUMINA_LOOKEVAL`). PST50's footage rights are unclear: never commit a frame; the
report is numbers only.

## Method

- **Input the page would see.** PST50's log frames use an unnamed curve. **A**: `content_709` in mode 0 (as shot),
  i.e. the clip reaches Skim already in Rec.709 through PST50's own technical conversion (itself a global function
  of the log, ΔE 0.49 to a LUT). **B**: `content_log` in mode 1, Skim's S-Log3 → Rec.709 table, as if the clip
  were S-Log3; Exposure is then the page's code shift. B shows what a wrong log assumption costs.
- **Fit.** 6 000 pixels from half the 32 px blocks; residuals in CIELAB; `scipy.optimize.least_squares` (trf,
  bounds). Global (Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temp, Tint, Vibrance, Saturation) from
  three Exposure starts; + Mix, + Grade and every slider start from the global fit.
- **Score.** ΔE2000 on the other blocks, at 960×540, with the stored (rounded) values through the page's maths.
- **Which sliders.** Per group: drop (refit without it), zero (fitted look with it at rest) and only (it alone).
- **Transfer.** PST50 has one graded frame per shot and no graded video, so there is no "another frame of the
  same clip" with a ground truth. Proxies: the three clips whose frame graded is the style shot `tarN` (same look,
  another shot), and the PST50 look clusters (pairs whose LUTs cross under ΔE 3).

## Results (PST50, 2026-11-08; full tables in `report/pst50.md`)

ΔE2000 median / p95, median over the 50 pairs; one graded frame per pair, scored on blocks the fit never saw.

| | ΔE median | p95 | pairs < 1 / < 2 |
|---|---|---|---|
| technical Rec.709 | 9.20 | 13.08 | 0 / 0 |
| Light + Color sliders (10) | 2.01 | 5.05 | 9 / 25 |
| + Grade (24) | 0.75 | 1.90 | 31 / 46 |
| every slider (48: + Mix) | **0.60** | **1.45** | 46 / 50 |
| every slider, log read as S-Log3 | 0.70 | 1.80 | 43 / 50 |
| 33³ LUT (floor) | 0.42 | 1.10 | 50 / 50 |

- **The sliders reproduce nearly all of a professional grade.** On one frame they come within 0.2 ΔE of a free
  33³ LUT (0.60 vs 0.42), about the same as curves + 3×3 (0.55). The fit has no over-fitting gap between the fit
  and held-out blocks (0.00).
- **The Grade wheels carry it.** On their own they get 1.6; without them the rest refit gives +0.48. Light + Color
  alone stop at 2.0 / 5.0, with Whites (46 % of pairs), Highlights (34 %), Temp (34 %) and Shadows (32 %) pinned at
  their limits: a pro look needs a split tint that global sliders can't make. Mix (24 sliders) adds only 0.15
  after Grade. Exposure, white balance and saturation are interchangeable with the wheels (drop ≈ 0).
- **A wrong log assumption costs little.** Reading PST50's unnamed log as S-Log3 costs +0.1 (0.70) once every
  slider is fitted; the sliders absorb the curve mismatch.
- **Transfer to another shot of the same look matches a LUT, not the in-frame number.** Clip 29: 0.83 content →
  clip (LUT 0.81), 0.77 clip → content (LUT 0.66). Clip 37: 2.29 (LUT 2.26), 1.70 (LUT 2.56). Look clusters: 1.2–6.4,
  where the LUT gets 1.5–4.2. Across shots the error is the look itself not being one global function, not the
  sliders running out. Clip 46 is Rec.709, not log, so it gives no valid test in mode A.
- **A look from one frame doesn't carry to unrelated looks.** Applied to the other 49 pairs, a look scores
  10.9 (global) / 11.6 (every slider), the same as the LUT's 11.6 and worse than plain 709 (9.2).

Not measured: PST50 has no graded video, so frame-to-frame transfer *within a clip* has no ground truth here;
the 2 + 1 clips and 4 clusters above are the only cross-shot evidence (n is small). Fitting time in numpy is
about 1 s for Light + Color and about 50 s for every slider on 6 000 pixels; an in-page fitter would need its own budget.
