# Sony technical assist v0 — not promoted

This branch implements a reviewable experiment, not a production editing-quality claim.
The local controller chose **neutral on every frame**. It removes the old controller's
harmful restyling but supplies **no incremental correction over neutral**. Keep it off by
default. The conservative deterministic policy is available as an explicit session action;
its visual benefit still needs the owner's blind review. Existing Auto remains the legacy
baseline, not a newly validated recommendation.

## Source and isolation

Fetched origin before changing code. Main was clean at `603f95d`. Isolated branch:
`codex/sony-technical-assist`, based on `elastic-v4/model-core` `f53054d`.
Other inspected tips: model-assist `9745c9e`, p0-render-proof `d2b2824`, next-round `4d46a8a`,
ui-reconcile `8b939bb`, p1-grammar `68ccbc1`, p2-scroll `4ca6d2e`. No newer develop/D1–D4
branch was present after fetching. The model, P0 and UI worktrees were clean when inspected.
No other worktree was edited, built in, rebased, or killed.

Model-core already contains the highlight/shadow mapping correction `e047c2d` and the
later 109-frame run. P0's texture-orientation fix was committed on `d2b2824` and present in
UI reconciliation, but absent from model-core. This branch imports that exact
`PreparedRawSession.swift` orientation correction rather than reinventing it. UI
reconciliation has many separate UI/scroll changes but does not carry model-core's model
and evaluation files; it was not an appropriate wholesale replacement base.

This owner's request supersedes the older D-stream requirement to optimize reference
edit distance, its branch naming, and its prohibition on integrating another stream's
fix. No personal taste fitting, new recipe schema, hosted photo upload, or key was used.
No push or PR was made. A UI-integration review remains necessary before merging these
render changes into the newer UI tree.

## What is implemented

- Read-only resumable ARW inventory using exiftool, incremental SHA-256, SQLite checkpoints,
  source-change checks, metadata, exact card-copy relationships, and inferred time sessions.
  Private embedded-preview contact sheets honor RAW orientation; coarse visual groups are
  explicitly inferred, not confirmed lighting. Outputs are refused inside any git worktree.
- Explicit whole-shoot split freezing, immutable manifests, duplicate protection, and
  refusal to change a frozen split or resume a run with changed source/input/model settings.
- `TechnicalAssist`: opt-in, neutral-render input, measured constraints, one closed action,
  one-third-stop exposure or -20 highlight recovery, neutral, or abstention. No colour,
  geometry, multi-slider vector, or application mutation. Observations are labeled hypotheses.
  Legacy Auto is rejected as a controller action until validated. Its unsafe behavior remains
  visible in the existing `auto` arm. The controller has an eight-second transport deadline,
  bounded image/reply sizes, cancellation checks, and the existing loopback-only client.
- `applyTechnicalPolicy(to:)`: an explicit deterministic session entry point, skip hand and
  sidecar edits, deduplicate IDs, preserve WB/geometry, and commit one undoable batch. It is
  not yet connected to a new production UI button. The experimental model is not substituted
  into the old `applyModelAuto` path; its existing threat-model tests remain intact.
- Actual authoritative candidates for neutral, Auto, simple policy, and controller; existing
  mapped reference, legacy model, subject metering, WB-only, and diagnostic oracle arms retained.
  Legacy raw JSON proposals are captured before clamping. Oracle is used only on development
  reference comparisons, never to choose held-out actions.
- Private blinded HTML comparisons, tie/both-bad/severe-reason input, export/import of decisions,
  and a persistent project queue for proposals, abstentions and inconsistency hypotheses.
  Queue acceptance records an override; it does not silently write a recipe. It can later
  support unfinished-work queries without selecting a gallery or essay.
- Immutable small review-preview/observation cache with RAW-content, render-pipeline, recipe,
  model-weight revision keys and corruption checks. Measured 216 misses on first population,
  216 hits on second. This is review reuse, **not inference acceleration**. Model inference
  caching is deferred; profile and establish useful model behavior before adding it.

