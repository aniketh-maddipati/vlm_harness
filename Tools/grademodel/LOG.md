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

## Round 1: ⇧E on log-mean luminance (`r1_logmean`): REJECT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.513 | 1.493 | 0.629 | 1.622 |
| uday | 7.525 | 17.267 | **6.148** (+0.382) | 16.147 |
| sparks | 6.290 | 16.217 | **6.466** (+0.401) | 12.095 |
| tos | 6.086 | 12.441 | 7.629 | 12.606 |
| pst50 / transfer | unchanged | | | |
| look_composite | 4.383 | | 5.165 | |

Dev improves (exposure −0.019, look −0.201); held Uday and Sparks medians fail (+0.38, +0.40). Judge: log-mean
leans on deep shadows and darkened two held shots further (Uday 7: −0.73 → −0.76 stops, oracle +0.2 → +0.4;
Sparks 2024-2455: −0.33 → −0.44, oracle +0.3 → +0.8). Held p95s improve (Sparks −4.06, ToS −1.46). Next: trimmed
log-mean.

## Round 2: look fitted with each training shot's own gains taken out (`r2_jointgains`): REJECT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.532 | 1.513 | 0.655 | 1.634 |
| uday | 8.340 | 20.083 | **8.239** (+2.473) | **18.689** (+1.808) |
| sparks | 4.729 | 15.052 | **7.549** (+1.484) | 15.174 |
| tos | 8.630 | 12.599 | **8.297** (+0.162) | 12.584 |
| pst50 / transfer | unchanged | | | |
| look_composite | 4.743 | | 5.933 | |

Dev look worse (+0.159). Taking the trims out of the training shots makes the look expect "ideally balanced"
input, which the rule's gains on a new shot don't deliver; the baseline look had learned the rule's average error.

## Round 3: ⇧E on the trimmed log-mean, p10–p90 (`r3_trimmed_logmean`): REJECT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.521 | 1.513 | 0.635 | 1.665 |
| uday | 7.568 | 18.280 | **5.937** (+0.171) | 15.320 |
| sparks | 6.169 | 20.111 | **7.044** (+0.979) | 14.041 |
| tos | 7.149 | 12.331 | 8.118 | 13.328 |
| pst50 / transfer | unchanged | | | |
| look_composite | 4.580 | | 5.336 | |

Dev improves (exposure −0.011; look −0.004, under the 0.01 bar); held Uday and Sparks medians fail. Run as queued from the round-1
judge before its revised advice (a half step between median and log-mean) arrived; counted, not re-run.

**Stop: 3 rejected in a row.** No change adopted; the incumbent is still the baseline.

### Per shot: held ΔE median / ⇧E stops (baseline · r1 · r3)

| shot | baseline | r1 log-mean | r3 trimmed |
|---|---|---|---|
| uday 1 | 7.32 / +0.15 | 7.23 / +0.28 | 7.36 / +0.35 |
| uday 4 | 6.29 / +0.19 | 6.01 / +0.36 | 6.01 / +0.39 |
| uday 5 | 4.76 / +0.00 | 3.91 / +0.00 | 3.82 / +0.00 |
| uday 7 | 5.25 / −0.73 | 6.29 / −0.76 | 5.86 / −0.70 |
| sparks 2024-2455 | 5.94 / −0.33 | 7.45 / −0.44 | 7.67 / −0.53 |
| sparks 5363-5763 | 6.19 / −0.08 | 5.48 / +0.00 | 6.42 / +0.02 |
| sparks 5764-6024 | 15.78 / −1.00 | 11.06 / −0.48 | 16.74 / −0.97 |
| sparks 6026-6502 | 5.11 / +0.29 | 5.38 / +0.37 | 6.17 / +0.39 |

Uday 7's own exposure moved 0.03 stops between baseline and r1, its ΔE 1.04: the look, re-fitted on re-balanced
training shots, moves a held shot about as much as its own balance does.

Judge, round 3: when only the balance statistic changes, a held shot's median ΔE moves by typically 0.37 (up to
1.39) on Uday, 1.37 (4.93) on Sparks, 0.63 (3.66) on ToS, even where the shot's own stops do not change (Uday 5:
0.00 stops in all three runs, ΔE 4.76 / 3.91 / 3.82; ToS 07_3b clamped at −1 in all three, 9.66 / 9.21 / 8.95).
A +0.05 limit on a median of 4 shots is far inside that. Paired per-shot change over all 21 held look shots
(Uday + Sparks + ToS), candidate − baseline: r1 −0.46 (6 shots worse), r2 +0.82 (13 worse), r3 −0.27 (10 worse).

