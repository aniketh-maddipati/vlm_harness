# grademodel: Skim's grade model, one frozen evaluator and an evaluator-optimizer loop

Skim's bet for video creators: learn a creator's look once, then balance each clip (exposure, then white) so
every clip of a shoot lands on that look. This folder scores candidate grade models on fixed splits and logs a
loop that changes one thing per round. Measures only: nothing here ships; a change moves into the Skim page only
when the owner says so.

| File | What it does |
|---|---|
| `criteria.json` | Splits (seeded dev / held halves), the adopt rule, what may be fitted on what. **Owner only.** Amended 2026-11-09 by the owner: the held look rows of Uday / Sparks / ToS are one pooled per-shot row (`amended` in the file) |
| `prepare.py` | Builds the fixed pixel samples once → `~/LuminaEvidence/grademodel/cache/` (never committed) |
| `evaluate.py` | The evaluator: one candidate → one table + `~/LuminaEvidence/grademodel/<date>/<candidate>.json` |
| `compare.py` | The adopt rule written out: incumbent vs candidate, every delta, a verdict |
| `gm.py` | S-Log3, CIELAB / ΔE2000, the smoothed 17³ LUT |
| `candidates/` | One file per candidate (`balance`, `fit_look`, `apply_look`). `page_js.py` is Skim as it ships, its balance run through the page's own JavaScript (Tools/exposeval/page.mjs); a balance candidate is `PATCHES` on the page's text (`s2_lift_cap.py`). `baseline.py` / `r1_logmean.py` are the numpy ports, kept for the history |
| `lowkey.py` | Low-key shots apart (info): adaCG `night`, and look shots ≥ 0.5 stop under their shoot |
| `LOG.md` | Every round, numbers only |
| `test_grademodel.py` | Synthetic tests (Linux too): `make grademodel-test` |

```bash
PY=~/LuminaEvidence/venv-parity/bin/python
$PY -I Tools/grademodel/prepare.py                       # once; reads the T7 (slow: NTFS)
$PY -I Tools/grademodel/evaluate.py Tools/grademodel/candidates/page_js.py    # the page as it ships (needs node)
python3 Tools/grademodel/compare.py ~/LuminaEvidence/grademodel/<date>/baseline.json ~/LuminaEvidence/grademodel/<date>/<cand>.json
$PY -I Tools/grademodel/lowkey.py <incumbent.json> <candidate.json>
make grademodel-test
```

## Data and what each may be used for

| Set | Pairs | Use |
|---|---|---|
| Uday, Saratoga (private, `/Volumes/T7/Lumina/uday`) | his FCP edit, S-Log3 OG ↔ his grade, 8 shots (shot 2 dropped: exports not aligned) | fit his own look; score held-out shots |
| Netflix Sparks SDR (CC BY) | ACES linear ↔ graded SDR 709, 108 frames in 8 ranges | fit + score |
| Tears of Steel (CC BY) | linear plates ↔ the regraded edit, 33 shots | fit + score |
| PST50 (licence unclear) | 709 ↔ pro grade, 50 pairs, 4 look clusters | **score only** |
| HDRVS adaCG (licence unclear) | the annotator's per-shot middle (Tools/exposeval's proxy) | **score only** |

No frame, label or sample is committed; only numbers.

## How a candidate is scored

- **Exposure (adaCG).** The candidate's balance runs over every shot of a location (the shoot); its luminance-weighted
  stops are compared with the annotator's relative middle (`Tools/exposeval/target.py`). ⇧E as shipped reproduces
  Tools/exposeval's 0.59 on all 782 shots.
- **Look + balance (Uday, Sparks, ToS).** Balance runs over the whole shoot (no grade seen). The look is fitted on the
  other shots' balanced pixels (leave one shot out; ToS in 6 folds) and scored with ΔE2000 on the held-out shot's
  unseen frames. Rows: median over shots of each shot's median, and of each shot's p95.
- **Look (PST50).** Fitted on half the 32 px blocks of one graded frame, scored on the other half; transfer: one
  pair's look on the other pair of its look cluster.
- **Info, not gated:** the oracle exposure (the one extra gain that would fit the held-out shot best, on top of the
  candidate's balance: what a touch-up pass would set) and ΔE with it.

The look's input is scene-linear through S-Log3 on every set, so Sparks' ACES and ToS's plates go through the same
curve as Uday's clips. Exposure is a scene-linear gain before the look (Skim's Exposure since #339 is applied in
Final Cut after the LUT; on log input, a code shift there is the same gain).
