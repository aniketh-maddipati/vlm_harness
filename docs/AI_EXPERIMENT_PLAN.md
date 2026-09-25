# Lumina: AI opportunities and a reproducible experiment plan

Planning note · 2026-09-24 · inspected combined UI plus workbench source. This is a research backlog, not a claim that models are trained, deployed, or preferred by users. Navigation and Auto geometry protection subsequently landed through PR #111. Conservative exposure changes and the experiment plan remain local work pending visual acceptance.

## Recommendation

Invest first in **better bounded Auto tone proposals and learning which proposal a photographer prefers**. Reuse the renderer, recipe controls, deterministic baseline and existing measurements. Compare a small predictor and retrieval against a vision-language model before fine-tuning one. Build a reusable evaluation set before adding a spectrum of looks to the UI. AI should shorten the path to a good starting point; it should not introduce surprise rotation, unexplained edits, or waiting during scrolling.

Keep one reliable Auto action initially. Research three *internal* candidates (conservative, standard, stronger correction) plus the unedited original. These are experimental conditions, not committed product names. Expose alternatives only if they reliably improve decisions without increasing comparison time. Do not infer a desire for warmer color from a request for stronger tone correction.

## Existing foundations and gaps

| Surface | Actual code available | Implication for experiments |
| --- | --- | --- |
| Deterministic Auto | `Lumina/Develop/AutoDevelop.swift`; current Elastic version actions call this path | Mandatory reproducible baseline. The presence of model code does not mean the visible Auto button uses it. |
| Bounded model proposal | `Lumina/Develop/ModelAutoDevelop.swift`, `P0SessionModel+Model.swift` | Optional tone fields, finite-number parsing, clamps, deterministic fallback and statistic-echo rejection already exist. Audit activation and request ownership before reusing. |
| Tone envelope | `ModelAutoDevelop.Band` | Current exposure −1…1 EV, contrast −25…25, highlights −60…10, shadows −10…50, vibrance −10…25, saturation −15…15; exposure quantized to 0.05 EV. These are guardrails, not proven aesthetic optima. |
| Geometry / WB | `EditRecipe`, `AutoDevelop`, model bounding | Preserve crop, orientation and existing WB. Model WB proposal fields exist but bounding deliberately ignores them. Geometry preservation landed through PR #111 after reported surprise rotation; conservative exposure policy is documented separately. |
| Image statistics | `ImageStats`, prepared RAW measurement | Can support cheap tone prediction. Verify measurement image, transfer function and camera identity; preview pixels and RAW measurements are not interchangeable. |
| Visual similarity | `Lumina/Services/EmbeddingService.swift` | Vision feature prints with histogram fallback already exist. Never mix embedding versions or fallback spaces as though their distances were calibrated. |
| Taste retrieval | `Lumina/Services/TasteIndex.swift`, `TasteRetriever`, legacy `ProjectViewModel` | Existing nearest-neighbor recipe transfer is a baseline, not a proven current P0 personalization system. `DevelopRecipe` and `EditRecipe` require explicit, tested conversion. |
| Rendering / export | `DevelopRenderGraph`, authoritative export service | All judged candidates must render through the same production graph and frozen recipe. Do not judge a generative replacement image as an editable recipe. |
| Ownership / diagnostics | Auto request identities, recipe fingerprints, latency metrics, performance recorder | Reuse cancellation, stale-result rejection and measurement infrastructure. Add experiment instrumentation off the critical interaction path. |

## Priority and feature boundaries

| Priority | Opportunity | First experiment | Success evidence | What remains deterministic |
| --- | --- | --- | --- | --- |
| P0 | Better Auto tone | Measured statistics → bounded six-control recipe; compare regression, retrieval and VLM proposals | Blind preference over current Auto; fewer corrective edits; no increase in serious artifacts | Bounds, WB/geometry, source identity, undo, persistence, export |
| P0 | Pick a useful Auto strength | Rank three bounded candidates from the same source | Better first-choice acceptance and lower time to satisfactory result | Candidate construction, user choice, exact recipe replay |
| P1 | Personal taste | Retrieve accepted examples; then train a small preference head if retrieval plateaus | Held-out future shoots improve for that person without degrading cold start | Explicit preference storage, reset, fallback; no inference of personal traits |
| P1 | Burst representatives | Rank within existing bursts using sharpness, eye state, exposure and optional learned features | Photographer's preferred frame in top-k; lower review time; retain intentional motion | No auto-delete, no irreversible reject, manual override |
| P1 | Group boundaries | Compare time/metadata baseline against time plus visual features | Boundary precision/recall plus human split/merge effort | Stable IDs, capture chronology, manual order, viewport behavior |
| P2 | Consistent set treatment | Predict scene-conditioned tone deltas across an approved group | Less visible discontinuity without flattening intentional lighting changes | Scope freeze, hand-edit protection, one undo, no blind copying of exposure |
| P2 | Search / labels | Local embeddings or bounded descriptors | Retrieval relevance and task completion, measured on actual library queries | File access, source truth, metadata provenance |
| P2 | Explain suggestions | Short explanations grounded in measured inputs and applied controls | Factual accuracy and usefulness; explanations agree with recipe | Error receipts, export counts, filenames and recovery actions |
| Later | White-balance assistance | Separate mixed-light / neutral-reference study | Skin and neutral fidelity across cameras and intentional warm scenes | WB remains separate from tone Auto until justified |

