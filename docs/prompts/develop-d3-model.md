# D3 — Model arm: corrections, not restyles

**Read first:** `docs/prompts/develop-INDEX.md`, `docs/security/MODEL_ASSIST_THREAT_MODEL.md`,
`docs/DEVELOP_EVAL.md` §7 of run 1.

## Where you are

Branch **`elastic-v4/d3-model`** off `elastic-v4/model-core` (`e047c2d`+), worktree
`~/lumina-wt/d3`. You own `ModelAutoDevelop.swift`, `ModelClient.swift`, `Ask*.swift`,
`P0SessionModel+Model.swift`, the model/ask tests, the threat model. D67 stands: loopback
only, no key, no new URL. The 14 threats each have a named test — they stay green; the
echo guard stays.

State: the model arm (Qwen2.5-VL 3B on LM Studio, 127.0.0.1:1234, `lms ps` first) answered
every one of 109 frames and was the farthest arm: ΔE 21.6, contrast MAE 18 (it sits at the
band edge), highlights moved the *wrong* way on 100 % of frames the owner touched, saturation
MAE 15. The band bounds it; the proposals are restyles. The ask planner (text model) is
verified for language → scope + action and is not the problem.

## The task, in order

1. **Reproduce the failure in numbers you can iterate on.** Dump, per frame, the raw proposal
   before banding next to the hand edit (D2's harness records the bounded recipe; add a
   `proposal` field on the model arm — harness file is D2's, so ask via Progress or carry a
   local patch you do not commit). Establish: is the model saying "+contrast +saturation" on
   every frame regardless of the picture?
2. **Prompt as a correction task.** The system prompt asks for "first-pass correction, small
   moves". Try: state the measured stats *and* what a neutral render already does; ask for
   deltas from neutral with an explicit "0 is the common answer"; forbid restyling words.
   Keep the field-ranges sentence (it is load-bearing — dropping it produced the echo).
   Measure every variant on the same 30-frame subset before the full set.
3. **Band redesign from data, not taste.** Bands should be the oracle's 5–95 % range on the
   *untouched-plus-decoder-gap* frames, i.e. the moves a correction ever needs — not ±25
   contrast because it sounded safe. Justify each band in the commit from `report.py` §4.
4. **Highlights sign.** Something makes the model propose positive highlights on frames the
   owner recovered. Check whether the prompt's wording ("highlights from −100 to 100") reads
   as "clip more"; a one-line gloss ("negative recovers blown highlights") is the test.
5. **Larger model, same rules.** If a 7B vision model is resident (`lms ls`), run the same
   30-frame subset once. Report; do not switch the default without the owner.
6. **Latency.** Concurrency 4 in `applyModelAuto` is product; the harness uses 1. Measure p95
   per frame at 2 and 4 with another stream possibly sharing the server; the reply-size bound
   and the deadline (a listed residual risk) belong here.

## Scoreboard

| row | metric | command | now (run 1) | target |
|---|---|---|---|---|
| Model accuracy | `model` ΔE on edited frames; same-direction rate for highlights / contrast / saturation | D2 harness with `TEST_RUNNER_LUMINA_LIVE_MODEL=1` | 21.6; 0 % / 97 % / 28 % | < `auto`; highlights ≥ 90 % |
| Workflow accuracy | 0 unexplained fallbacks; every fallback reason counted; threat-model tests green; two runs at temperature 0 agree within 0.1 ΔE | `report.py` §5, logic suite | 0 fallbacks; agreement not measured | same, measured |
| UX polish | p95 ≤ 4 s/frame at concurrency 4; the fallback copy (banned words: sync, preset, AI, smart, auto, analyze, generate, magic) never reaches the rail; batch stays all-or-nothing and one ⌘Z | `ModelRaceTests`, timing in Progress | 3 s at concurrency 1 | measured at 4 |

## Gate

Build/test/fast as in `develop-d1-auto.md`; the eval run adds `TEST_RUNNER_LUMINA_LIVE_MODEL=1`
and writes to `~/Pictures/lumina-harness/eval-out/d3/<run-name>`. A 30-frame subset is
`TEST_RUNNER_LUMINA_EVAL_LIMIT=30`.

## Running this in a loop

1. `git branch --show-current` — `elastic-v4/d3-model` or stop.
2. `git log --oneline -5`, re-read **Progress**. 3. `lms ps`; gate.
4. Next unchecked item only; commit; Progress with the scoreboard in the same commit.
5. All checked → say so and stop.

## STOP

- Any prompt or few-shot that quotes the owner's edits or FiveK experts → that is fitting; stop.
- Any URL that is not loopback, any key, any Keychain read → no.
- Loosening a threat-model test → no; move it with a reason or stop.

## Checklist

- [ ] 1 raw proposals dumped and read
- [ ] 2 correction prompt, measured on 30
- [ ] 3 bands from data
- [ ] 4 highlights sign
- [ ] 5 larger model, reported
- [ ] 6 latency at concurrency 2 / 4

## Progress

_(append one dated entry per commit)_