## Data and frozen evaluation

The supplied folder contained **54 ARWs**, not the anticipated 2,000. All are ILCE-7M3.
The owner confirmed May 23–24 are one shoot; the other dates are different shoots:

| partition | confirmed shoots | unique RAWs | comparison rows |
|---|---:|---:|---:|
| Existing edited-event development set | 1 | 94 | 109 (includes virtual copies) |
| Held-out May trip | 1 | 4 | 4 |
| Held-out August trip | 1 | 31 | 31 |
| Held-out April portraits | 1 | 19 | 19 |

The two inferred time groups in the development event remain one shoot. All three other
shoots were reserved before model evaluation, with the controller source hash frozen.
No threshold/prompt/action tuning followed holdout inspection. Contact sheets suggest
outdoor landscape, urban shade/bright-sky, and sunlit portrait conditions. These are scene
hypotheses; **confirmed lighting-condition count is unknown**. Three small held-out shoots
cannot justify generalization to the broader library. No FiveK files were used or copied.

## Measurement repair

The native-Kelvin post-op experiment was insufficient: an eight-row check still had Auto
preview/export gaps up to 13.76 ΔE. It was not accepted as a fix. Both interactive and
authoritative tiers now bake the same exposure and WB/tint intent on CIRAWFilter.
Interactive exposure/WB changes therefore invalidate the RAW cache. Look-only edits still
reuse it. The pipeline mapping version changed to `lumina-ciraw-2`.

Variants now share sources only when their RAW intents match, with generation-checked
publication and no decode after a pre-dispatch cancellation. This deliberately gives up
the old promise that four distinct WB variants can all use one as-shot surface. Production
scrub/variant latency and memory must be re-profiled before merging into the latest UI.

Named run `development-baked-v1`, 109 rows, same reference comparisons as prior run 2:

| arm | edited mean CIE76 ΔE, prior → now | untouched mean ΔE now |
|---|---:|---:|
| neutral | 10.71 → 10.71 | 5.12 |
| mapped owner edits | 10.04 → 10.04 | 5.12 |
| diagnostic oracle | 5.58 → 5.58 | 4.01 |
| legacy Auto | 11.70 → 11.70 | 15.59 |
| legacy model | 33.32 → 33.32 | 28.42 |
| simple policy (new) | — → 8.88 | 5.04 |
| closed-action controller (new) | — → 10.71 | 5.12 |

These are distances to particular Lightroom exports, **not photographic-quality scores or
blind preferences**. No coefficients were fitted to those exports. The prior authoritative
numbers reproduce to 0.01 ΔE; only the formerly faulty interactive semantics changed.

| preview vs authoritative, 109 rows | mean | p95 (lower empirical) | worst |
|---|---:|---:|---:|
| neutral | 0.50 | 0.75 | 0.83 |
| mapped reference recipe | 0.62 | 1.10 | 1.12 |
| legacy Auto | 0.65 | 0.88 | 1.08 |

No tier comparison exceeded 1.5 ΔE. A separate 24-case live contract covers explicit
Kelvin/tint, exposure, off-center crop and quarter-turns: mean 0.51, worst 0.91,
24/24 warm RAW-cache hits. At 640 px, cold render p50 8.15 ms / p95 204.47 ms; these are
small-sample test timings, not production slider latency.

`contract-full-export-v1` also passed the public interactive graph against encoded,
full-resolution ProPhoto TIFF exports on three Sony frames with explicit WB/tint, tone
and an off-center crop. CIE76 gaps: 0.875, 0.985, 0.945.
The temporary full-resolution TIFFs were deleted after verification; numeric evidence remains.

Existing Auto's unwanted geometry and WB behavior were reproduced: 27/109 nonzero
straighten proposals in this run (prior documentation says 28), WB-only drift 3.63 ΔE.
The safe policy never changes either. Legacy Auto remains unchanged for comparison;
replacing that product command requires a separately reviewed behavior change.