**Do not use a model to fix** scroll fluidity, high-speed image folding, chronology navigation, build identity, hot reload, cancellation, export recovery, or filesystem permissions. These need deterministic engineering and native acceptance. Do not interpret the user's report of folding as evidence of a model problem. Crop/straighten suggestions, if ever explored, must be explicitly separate from tone Auto.

## Dataset: collect decisions, not just attractive pictures

The 500-file `card-clean-500` fixture is useful for reproducible UI/performance checks. It is not automatically a diverse training set or an independent aesthetic test set. Audit provenance, duplicates and coverage first.

Record each example as an immutable source plus decision context:

- Asset content hash; shoot, burst and photographer pseudonymous IDs; RAW/JPEG pairing; camera/lens/ISO; capture metadata quality; image orientation; decode and color profile versions.
- Base recipe and provenance; all candidate recipes; candidate render hashes; model, prompt, schema and renderer versions; measurements and their input hashes. Explicitly distinguish absolute control values from residual deltas.
- Randomized presentation order; chosen candidate, tie, neither acceptable, or no decision; final manual recipe; edit sequence and elapsed active editing time. An undo may mean comparison or exploration: do not label it a dislike without context.
- Human issue labels: too dark/bright, clipped highlights, crushed shadow detail, oversaturation, skin shift, inconsistent group, unwanted geometry change. Permit multiple acceptable outcomes.
- Data rights, permitted uses, retention and whether offline training / external processing is allowed. Keep local paths and identity mapping separate from portable training records. No automatic photo upload is authorized by this note.

Preserve originals; write candidates and labels to a durable experiment directory under `~/LuminaEvidence/ai-experiments/<experiment-id>/` or an explicitly selected data volume. Store source code, manifests and small summaries in Git; keep images, weights and full logs outside Git. Avoid `/private/tmp` as the only evidence location.

## Splits and leakage controls

1. Deduplicate before splitting, including RAW/JPEG pairs, near-identical bursts, resized copies and exported derivatives. Keep an entire shoot/event and its derivatives in one split.
2. Hold out future shoots. Include camera and scene holdouts; for a general model also hold out photographers. Report personalized evaluation separately: past preferences may train, future shoots test.
3. Freeze a validation set for tuning and a sealed final test set. Do not use final-test preferences to choose prompts, bands or checkpoints. Retrieval examples must come only from the allowed training partition.
4. Stratify difficult cases: high ISO, backlighting, mixed light, intentional silhouettes, diverse skin tones, monochrome, saturated lighting, under/overexposure and missing metadata. Report each slice, not only a global average.
5. Treat a shoot or photographer as the resampling unit for uncertainty estimates; thousands of correlated burst frames are not thousands of independent judgments.

