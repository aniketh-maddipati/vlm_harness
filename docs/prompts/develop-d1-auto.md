# D1 — Auto rules: beat doing nothing, on every frame

**Read first:** `docs/prompts/develop-INDEX.md` (rules, ownership, scoreboard), then
`docs/DEVELOP_ENGINE.md` §AutoDevelop and `docs/DEVELOP_EVAL.md`.

## Where you are

Branch **`elastic-v4/d1-auto`** off `elastic-v4/model-core` (`e047c2d`+), worktree
`~/lumina-wt/d1`. You own `AutoDevelop.swift`, `ImageStats*.swift`, `AutoDevelop*Tests`, and
the AutoDevelop section of the engine doc. You do **not** own the render graph (D4) or the
harness (D2): if a measurement needs a harness arm that does not exist, ask D2 through
Progress and stub locally.

The deterministic auto pass loses to the neutral decode 2× on the owner's edits. Part of that
was the highlight/shadow mapping, fixed in `e047c2d`; the rest is yours:

- `AutoDevelop.recipe` writes `temperature = nativeTemperature` with `tint = 0`. On the
  authoritative tier that drops the camera's native tint (3.6 ΔE mean, 12.6 max from as-shot);
  on the interactive tier it is applied as a shift from 6500 K (9.6 ΔE between tiers).
- Horizon straighten fires on 28/109 frames the owner never rotated.
- Exposure pulls the mean to 0.46 at gain 3; hand edits average +0.33 EV on frames whose
  measured mean is already ~0.35, and the oracle's exposure sits *below* the hand value once
  shadows are lifted. Whether the anchor or the gain is wrong is a measurement, not a guess.
- The default −20 / +15 curve on non-clipping frames has never been measured against anything.

## The task, in order

1. **White balance is as-shot unless auto proposes a change.** Stop writing `temperature`
   (the 6500 sentinel *is* as-shot on both tiers). If carrying native tint is wanted, that is
   a new `ImageStats.nativeTint` field, tolerant-decoded, five-site probe mirror not involved.
   `AutoDevelopTests.testNativeTemperature…` will move — that is a result to report in the
   commit, not a silent edit. Measure: `autoWB` ΔE from neutral → 0, `tierGap.auto` ≤ 1.5.
2. **Straighten only on evidence.** Require a horizon observation Vision is confident in and
   an angle the frame's own content supports (a face-bearing frame with a 3° "horizon" is
   noise). Measure: non-zero straighten on ≤ 3/109 owner frames; keep the horizon fixture
   tests green.
3. **Exposure rule, measured through the fixed filter.** Run the post-fix eval; read the
   oracle's exposure against the hand exposure per frame *and* against the measured mean.
   Propose an anchor/gain justified by the untouched-frame gap and a stated target (e.g. the
   oracle's median exposure at mean 0.35), then measure on both sets. No per-frame fitting.
4. **The default curve.** Same method for −20 / +15: measure against the oracle's highlights
   and shadows on non-clipping frames; propose; measure. If the honest answer is "0 / 0",
   say so.
5. **Subject-weighted metering** only after 1–4: it moved exposure 0.06 EV through the broken
   filter. Re-measure via D2's `autoSubject` arm; adopt only if it beats global on both sets.

## Scoreboard

| row | metric | command | now (run 1) | target |
|---|---|---|---|---|
| Model accuracy | `auto` ΔE on edited frames, owner set; same-direction rate for exposure / highlights / shadows | D2 harness + `report.py` | 19.40 · 93 % / 100 % / 96 % | < neutral (10.7), toward oracle (6.2); direction ≥ 90 % |
| Workflow accuracy | `AutoDevelopTests`, `AutoDevelopRawFixtureTests` green; two consecutive runs within 0.05 ΔE; every coefficient change cites its justification in the commit | logic suite + two eval runs | green; not yet checked | green; agree |
| UX polish | `auto` ≤ `neutral` on every untouched frame; `tierGap.auto` ≤ 1.5; straighten on ≤ 3/109 | `report.py` §1 and §5 | 26.1 vs 5.1; 9.6; 28 | pass all three |

## Gate

```bash
cd ~/lumina-wt/d1
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests build-for-testing
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test-without-building
python3 Scripts/harness/run.py fast
# eval, owner set, no model arm (faster; the model arm is D3's)
TEST_RUNNER_LUMINA_EVAL_RAW_DIR=$HOME/Pictures/lumina-harness/mehendi-94 TEST_RUNNER_LUMINA_EVAL_EDIT_DIR=$HOME/jeevana_mehendi_2026 TEST_RUNNER_LUMINA_EVAL_TRUTH=$HOME/Pictures/lumina-harness/eval-out/truth.json TEST_RUNNER_LUMINA_EVAL_OUT=$HOME/Pictures/lumina-harness/eval-out/d1/<run-name> xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -test-timeouts-enabled NO -only-testing:LuminaLogicTests/DevelopEvalHarnessTests test-without-building
python3 Scripts/harness/eval/report.py $HOME/Pictures/lumina-harness/eval-out/d1/<run-name>/metrics.json --out $HOME/Pictures/lumina-harness/eval-out/d1/<run-name>/summary.md
```

## Running this in a loop

1. `git branch --show-current` — on `elastic-v4/d1-auto` or stop and say so.
2. `git log --oneline -5`, re-read **Progress** below. The file is the only state that survives.
3. Gate before changing anything; note whether you start from green.
4. Do the **next unchecked item only**. Commit. Update **Progress** with the scoreboard after
   the commit, in the same commit.
5. Every item checked and the scoreboard not regressed → say so and stop.

## STOP

- A change that only helps because it was chosen against the owner's numbers → write the
  proposal in Progress, do not commit it.
- `AutoDevelopTests` would need loosening rather than moving → stop, report.

## Checklist

- [ ] 1 white balance as-shot
- [ ] 2 straighten on evidence
- [ ] 3 exposure rule measured
- [ ] 4 default curve measured
- [ ] 5 subject metering re-measured

## Progress

_(append one dated entry per commit: what changed, scoreboard after, what moved in tests)_