## Summary (baseline vs best per split)

No candidate adopted, so "best" is the baseline on every gated row. The best number any candidate reached, for
the record (not adoptable: each came with a failing held row):

| split | baseline | best seen (candidate) |
|---|---|---|
| exposure_adacg dev / held (stops) | 0.532 / 0.655 | 0.513 / 0.629 (r1) |
| uday dev / held ΔE median | 7.929 / 5.766 | 7.525 (r1) / 5.766 (baseline) |
| sparks dev / held | 5.034 / 6.065 | 4.729 (r2) / 6.065 (baseline) |
| tos dev / held | 7.943 / 8.135 | 6.086 / 7.629 (r1) |
| held p95 uday / sparks / tos | 16.881 / 16.149 / 14.070 | 15.320 (r3) / 12.095 (r1) / 12.584 (r2) |
| pst50 / pst50_transfer held | 0.406 / 5.176 | unchanged (no round touched the one-frame look) |

For the owner (criteria are yours; nothing changed here):
1. The held ΔE rows can't resolve a balance change: 4 shots per set, and re-fitting the look on re-balanced
   training shots moves each held shot ~0.4–1.4 ΔE by itself. The judge's proposal: replace the Uday / Sparks / ToS
   held-median rows with one pooled row, the median over the 21 held shots of each shot's change (candidate −
   incumbent), at most +0.05; keep the per-set p95 rows. Under it r1 and r3 pass that row, r2 fails.
2. Log-mean ⇧E (r1) is the one to re-test under any revised rule: −0.019 / −0.026 stops on adaCG dev / held, ToS
   −0.51 held, every held p95 down; its failures are two shots (Uday 7, Sparks 2024-2455).
3. Not run (the stop rule came first): white balance (shoot-median chroma), highlight cap, and look regularisation.

---

# Criteria amended 2026-11-09 (owner approved: "Yes, all three")

The Uday / Sparks / ToS held-median rows are replaced by one pooled row: over their 21 held shots, each shot's
change in median ΔE (candidate − incumbent); the median of those changes must be ≤ +0.05. Their per-set held p95
rows stay (≤ +0.10). Splits, tolerances, the dev rule and the exposure / PST50 rows are unchanged. The loop is
rerun from the baseline under this gate (same limits: 8 rounds, or 3 rejected in a row); rounds are numbered
anew (G1, G2, …).

Evidence for this loop: `~/LuminaEvidence/grademodel/pooled/`. Incumbent at start: baseline (Round 0 numbers, unchanged).

## G1: ⇧E on log-mean luminance (`r1_logmean`, re-scored): ADOPT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.513 | 1.493 | 0.629 | 1.622 |
| uday | 7.525 | 17.267 | 6.148 | 16.147 |
| sparks | 6.290 | 16.217 | 6.466 | 12.095 |
| tos | 6.086 | 12.441 | 7.629 | 12.606 |
| pst50 / transfer | unchanged | | | |
| look_composite | 4.383 | | 5.165 | |

Dev exposure −0.019, look −0.201. Held: exposure −0.026; pooled per-shot Δ −0.456 (15 of 21 shots better; worst
ToS 03_2d +2.49, ToS 05_4h +1.79, Sparks 2024-2455 +1.51, Uday 7 +1.04; best Sparks 5764-6024 −4.72); p95 Uday
−0.73, Sparks −4.06, ToS −1.46.

## G2: white balance half way to the shoot's median chroma, ±0.3 (`g2_wb_shootchroma`): REJECT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.513 | 1.493 | 0.629 | 1.622 |
| uday | 7.340 | 17.129 | 6.338 | 15.969 |
| sparks | 7.400 | 16.273 | 6.333 | 11.678 |
| tos | 6.648 | 11.717 | 6.913 | **14.062** (+1.456) |
| look_composite | 4.681 | | 5.033 | |

Dev look +0.298 (no dev gain); pooled Δ **+0.281** (11 of 21 worse); ToS p95 +1.46. Judge: pulling each clip
toward the shoot's median colour erases colour that differs on purpose between scenes (ToS 03_2d +3.10, 04_4c
p95 +3.06).

