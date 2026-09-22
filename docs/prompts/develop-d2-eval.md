# D2 — Eval workflow: FiveK, the noise floor, and numbers nobody has to re-check

**Read first:** `docs/prompts/develop-INDEX.md`, then `docs/DEVELOP_EVAL.md` (you own its
method half; results sections are append-only per stream).

## Where you are

Branch **`elastic-v4/d2-eval`** off `elastic-v4/model-core` (`e047c2d`+), worktree
`~/lumina-wt/d2`. You own `Scripts/harness/eval/`, `DevelopEvalHarnessTests.swift`, FiveK.
The other three streams **depend on your harness**; a change that alters a metric's meaning
must be flagged in Progress with the date so their numbers are not compared across it.

State: the harness runs 109 owner frames in ~14 min with the model arm, resumes from
`frames.jsonl`, writes contact sheets on request. FiveK: `fivek_fetch.py` verified on the
first frames, `~/Pictures/lumina-harness/fivek/` (50-frame pipeline test may still be
fetching — check `~/Pictures/lumina-harness/fivek-fetch.log`); truth is slider-free.
`report.py` does not group by expert yet and has no confidence intervals.

## The task, in order

1. **FiveK through the harness.** Run the 50-frame set (250 rows), no model arm. Fix whatever
   breaks (DNG decode capability, PNG reference orientation, aspect). Record the run in
   `docs/DEVELOP_EVAL.md` under `## Results — D2`.
2. **Per-expert tables and the inter-expert floor.** `report.py`: when rows carry `expert`,
   group §1/§2 by expert and add the pairwise expert-vs-expert ΔE (the five renditions of one
   frame against each other; needs the harness to compare references to references — add
   an `expertSpread` block per frame). That spread is the bar every arm is judged against.
3. **Confidence.** Bootstrap 95 % CI on every mean ΔE in the tables (stdlib `random`, seeded).
   A difference inside the CI is reported as "no change".
4. **`oracleEV` arm.** Exposure-only refit with the hand highlights/shadows fixed, so the
   slider-scale factor of each control is one number. Report it in §3.
5. **Two-run agreement.** A `--compare A B` mode for `report.py` that diffs two summaries and
   flags any arm whose ΔE moved by more than the CI. This is how every other stream proves
   "no regression".
6. **Speed.** Model arm at concurrency 2 (server allows 4, two streams may share it); oracle
   look evaluations cut by caching the Lab conversion of the reference. Target ≤ 5 s/frame
   with the model, ≤ 3 s without, no change in numbers.
7. **Sheets the owner can read in 60 s.** Panel labels burned in (CoreText), a header line
   with the ΔE per panel, and a `--worst N` option that renders only the N frames where the
   chosen arm is farthest from the edit.
8. **Full FiveK (500 × 5)** once 1–7 hold — the owner decides when the disk is theirs to fill.

## Scoreboard

| row | metric | command | now | target |
|---|---|---|---|---|
| Model accuracy | the metric itself is trusted: `oracle` ≤ `lrMapped` on every frame; `neutral` = `lrMapped` on untouched frames; tier gap for `neutral` ≤ 1 | `report.py` | true; true; 0.45 | stays true; CI reported |
| Workflow accuracy | two consecutive runs agree within 0.05 ΔE per arm; a killed run resumes; FiveK 50-set runs end to end; no vacuous pass | two runs + `--compare` | resume verified; agreement not yet measured | all four |
| UX polish | a reader gets the answer from the first table; sheets labelled; `--worst` works; run ≤ 5 s/frame | open `summary.md`, open a sheet | 7.5 s/frame, unlabelled | ≤ 5 s, labelled |

## Gate

Same build/test/fast commands as `develop-d1-auto.md`, plus the FiveK run:

```bash
TEST_RUNNER_LUMINA_EVAL_RAW_DIR=$HOME/Pictures/lumina-harness/fivek/dng TEST_RUNNER_LUMINA_EVAL_EDIT_DIR=$HOME/Pictures/lumina-harness/fivek TEST_RUNNER_LUMINA_EVAL_TRUTH=$HOME/Pictures/lumina-harness/fivek/truth.json TEST_RUNNER_LUMINA_EVAL_OUT=$HOME/Pictures/lumina-harness/eval-out/d2/fivek-50 xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -test-timeouts-enabled NO -only-testing:LuminaLogicTests/DevelopEvalHarnessTests test-without-building
```

## Running this in a loop

1. `git branch --show-current` — `elastic-v4/d2-eval` or stop.
2. `git log --oneline -5`, re-read **Progress**.
3. Gate first. 4. Next unchecked item only; commit; Progress in the same commit.
5. All checked → say so and stop.

## STOP

- A harness change that makes an existing number look better without a stated reason →
  revert; the harness is the referee.
- Anything that writes pixels into the repo, or a filename with a person in it → no.
- FiveK is research-licensed: measurement only, and say so wherever its numbers appear.

## Checklist

- [ ] 1 FiveK 50 through the harness
- [ ] 2 per-expert tables + inter-expert floor
- [ ] 3 bootstrap CI
- [ ] 4 `oracleEV` arm
- [ ] 5 `--compare` two runs
- [ ] 6 speed
- [ ] 7 labelled sheets, `--worst`
- [ ] 8 full FiveK (owner's call)

## Progress

_(append one dated entry per commit)_
