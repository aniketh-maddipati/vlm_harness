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