## G3: log-mean ⇧E at strength 0.75, clamp ±1.2 (`g3_logmean_k075`; k and clamp fitted on the 25 dev shots of Uday / Sparks / ToS): REJECT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.522 | 1.390 | 0.596 | 1.578 |
| uday | 7.624 | 18.891 | 5.761 | **16.302** (+0.155) |
| sparks | 7.581 | 16.427 | 6.069 | 11.021 |
| tos | 6.248 | 12.178 | 6.889 | 11.612 |
| look_composite | 4.694 | | 4.860 | |

Neither dev score improves (exposure +0.009, look +0.310); Uday p95 +0.16. Held otherwise better: exposure
−0.033, pooled Δ −0.323, Sparks p95 −1.07, ToS p95 −0.99, adaCG p90 1.62 → 1.58.

## G4: a smoother shared look across shots, LUT smoothness 0.5 → 2.0 for multi-shot fits (`g4_smooth_look`): REJECT

| metric | dev median | dev p95/p90 | held median | held p95/p90 |
|---|---|---|---|---|
| exposure_adacg (stops) | 0.513 | 1.493 | 0.629 | 1.622 |
| uday | 7.523 | 17.218 | 7.003 | **16.352** (+0.205) |
| sparks | 7.218 | 16.428 | 6.200 | **12.332** (+0.237) |
| tos | 7.358 | 11.634 | 8.251 | **13.243** (+0.637) |
| pst50 / transfer | unchanged | | | |
| look_composite | 4.823 | | 5.407 | |

Dev look +0.440; pooled Δ **+0.197**; every p95 row fails. Chosen by the judge over equal shot weighting and a 9³
LUT, on the reading that look re-fit noise sets the score; a smoother look instead lost detail the grade has.

**Stop: 3 rejected in a row (G2, G3, G4).** Adopted: G1 only.

## Summary under the pooled gate (baseline → adopted G1)

| row | dev baseline → G1 | held baseline → G1 |
|---|---|---|
| exposure vs adaCG, median / p90 (stops) | 0.532 / 1.513 → 0.513 / 1.493 | 0.655 / 1.634 → 0.629 / 1.622 |
| Uday ΔE median / p95 | 7.93 / 19.49 → 7.53 / 17.27 | 5.77 / 16.88 → 6.15 / 16.15 |
| Sparks | 5.03 / 13.99 → 6.29 / 16.22 | 6.07 / 16.15 → 6.47 / 12.10 |
| ToS | 7.94 / 13.09 → 6.09 / 12.44 | 8.14 / 14.07 → 7.63 / 12.61 |
| PST50 / PST50 transfer | 0.35 / 1.67 (unchanged) | 0.41 / 5.18 (unchanged) |
| look composite | 4.584 → 4.383 | 5.110 → 5.165 |
| pooled per-shot Δ (21 held shots) | | −0.456 (15 better, 6 worse) |

Not adopted but best held seen: G3 (strength 0.75, ±1.2) held exposure 0.596, pooled −0.32 vs G1, ToS held p95
11.61, Sparks 11.02, but its dev scores rose, so the rule rejects it.

Judge on G4: smoothing hurt the shots that need a strong look (Sparks 5764-6024 +2.00, Uday 4 +1.32, ToS 05_4h
+1.19; ToS 04_4c p95 +4.15): the look's flexibility helps; re-fit noise was not the limit.

## Into the Skim page? (the owner decides; nothing drafted)

G1 is one line in the page's `sceneSl` (`Lumina Skim v3.dc.html`): return exp(mean(log(Y + 1e-4))) over the same
sampled pixels instead of the upper median; `evAutoMap`, the shoot median and the ±1 clamp stay. The page's
luminance is on the eval's scale (scene-linear reflectance after S-Log3, 0..1 after sRGB's curve), so the 1e-4
floor carries over. Judge's risks from the per-shot losses:
- the log-mean sinks on large dark areas, so low-key shots get lifted too far (Sparks 30-511: +0.05 → +1.0 stop
  where the grader wanted −0.8);
- dark mid-tones against bright areas can move the wrong way (Sparks 11198-11570: +0.5 → −0.03, wanted +0.7;
  ToS 05_4h to −1.0, wanted +0.3).
