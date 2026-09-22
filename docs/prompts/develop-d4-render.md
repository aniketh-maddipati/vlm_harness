# D4 — Render truth: preview ≡ export, and every control means what it says

**Read first:** `docs/prompts/develop-INDEX.md`, `docs/DEVELOP_ENGINE.md` (control matrix,
operation order), `docs/COLOR_PIPELINE.md`, `docs/DEVELOP_EVAL.md` §2 and §4 of run 1.

## Where you are

Branch **`elastic-v4/d4-render`** off `elastic-v4/model-core` (`e047c2d`+), worktree
`~/lumina-wt/d4`. You own the render graph, the RAW session, the intents, the colour policy,
`DevelopEngineTests`, and the control matrix. You do **not** own `AutoDevelop` (D1): if a
fix here makes one of its rules moot, say so in Progress; do not edit it.

State: `e047c2d` fixed the highlight/shadow mapping's ranges but not its *scale* — the
oracle still keeps the hand highlight/shadow values and pulls exposure ~0.9 EV to compensate,
so the per-unit strength of both controls versus Lightroom is unmeasured. `temperature` has
two meanings: the 6500 sentinel is as-shot on both tiers, but an explicit Kelvin is absolute
on the authoritative tier and a `CITemperatureAndTint` shift *from 6500* on the interactive
one (`applyExposureAndWhiteBalance`), so any hand-set or auto-set Kelvin previews differently
than it exports (auto: 9.6 ΔE). Positive Highlights is inert. Whites / Blacks / Clarity /
Texture / Dehaze are disabled by design and the hand edits use Whites/Blacks on 86 of 109
frames.

## The task, in order

0. **The interactive stage is vertically mirrored in CI space.** Measured in
   `docs/DEVELOP_EVAL.md` run 2: uncropped frames match the authoritative render only after a
   vertical flip (0.45 vs ~34 ΔE), and every cropped frame crops the wrong region on the
   interactive tier. Source: `materializeInteractiveStage` (`CIRenderDestination.isFlipped =
   true` + `CIImage(mtlTexture:)`). This is the owner's "photographs flip upside down" report
   (`docs/prompts/elastic-p0.md` §2) — coordinate with that stream before touching
   `DevelopMetalView`, which may be compensating on display. Acceptance: the harness's
   `asIsDeltaE` on `neutral` drops to the mirrored value; D2's tier gap needs no mirroring;
   a cropped frame previews the same region it exports. Do this before item 1 — item 1's
   measurement depends on it.
1. **White balance previews as it exports.** The interactive post-op must shift from the
   file's *native* neutral (`PreparedRawSession.Metadata.nativeNeutralTemperature/Tint`), not
   from 6500. `finishRawStage` has the metadata; `branchInteractiveVariant` and the proxy path
   need it passed in. Measure with D2's `tierGap` on `lrMapped` custom-WB frames (23 of them)
   and on `auto`: ≤ 1.5 ΔE.
2. **Highlight / shadow scale.** Using D2's `oracleEV` arm (or a local equivalent), find the
   per-unit gain that makes `lrMapped` ≈ `oracle` on frames where the hand edit used only the
   rendered controls. Apply it as a documented constant with its derivation in the control
   matrix. Positive Highlights: either an honest implementation (a separate curve stage) or
   the rail says "no effect above 0" — pick, document, test.
3. **Preview ≡ export contract test.** A logic test that renders one recipe with explicit
   Kelvin, non-zero tone, and a crop on both tiers and asserts ΔE ≤ 1.5 on a real RAW
   (fixture-gated, skip loudly). This is the test that would have caught item 1.
4. **Whites / Blacks proposal — doc first.** The hand edits use them on 86/109 frames, yet the
   oracle residual correlates only weakly (r 0.27) with their magnitude. Write the measured
   case for or against a tone-endpoint stage in `docs/DEVELOP_ENGINE.md`; the constitution
   decides. No code until ruled.
5. **Decoder gap.** 5.1 ΔE on untouched frames between Apple's decode + Lumina and Adobe
   Standard + Lightroom. Split it: lens profile (centre vs full-frame numbers), colour
   (the oracle's saturation/vibrance moves on untouched frames), tone. Report which part is
   reachable with the rendered controls and which is a profile.

## Scoreboard

| row | metric | command | now (run 1) | target |
|---|---|---|---|---|
| Model accuracy | `lrMapped` ΔE on edited frames approaches `oracle`; `neutral` on untouched frames (decoder gap) | D2 harness, `report.py` §1–§3 | 15.5 vs 6.2; 5.12 | lrMapped − oracle ≤ 2; gap explained |
| Workflow accuracy | control matrix rows carry a measured mapping and a derivation; `DevelopEngineTests` + preview≡export test green; two runs agree | logic suite, two runs | rows say "approximation"; no tier test | every rendered row measured; test exists |
| UX polish | tier gap ≤ 1.5 ΔE for every arm; every approximation and inert range in the rail's copy (`approximationNote`); banned words absent | `report.py` §5, `banned_words.sh` | auto 9.6; positive Highlights noted | all ≤ 1.5; complete |

## Gate

Build/test/fast as in `develop-d1-auto.md`; eval outputs to
`~/Pictures/lumina-harness/eval-out/d4/<run-name>`. `render_data_plane_isolation` and
`progressive_render_architecture` lints pin this plane — new `nonisolated` types are
registered there, never worked around.

## Running this in a loop

1. `git branch --show-current` — `elastic-v4/d4-render` or stop.
2. `git log --oneline -5`, re-read **Progress**. 3. Gate first.
4. Next unchecked item only; commit; Progress with the scoreboard in the same commit.
5. All checked → say so and stop.

## STOP

- A new persisted field on `EditRecipe` → schema proposal in `docs/` and a ruling first.
- Anything that makes preview and export diverge on purpose → no.
- A calibration constant chosen because it minimises the owner's number rather than from a
  derivation you can write down → Progress, not code.

## Checklist

- [ ] 0 interactive stage mirrored (the flip)
- [ ] 1 WB previews as it exports
- [ ] 2 highlight/shadow scale + positive Highlights decision
- [ ] 3 preview ≡ export contract test
- [ ] 4 Whites/Blacks proposal (doc)
- [ ] 5 decoder gap split

## Progress

_(append one dated entry per commit)_