## Model failure and incremental benefit

Legacy model proposals on 109 frames: exposure -0.5 on 97 frames and -1 on 10;
saturation 60 on 57 and 70 on 48; tint shift 100 on 96. Some temperature shifts copied
camera Kelvin (up to 4985) instead of proposing a delta. These survive as band-edge
edits; the echo check only protects the three quoted luminance statistics. The fixed
shadow filter exposed the darkening previously hidden by maximum shadow lift.

The three worst-distance cases were inspected locally: pronounced darkening and saturated
red/green colour distortion. Their comparison gallery remains private. This diagnoses
those cases; it is not a human preference label for every legacy frame.

New controller: **109/109 development and 54/54 held-out decisions were neutral**, no
online abstentions, zero recipe differences from neutral. These are 54 deterministic ties
to neutral by recipe/pixel identity, not 54 completed human votes. Consequently there is
no demonstrated model contribution to an improved technical starting point.

| held-out shoot | frames | controller action | policy changed frames |
|---|---:|---|---:|
| May trip | 4 | neutral on all | 1 |
| August trip | 31 | neutral on all | 31 |
| April portraits | 19 | neutral on all | 4 |

A balanced 12-frame / 36-pair review compares the controller against neutral, Auto and the
policy, with each shoot represented. **Human wins/ties/losses/severe regressions are
pending, not zero.** Scene-type breakdown is pending confirmation of scene/lighting
labels. All new model candidates are neutral, so there is no model-induced pixel
regression relative to neutral; neutral itself is not guaranteed to be acceptable.

Second-stage rendered-candidate ranking was not run. A uniform-neutral controller supplies
no evidence that another model call is worth its latency. The next experiment is a frozen
comparison of actual rendered neutral/policy candidates after obtaining the owner's blind
judgments, with at most three candidates and a measured total budget. A larger installed
model was identified but not evaluated or recommended.

## Interaction measurements and limits

Actual machine: Apple M4 Pro, 24 GiB, macOS 26.5.2, Xcode 26.6. Local Qwen2.5-VL-3B Q4_K_M,
4096 context, two server slots, 3.27 GB listed model size (3.04 GiB load report). GGUF and
vision-projection weight digests are stored privately. No model was unloaded.

| measurement | p50 | p95 (nearest rank) | max |
|---|---:|---:|---:|
| development controller call | 1.37 s | 1.94 s | 2.36 s |
| development rendered suggestion | 1.44 s | 2.01 s | 2.45 s |
| held-out controller call | 1.76 s | 3.55 s | 3.84 s |
| held-out evaluation frame through rendered candidates | 2.24 s | 4.12 s | 4.26 s |

The held-out end-to-end timer includes preparation and rendering the other baseline
candidates; it is an upper bound on this serial harness's suggestion time, not an isolated
interactive UI measurement. Held-out throughput: 54 frames / 131.33 s = 0.41 frames/s.
Development took 753.27 s including both models and the expensive oracle, not just assist.
Runs overlapped on two local model slots; they are not uncontended concurrency benchmarks.

`offline-probe-v1` used a refused loopback port, without stopping the shared server:
abstention, neutral preserved, 23.43 ms call / 56.19 ms through rendered suggestion.
Cancellation is tested with a gated fake transport. Existing stale-edit, hand-edit skip,
one-step batch undo and threat-model tests remain green. Peak process/GPU memory and
concurrency-2/4 interaction profiling remain unmeasured; model file size is not peak RSS.

## Promotion decision

**FAIL / NOT PROMOTED.** No incremental model benefit; human preference evidence pending;
production interaction and peak-memory gates incomplete. Keep the model experimental and
off by default. The deterministic entry point is reviewable now, but its untouched-shoot
preference benefit is not established either. No claim of Lightroom quality is made.