Public data can bootstrap experiments but does not establish product fitness. MIT-Adobe FiveK has 5,000 RAW photographs with renditions from five photographers, useful for studying multiple acceptable interpretations; inspect current usage terms before acquiring or redistributing it. Cross-renderer recipe values are not interchangeable labels. [FiveK paper](https://people.csail.mit.edu/vladb/photoadjust/db_imageadjust.pdf). The related [acceptable-adjustment dataset](https://projects.csail.mit.edu/acceptable-adj/data.html) motivates learning acceptable ranges rather than one exact target.

## Experiment ladder

| ID | Hypothesis and controlled comparison | Training / tuning | Decision |
| --- | --- | --- | --- |
| A00 | Current Auto improves on as-shot for intended users | None; capture baseline and failure slices | If not, improve baseline and labels before model complexity |
| A01 | A small set of deterministic strengths covers most preference variation | Freeze three bounded variants, preserve geometry/WB | Keep variants internal unless decision speed improves |
| A02 | Statistics predict better tone than fixed rules | Regularized regression or small tree/MLP; same six controls and bounds | Cheapest candidate that beats A00 on held-out shoots |
| A03 | Frozen visual features add useful scene information | Same head and data as A02, add versioned embeddings | Require improvement beyond stats-only model |
| A04 | Retrieval of accepted examples matches taste | No fine-tuning; compare global and personal libraries | Prefer retrieval if competitive and easy to reset |
| A05 | A VLM provides useful proposals beyond A03/A04 | Frozen prompt and structured output; offline local inference first | Count invalid/echo/fallback rates and latency; judge rendered outputs |
| A06 | A small student retains teacher gains | Distill only human-approved teacher candidates into bounded predictor | Teacher agreement alone is insufficient; repeat human evaluation |
| A07 | Preference training selects the right bounded candidate | Pairwise ranker over candidates; compare with fixed standard | Optimize selection before expanding generator capacity |
| A08 | VLM fine-tuning improves failures that prompting cannot | Small adapter/LoRA only after data and baseline evidence justify it | Stop if gains disappear on new cameras/shoots or cost dominates |
| G01 | Visual features improve grouping beyond time metadata | Ablate time-only, vision-only, combined | Human correction effort plus boundary metrics |
| B01 | Learned burst ranker helps photographers choose | Compare technical-score baseline with small ranker | Top-k preferred-frame recall and review time; no automatic deletion |

For A02–A08, change one major factor at a time. Freeze decode resolution, color pipeline, prompt, bounds and candidate budget unless that factor is being tested. Use at least three training seeds for finalists when stochastic training matters; do not multiply an arbitrary full hyperparameter grid. Start with learning curves (for example 100, 300, 1,000 independently sourced labeled examples, when available), then decide whether more data or a different model is needed. These counts are planning checkpoints, not a statistical guarantee or a claim that the data exists.

Fine-tuning targets must match serving semantics. Supervised recipe prediction uses typed, finite controls with clear units and missing-field meaning. Preference training learns a ranker from explicit choices; do not equate it automatically with language-model DPO. A generative image-editing model changes the problem and is out of scope for the initial recipe experiments.

## Evaluation and promotion

Pre-register a primary outcome per experiment: blind pairwise preference against the incumbent, or active time to an acceptable edit. Randomize left/right and candidate order; include ties, neither and as-shot. Evaluators should not see model names. Report number of photographers, independent shoots, photographs and judgments separately, with clustered uncertainty intervals.

Secondary measures: acceptance without further adjustment; size and number of corrective edits; severe failure rate; group consistency; invalid outputs; fallback frequency; cold/warm latency distributions; peak memory, energy and model footprint. Pixel similarity / PSNR to one editor's output is insufficient. Aesthetic scores can be auxiliary signals, not the acceptance oracle; [NIMA](https://arxiv.org/abs/1709.05424) is a relevant research baseline, not evidence that it measures this photographer's intent.

Hard invariants: zero unexpected geometry or WB changes in tone-only Auto; no stale proposal applied after focus/shoot/recipe changes; exact undo; valid bounds; deterministic fallback; originals preserved; production preview/export recipe parity. Verify these in tests. Measure perceived fluidity and folding separately on the native app; an aesthetic win does not waive interaction regressions.

Before a run, choose a minimum practical preference improvement, tolerated severe-failure rate and latency budget using product needs and baseline data. Size the study using pilot variance and desired power; do not pick a winning threshold after seeing test results. Promote only when the primary result is credible, worst-case slices are acceptable and deployment fits the device budget. Otherwise keep the simpler incumbent and retain the negative result.

## Serving architecture if an experiment wins

`frozen source + base recipe + measurements → proposal → typed validation → bounded recipe → production preview → user acceptance → one owned commit`

Inference must be cancellable, bounded in concurrency and outside the scrolling/render presentation path. Key cached results by source content, base recipe, model/adapter, preprocessing and schema versions. Apply only if request identity and current context still match. Timeouts, malformed values, unavailable models and low-confidence cases return the deterministic recipe. A numeric confidence field is not calibrated merely because a model emits it.

Prefer an offline small model for the common path; use any heavier teacher during authorized research. This note adds no app networking and does not override the repository's network restriction. Core ML supports personalization for supported updatable models, but that is not a promise that an arbitrary fine-tuned VLM can train on-device; validate conversion, operators, quantization and hardware before committing. [Apple model personalization](https://developer.apple.com/documentation/coreml/model-personalization).

## Reproducibility packet per run

Manifest: experiment ID; hypothesis; owner; parent baseline; Git SHA and dirty-patch hash; dataset/split hash; consent scope; preprocessing and renderer versions; seeds; model/adapter and tokenizer hashes; prompt/schema; hyperparameters; machine/OS; wall time; resource budget and stopping rule. Keep immutable prediction rows, bounded recipes, rendered candidate references, human labels, per-slice metrics, exceptions and a signed-off decision note together. Never describe a prompt change as fine-tuning.

Use a small experiment registry with states `planned`, `running`, `complete`, `rejected`, `promoted`. Every promoted candidate must point to the evaluation packet and a rollback baseline. Store failed experiments too: repeated negative results are useful constraints on the next feature.

## First implementation batches

1. Finish baseline Auto geometry protection and native interaction verification. Freeze the current renderer and incumbent results.
2. Add an offline candidate/label export harness around existing recipes and rendering; define splits and an explicit preference collection flow. Do not add another live UI mode yet.
3. Run A00/A01 and label failure slices. Try A02/A04 before paying for broad VLM sweeps.
4. Run A03/A05 only where the cheaper baselines fail. Use approved examples for A06/A07; reserve A08 for a demonstrated data/model gap.
5. Promote one feature at a time behind a reversible development flag. Ship the simplest winning behavior; keep training and evaluation tools separate from the shipping app.

This sequence expedites features by reusing bounded recipes and shared evidence, while avoiding multiple new UI controls and model infrastructure before there is evidence they help.
