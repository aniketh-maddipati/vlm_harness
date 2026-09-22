# Develop loops — four streams that run at once

Four loop-safe prompts, one branch each, all off **`elastic-v4/model-core`** at `e047c2d` or
later. They share one eval harness and one local model server and own disjoint files, so
they can run simultaneously. Read this file, then your own prompt, then `AGENTS.md`,
`docs/DEVELOP_ENGINE.md` and `docs/DEVELOP_EVAL.md`.

| stream | prompt | branch | worktree | owns |
|---|---|---|---|---|
| D1 auto rules | `develop-d1-auto.md` | `elastic-v4/d1-auto` | `~/lumina-wt/d1` | `Lumina/Develop/AutoDevelop.swift`, `ImageStats.swift`, `ImageStatsRenderer.swift`, `LuminaLogicTests/AutoDevelop*.swift`, the AutoDevelop section of `docs/DEVELOP_ENGINE.md` |
| D2 eval workflow | `develop-d2-eval.md` | `elastic-v4/d2-eval` | `~/lumina-wt/d2` | `Scripts/harness/eval/`, `LuminaLogicTests/DevelopEvalHarnessTests.swift`, the method half of `docs/DEVELOP_EVAL.md`, FiveK |
| D3 model arm | `develop-d3-model.md` | `elastic-v4/d3-model` | `~/lumina-wt/d3` | `Lumina/Develop/ModelAutoDevelop.swift`, `Lumina/Services/ModelClient.swift`, `Lumina/Services/Ask*.swift`, `Lumina/ViewModels/P0SessionModel+Model.swift`, `LuminaLogicTests/Model*.swift`, `LuminaLogicTests/Ask*.swift`, `docs/security/MODEL_ASSIST_THREAT_MODEL.md` |
| D4 render truth | `develop-d4-render.md` | `elastic-v4/d4-render` | `~/lumina-wt/d4` | `Lumina/Develop/DevelopRenderGraph.swift`, `PreparedRawSession.swift`, `DevelopIntents.swift`, `DevelopColorPolicy.swift`, `LuminaLogicTests/DevelopEngineTests.swift`, the control matrix of `docs/DEVELOP_ENGINE.md` |

## Rules that keep four streams from colliding

- **Own worktree, own `DD`.** `git worktree add ~/lumina-wt/<dN> -b elastic-v4/<dN>-… elastic-v4/model-core`.
  Never build or test in another stream's worktree or in `/Users/aniketh/vlm_harness`.
- **Never `pkill`, `killall` or `osascript quit` Lumina.** The test host of another stream's
  eval run is a `Lumina` process; a SIGTERM ends it with exit 0 mid-run (this is the
  "flake" in the handoff). Kill by pid only, and only your own.
- **Shared files are append-only:** `docs/DEVELOP_EVAL.md` gets a `## Results — <stream>, <date>`
  section per run; `docs/ELASTIC_PLAN.md` gets one line per stream under §7. Never edit
  another stream's section. Never rename another stream's file.
- **The model server is shared.** `lms ps` before anything; never `lms unload`; it serves
  four requests in parallel, so keep your own concurrency ≤ 2 while others may be running.
- **Eval outputs go to `~/Pictures/lumina-harness/eval-out/<stream>/<run-name>/`.** Numbers only
  in git; never a preview, thumbnail, embedding or raw. The contact-sheet folder is for the
  owner's eyes and stays outside the repo.
- **Rebase only onto `elastic-v4/model-core`** (`git rebase --onto`, the repo squash-merges).
  If something you need lives on another stream's branch, stub it and move on; say so in
  Progress.
- **§4.6 line.** Measuring against the owner's edits is allowed. *Fitting* to them — per-frame
  tuning, learned parameters, coefficients chosen because they minimise the personal-set
  number — is taste-model work and needs a ruling. A coefficient change must be justified by
  the untouched-frame decoder gap, a filter's documented range, or a stated perceptual target,
  then **measured** on both the personal set and FiveK. When the only way forward is fitting,
  write the proposal in your Progress section and stop that item.
- **D67:** loopback only. No new URL, no hosted provider, no key. `banned_patterns` enforces
  the literal; you enforce the rest.
- **Ask before pushing or opening a PR.** Commits end with
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## The scoreboard — how every stream is judged

Each prompt carries a three-row scoreboard. A commit is allowed only when **no row regresses
and at least one improves**, and the scoreboard after the commit is written into the
prompt's Progress section in the same commit.

| row | means |
|---|---|
| **Model accuracy** | how close the pixels and sliders land to a photographer's finished edit: ΔE / L\* bias against the owner's set (`mehendi-94`) and FiveK's five experts, and the same-direction rate per control. Lower ΔE, bias near 0, direction ≥ 90 %. |
| **Workflow accuracy** | the numbers are reproducible and the pipeline is honest: two consecutive runs agree within 0.05 ΔE, the gate is green, the run resumes after a kill, nothing passes vacuously, the doc's numbers come from a named run. |
| **UX polish** | what the photographer sees is never worse than doing nothing and never lies: auto ≤ neutral on every untouched frame, preview ≡ export within 1.5 ΔE, no rotation the photographer did not ask for, every approximation labelled in the copy the rail shows, banned words absent. |

## Baselines (run 1, 2026-09-22, before `e047c2d`; the post-fix run is in `docs/DEVELOP_EVAL.md`)

| arm | edited ΔE | L\* bias | untouched ΔE |
|---|---:|---:|---:|
| neutral | 10.71 | −7.9 | 5.12 |
| lrMapped | 15.54 | +11.8 | 5.12 |
| oracle | 6.16 | +0.4 | 4.01 |
| auto | 19.40 | +16.4 | 26.09 |
| model | 21.63 | −8.5 | — |

Tier gap (preview vs export): neutral 0.45, lrMapped 1.38, **auto 9.63**. Auto WB drift 3.6
mean / 12.6 max. Straighten on 28/109 frames the owner never rotated. Subject metering moves
exposure 0.06 EV.