Required before promotion: complete blind review and inspect all marked severe cases;
verify useful incremental benefit over the simple policy; confirm lighting labels;
profile actual UI scrub/variant/full-shoot interactions and memory; integrate with the
newer UI branch; connect accepted review state to the app with stale-state validation.
The broad ~2,000-file library is not present at the supplied path.

## Reproducing and reviewing

Scripts are in `Scripts/harness/eval/`. Use Python 3.11+ with PyYAML for the repository
static lane; Pillow is needed for private contact sheets. The system's default Python
3.8 fails an existing `removeprefix` lint; Apple's Python lacks PyYAML. Neither is evidence
of a product regression. Seven workflow/cache tests use standard-library fixtures.

```sh
python3 Scripts/harness/eval/sony_inventory.py --raw /path/to/ARWs --out /private/output/inventory --contacts
python3 -m unittest discover -s Scripts/harness/eval -p test_technical_workflow.py
python3 Scripts/harness/lint/xcode_compile.py --project-root . --derived-data /private/output/DD
# Run against that directory's generated P0Fast .xctestrun:
python3 Scripts/harness/eval/run_technical.py --raw /path/to/raws --edits /path/to/exports \
  --truth /private/truth.json --out /private/output/named-run --xctestrun /private/output/DD/Build/Products/Lumina_P0Fast_macosx26.5-arm64.xctestrun --live
# --legacy-model retains the old arm; --contract runs live render agreements.
# --shoot runs reference-free candidates (truth/edits arguments are currently required
# configuration scaffolding but are not used as labels or comparison targets).
python3 Scripts/harness/eval/technical_review.py prepare --metrics /private/run/metrics.json \
  --images /private/run/images --inventory /private/inventory.json --out /private/review
python3 Scripts/harness/eval/technical_review.py import --out /private/review --decisions /private/review-decisions.json
python3 Scripts/harness/eval/technical_review.py report --out /private/review
```

Inventory resumes per file; development evaluation resumes per completed reference row
only with the same frozen manifest. Reference-free shoot evaluation currently requires a
new named run after interruption; it refuses duplicate journals rather than claiming a
complete run. HTML choices persist locally and should also be exported to a private JSON
file. The JSON project queue records accept/reject/defer and reasons through the `choose`
command; this prototype does not infer acceptance from a blind preference vote.

Verification: 391 logic tests, one fixture skip, zero failures; seven workflow/cache tests;
41/41 static checks; named live development, held-out, render-contract and offline runs.
Vet was invoked after code units but could not review: no configured provider credential.
No credential was added. No PR/merge was attempted; the cache-free PR checkpoint is still
required before that later step.


## Hooking up the local model

LM Studio is already running Qwen2.5-VL-3B at `http://127.0.0.1:1234/v1`.
The connection is `ChatCompletionsClient(endpoint: .localVision)`; the new controller is
`TechnicalAssist.propose(neutralJPEG:base:stats:client:)`. Supply a <=512 px neutral
RAW render from Lumina, never a camera preview, and review the actual rendered result.
It returns a decision and does not mutate the session. `applyTechnicalPolicy(to:)` is
the separate explicit, undoable deterministic path.

To restore the existing local setup after restarting LM Studio:

```sh
lms ps
lms load qwen2.5-vl-3b-instruct --context-length 4096 --parallel 2 --yes
lms server start --bind 127.0.0.1 --port 1234
```

Check `lms ps` first; do not reload or unload a model another task is using.
The model name can be selected with `LUMINA_AUTO_MODEL`; endpoints must remain loopback.
For XCTest, the supplied runner writes these values into the generated `.xctestrun`
environment. A bare shell environment variable is not reliable for the hosted test app.
Use `run_technical.py --live` to invoke the new controller and `--legacy-model` only
when deliberately diagnosing the older slider-vector model. No hosted endpoint or key
is needed or authorized. A production UI hook is deferred because this model has not
passed the promotion gate.
