# Grade model loop: every round

Evaluator frozen 2026-11-09 (`evaluate.py`, `criteria.json`, cache from `prepare.py`). Numbers only. ΔE2000 rows:
median over shots of each shot's median / p95. Exposure: |stops − the adaCG annotator's relative middle|, median / p90.
Evidence per round: `~/LuminaEvidence/grademodel/<date>/<candidate>.json`. Judge = a subagent that did not write
the candidate, reading both tables and `compare.py`.

## Round 0: baseline (Skim as it ships: ⇧E median ±1, no white balance, one 17³ look over all training shots)

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.532 | 1.513 | 0.655 | 1.634 |
| uday | 7.929 | 19.493 | 5.766 | 16.881 |
| sparks | 5.034 | 13.990 | 6.065 | 16.149 |
| tos | 7.943 | 13.092 | 8.135 | 14.070 |
| pst50 | 0.347 | 0.883 | 0.406 | 0.980 |
| pst50_transfer | 1.669 | 3.895 | 5.176 | 8.876 |
| look_composite | 4.584 | | 5.110 | |

Info: no change 0.734 / 0.682 stops; oracle |stops| dev/held uday 0.35/0.25, sparks 0.25/0.70, tos 0.40/0.50;
touch-up ΔE uday 6.37/5.45, sparks 3.68/2.98, tos 5.04/4.97. 16 s.
