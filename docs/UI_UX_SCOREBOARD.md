# UI/UX command-center scoreboard

Documentation snapshot: 2026-09-23. Baseline source **`a6923588dfe3824f3b84556bbcac3d93d8f67876`** (PR #107); initial ledger copied from `codex/ui-ux-command-center`, updated only in Prompt 0's assigned worktree. Candidate code **`0725f80c2c7614e52b69d26112696ac008c472c9`** passes two cache-free rounds and current 45/45 graph parity. This is an evidence ledger, **not a frozen acceptance baseline**. No overall completion percentage is meaningful.

## Current diagnostic addendum

Prompt 0 implementation and assertion audit: [0-baseline-handoff](0-baseline-handoff.md).
The bounded selected-image trace and truthful callback/reload labels are implemented;
UX02 remains PARTIAL until current native and complete assertion coverage are verified.
No P-row receives acceptance from instrumentation plumbing or the inherited trace.
Current verification, durable photograph PNGs, invalid-video evidence and ownership
release are recorded in the handoff. The candidate still reproduces the Canvas
quarter-turn fallback defect; graph parity cannot clear UX03.

An isolated standalone Release build at the baseline SHA completed. Bundle
`com.lumina.uiuxp0`, PID 31412, binary SHA-256
`a3216711273f560cf16812ca976fa78b56e65b833a22ff77e83d3a44a04bf4eb`.
[Identity and eight copied RAW hashes](/private/tmp/lumina-ui-ux-evidence/p0/identity.json).
The worker verified native chooser → Canvas with actual photo pixels,
24 exposure/WB pointer drags, and 12 navigation actions. These add limited
current evidence to UX01/UX11/UX16; all remain PARTIAL pending their full matrices.

Valid diagnostic Time Profiler artifacts:
[open/Canvas](/private/tmp/lumina-ui-ux-evidence/p0/open-canvas.trace) and
[scrub/navigation](/private/tmp/lumina-ui-ux-evidence/p0/scrub-valid.trace).
The separate `scrub-navigation.trace` is INVALID due overlapping kperf recording;
exclude it. [Final telemetry](/private/tmp/lumina-ui-ux-evidence/p0/metrics-final.json)
has no input/recipe/presented-frame correlation. No P-row latency acceptance,
six-interaction coverage, real trackpad pass, human comfort score, or memory
acceptance follows from this diagnostic. PID 31412 exited before lease transfer.

Authority: [contract v6](../design/contract-v6.md) → [tokens](../design/tokens.yaml) → [copy](../design/copy-contract.txt) → code → tests, with explicit later product rulings reconciled by chronology. [Supplied roadmap](/Users/aniketh/.codex/attachments/34dae09b-d2f9-4fc9-b104-b7fe5ea6e372/Pasted%20text.txt) §9 supersedes contradictory earlier critique/status/budget wording; new numeric thresholds below remain **proposals**, not ratified or achieved gates. Stronger existing requirements prevail. Execution order: **0 → 1 → 6A → 2 → 3 → 4 → 5 → 6B → 7 → 8**. Own shared UI/session files sequentially.

Statuses describe the full row's known scope: **PASS** fully evidenced within declared scope; **FAIL** observed violation/absence, with observation revision stated; **PARTIAL** scoped success with outstanding coverage; **UNMEASURED** no accepted proof; **BLOCKED** a specific missing prerequisite prevents verification; **DEFERRED** explicitly later scope. Historical FAIL is an unresolved reported defect, not a new reproduction at baseline. Historical success never becomes a current PASS by inheritance alone. Human beta outcomes remain UNMEASURED; optional agent work remains DEFERRED.

## Evidence keys and provenance

| Key | Evidence, scope and limitation |
|---|---|
| **S** | Baseline source above; roadmap §9's static reconciliation, not runtime. RAW mirror/WB fix, recipe-aware cache keys, debounce/cancellation, display link and opt-in drawable acknowledgement already exist. Final selected-image identity and drawable-acquisition span remain gaps. |
| **U** | [Native UI report](UI_CHECK_REPORT.md), source **`2da465901cfb59fac9d5fa98c11472331ab1f26a`**, clean Debug build, unique `com.lumina.uicheck` bundle, eight cloned Sony RAWs. Exact executable/PIDs, fixture paths and captured manifest are in report. [Private capture manifest](/Users/aniketh/.codex/visualizations/2026/09/23/01a0cf69-9da8-7ff0-b2dc-504518731658/ui-check/evidence-manifest.json). Runtime findings are historical relative to baseline; no newer native correction proof supplied. |
| **I** | [Instrumentation baseline](perf/product-performance-baseline.md). PR #107 supplies opt-in recording and drawable acknowledgement, **not** recipe-correlated presentation latency. Reported 510 logic tests/four skips and FAST 41/41 validate plumbing at that checkpoint; no new test pass here. Recording arrays are unbounded and repeatedly serialized; memory/observer effects need separation. |
| **R** | [RAW parity report](RAW_PREVIEW_EXPORT_PARITY.md), correction `c3f2a89`, integrated through PR #104 at **`a3b7fe751dca3bdffac91015c60a8ecf7c7e9ed2`**; preserve its private run manifest for exact measured binary/source hashes, not the later merge as a fictitious runtime SHA. 45/45 measured graph cases, full-export mean CIE76 ΔE 0.6921, worst 0.8945, each ≤1.5. Graph-only; actual Canvas selection can still be wrong. |
| **H** | [Elastic history](ELASTIC_PLAN.md): dated/commit-scoped run entries, including 403-frame warm scripted zero wells and flick tick p95 8.84 ms. Not actual-frame latency or a fresh baseline. Preserve individual entry provenance; where no exact measured SHA/binary is supplied, record null rather than invent one. |
| **Q** | Roadmap's attributed 109-frame reference-edit run: neutral 10.71, Auto 11.70, model 33.32 edited-frame ΔE. Exact run SHA/binary not supplied here; historical only, never a human-preference or final-tree result. |
| **N** | No accepted measurement in U/I/roadmap for the complete row. Evidence gap, not zero events or zero failures. Founder-reported lag is an observed experience problem even though timing attribution is N. |

## Gate conflicts and preserved requirements

| Area / affected IDs | Decision for implementation and acceptance |
|---|---|
| Startup, UX17/P14 | [v5 D36](../design/contract-v5.md) says “Opens silently <1 s”; v6 D36's rejects-endgame amendment does not explicitly withdraw that clause. Preserve **<1 s opening requirement**; M0 must define its boundary versus process→home and folder→viewport. Proposed P14 p95 ≤1 s is not automatically equivalent; ≤2/5 s viewport budgets do not replace it. |
| Edit/travel, UX27–28/P01/P03–05/P09 | [P0_EDITING historical target table](P0_EDITING.md#live-harness-on-sony-arw-dsc08241arw-debug-2026-08-06--historical) includes **slider→pixels p95 <16 ms, settled <150 ms, cached neighbor navigation <35 ms**. [DEVELOP_ENGINE](DEVELOP_ENGINE.md#performance-targets-measure-on-mac--not-claimed) uses cached present ≤50, settle ≤300, warmed switch ≤80, Before/After ≤50 and 1:1 ≤250 ms. Historical table and measurement-boundary differences do not ratify relaxation. Carry tighter legacy targets as unresolved constraints; M0 must document authority and same-boundary applicability before claiming acceptance at 50/300/80. No new contract is declared here. |
| Scroll/travel, UX26–27/P02/P06 | [LatencyMetrics](../Lumina/Services/LatencyMetrics.swift) declares proposed 8.33 ms scroll and 50 ms travel/mark/zoom budgets; its comments explicitly say unratified. Retain existing harness gates under their actual tick/display-link semantics; do not equate them to presented frames. §9 uses actual refresh intervals: >2T in <1% of active opportunities, **no >100 ms warm scroll gap**. P02's 250 ms catastrophic guard cannot weaken scroll's 100 ms guard. |
| Geometry, UX03–06 | Preserve inherited 45-case **≤1.5 ΔE per case** graph gate plus actual view/export proof. Same-recipe promotion has no intentional layout shift, **≤1 physical pixel measurement tolerance** (§9); intentional crop/rotation changes are excluded. Preserve intermediate gate; demonstrate delayed-authoritative presentation and report legitimate fast-path skips separately. |
| Memory, UX29/P10 | [PhotoImageCacheBudget](../Lumina/Services/PhotoImageCacheBudget.swift): 48/96/128 MiB tier ceilings, 256 MiB combined LRU, separate 64 MiB floor; W6 values explicitly await contract ruling. Preserve scoped implementation gates; these do **not** cap whole-process RSS/footprint, RAW/Metal/model resources. Workload/hardware absolute process caps remain TBD; a 10% plateau alone cannot PASS. No arbitrary 3 GB replacement. |
| Persistence/recovery, UX18–20/P07–08 | [v5 D35](../design/contract-v5.md), [v6](../design/contract-v6.md) and [canonical authority](P0_CANONICAL_STATE.md) preserve continuously saved decisions, truthful retained assets/recovery and no silent conflict overwrite. Faster acknowledgement cannot trade away durability. “Progress” does not authorize banned progress bars/spinners/modals. |
| Grammar/accessibility/beta, UX09/12–15/21–22/33–38 | Preserve crop/off-center and keyboard alternatives; reconcile later [Elastic rulings](ELASTIC_PLAN.md) (including range/toggle and Esc) before using old tests. v6 D66 requires notarized Developer ID beta, not obsolete TestFlight; D45 zero diagnostics egress remains; D67 permits only sanctioned loopback model inference. No optional experiment or roadmap wording authorizes broader network access, distribution, or tester messages. |

## Photo workflow ledger

All acceptance counts below are future requirements unless evidence explicitly says measured. Owner is **prompt / milestone**. Linked evidence keys resolve to the provenance table above.

| ID | Owner / stage | Status | Criterion (proposed numeric gates unless inherited above) | Actual evidence and remaining scope |
|---|---|---|---|---|
| UX01 | 0 / M0 | PARTIAL | 100% run source/binary/bundle/PID identity; zero wrong-window actions | [Prompt 0](0-baseline-handoff.md) pins baseline Release and candidate standalone Debug, patch/binary/fixture hashes, native PID59671/window11474 and harness PID60837. Full configuration matrix remains unmeasured. |
| UX02 | 0 / M0 | PARTIAL | Every named pass asserts its behavior; skips excluded; no uncorrelated latency passes | [Prompt 0](0-baseline-handoff.md) audits all 53 and corrects callback/reload/publication labels. Candidate smoke 51/53: navigation now fails on blankAfterWait=true; intermediate publication unsampled. No latency acceptance or readiness percentage. |
| UX03 | 1 / M1a | FAIL | Zero wrong geometry: all quarter-turns, centered/off-center crops, portrait/landscape/square; retain R gate | [Prompt 0](0-baseline-handoff.md) reproduces 270° mismatch with native pixels. [Packet 1](1-display-handoff.md) implements intended-recipe selection and passes production-selector regressions; native correction/export agreement remains unverified. Historical [U U1](UI_CHECK_REPORT.md#u1--p1-intended-rotationcrop-can-be-hidden-by-browse-fallback) includes correct 90° TIFF. |
| UX04 | 1 / M1a | PARTIAL | 500 controlled transitions/run; zero wrong assets/new superseded promotions; bounded age of retained valid frame | [Packet 1](1-display-handoff.md) adds post-await request ownership, selected-frame asset/recipe/generation checks and same-asset retention. No three-run native 500-transition proof; source guards do not establish zero transient failures. |
| UX05 | 1 / M1a | FAIL | No blank after valid preview; unchanged recipe edges ≤1 physical pixel at 1×/2× | Historical [U U3](UI_CHECK_REPORT.md#u3--p2-promotion-box-shifts-and-intermediate-tier-not-observed): box [28,61.5,1064,711]→[28,62.5,1064,709]. [Packet 1](1-display-handoff.md) retains same-geometry layout size; actual 1×/2× photograph edges and blank-free transitions remain unverified. |
| UX06 | 1 / M1a | FAIL | Delayed-authoritative case presents intermediate; fast-ready final skips separately labelled; preserve gate | Historical [U U3](UI_CHECK_REPORT.md#u3--p2-promotion-box-shifts-and-intermediate-tier-not-observed): ranks [0,0,0,0,0,2]. [Packet 1](1-display-handoff.md) adds bounded Debug-only uncached authoritative delay; actual intermediate presentation is still unmeasured. |
| UX07 | 2 / M2 | FAIL | Own-recipe tiles; zero wrong-version tiles/100 switches; unavailable explicit | [U U4](UI_CHECK_REPORT.md#u4--p2-incomplete-controls-and-accessibility), S: Auto/Yours deliberately return no preview path. |
| UX08 | 2 / M2 | PARTIAL | Zero edit loss/100 switches plus undo/reopen; Before changes no durable state | [U](UI_CHECK_REPORT.md): sampled shot/yours and hand recipe restoration passed; 100-switch and full async coverage absent. |
| UX09 | 3 / M2 | FAIL | Off-center placement; exact apply/cancel/reset/undo/reopen/export; ≥6 geometry cases, pointer and keyboard/numeric | [U U4](UI_CHECK_REPORT.md#u4--p2-incomplete-controls-and-accessibility): native off-center path absent; graph crop support is not native interaction proof. |
| UX10 | 2 / M2 | FAIL | Cull/edit/batch/order exact redo; new mutation clears redo; 20 native mixed sequences | [U U4](UI_CHECK_REPORT.md#u4--p2-incomplete-controls-and-accessibility): redo absent; sampled edit undo preserves cull only. |
| UX11 | 3 / M2 | PARTIAL | Every visible control: pointer/keyboard/value/range/reset/engine effect; honest unavailable state | [U](UI_CHECK_REPORT.md): callback sliders passed; pointer automation failed; no claim that human dragging itself is broken. |
| UX12 | 3 / M2 | UNMEASURED | 100% advertised shortcuts; no photo actions while typing; repeat/key-up/deactivation/Esc matrix | [H](ELASTIC_PLAN.md) key-routing work and U sampled keys do not cover current full grammar. |
| UX13 | 3 / M2 | FAIL | Unique actionable leaf names/roles/values; keyboard-complete workflow, no traps; VoiceOver | [U U4](UI_CHECK_REPORT.md#u4--p2-incomplete-controls-and-accessibility): nine sliders merged into one AX value; parent identifiers overwrite leaves. |
| UX14 | 3 / M2 | UNMEASURED | No selection from travel; targets/counts accurate; range/toggle/batch/undo matrix | [U](UI_CHECK_REPORT.md) pointer multiselect unmeasured; use current approved Elastic selection grammar. |
| UX15 | 3 / M2 | UNMEASURED | Peek/Before/clipping open/cycle/pin/exit; 30 hold/release cycles restore exact state | [H](ELASTIC_PLAN.md) implementation history; U sampled Before is not full transient/input parity proof. |
| UX16 | 4 / M3 | PARTIAL | Chooser/drop/Recent/empty all succeed or explain; cancel retains session | [U](UI_CHECK_REPORT.md): normal open attempt, recovered workbench and Recent/reopen sampled; full clean-entry matrix absent. |
| UX17 | 4 / M3 | UNMEASURED | 403-frame usable viewport p95 ≤2 s warm/≤5 s app-cold; truthful progress; preserve startup conflict | [I](perf/product-performance-baseline.md): no accepted open timing; SD separately, app-cold ≠ disk-cold. |
| UX18 | 4 / M3 | FAIL | Missing/corrupt/denied/offline visibly explained even with cached pixels; zero asset loss; useful recovery | [U U2](UI_CHECK_REPORT.md#u2--p2-missing-source-state-is-invisible-while-cached-photo-remains): retained 8/8 assets, catalog missing flag; cached Canvas hides missing-source notice. |
| UX19 | 4 / M3 | FAIL | Empty guidance plus usable action; 5/5 scripted recoveries and AX activation | [U U5](UI_CHECK_REPORT.md#u5--p3-empty-folder-offers-little-guidance): empty gray table, no body recovery action; Home shortcut worked. |
| UX20 | 4 / M3 | PARTIAL | 20 reopen/recovery cycles, no lost/phantom marks/edits/order; external conflict never silently overwrites | [U](UI_CHECK_REPORT.md): sampled marks, hand recipe, geometry persist; interruption/conflict/20-cycle proof absent. |
| UX21 | 4 / M3 | UNMEASURED | No grouping identity loss/duplicates; cross-volume same basename; ≥4/5 explain rows unaided | [H](ELASTIC_PLAN.md) grouping history; two-shoot and real cold participant evidence absent. |
| UX22 | 4 / M3 | UNMEASURED | 20 add/remove/reorder sequences; exact undo/reopen/export order; audit current drop paths | [H](ELASTIC_PLAN.md) set implementation history; full end-to-end sequence evidence absent. |
| UX23 | 5 / M3 | PARTIAL | ≥20-photo mixed batch; selected = outputs + explicit failures; dimensions/orientation/profile/order; no overwrite | [U](UI_CHECK_REPORT.md): one 4000×6000 rotated ROMM RGB TIFF correct; Canvas agreement FAIL; batch accounting unmeasured. |
| UX24 | 5 / M3 | UNMEASURED | Cancel/denied/capacity failures never claim success; retry retains successful outputs | [U](UI_CHECK_REPORT.md), N: successful single file does not prove transactional recovery. |
| UX25 | 5 / M3 | UNMEASURED | One validated photo-essay JPEG flow, truthful settings/destination/reveal; verify any named platform spec | [U](UI_CHECK_REPORT.md), N: only TIFF sampled. |
| UX26 | 6A,6B / M1b,M4 | UNMEASURED | Zero wells after preview floor; >2T gaps <1%; no >100 ms warm gap; 403/~2,000, real glide/flick/reverse/return | [H](ELASTIC_PLAN.md) 403 warm scripted zero wells, tick p95 8.84 ms; not native frame latency. U scroll tool unavailable; founder lag remains reported. |
| UX27 | 6A / M1b | UNMEASURED | Mark acknowledgment p95 ≤50 ms; correct warm travel ≤80 ms; ≥200/run ×3; tighter conflicts above | [I](perf/product-performance-baseline.md): no accepted input→correct selected frame timing. |
| UX28 | 6A / M1b | FAIL | Correct warm scrub ≤50 ms; last-input final settle ≤300 ms incl. debounce; Before ≤50, version ≤80; ≥200/run ×3 | Founder reports lag; timing N. [R](RAW_PREVIEW_EXPORT_PARITY.md): cold graph p95 278.04/warm 3.31 ms; eight version publications 127.41–172.74 ms are historical stage timings, not display p95. Preserve tighter conflicts. |
| UX29 | 6A,6B / M1b,M4 | UNMEASURED | No crash/OOM; minute20 footprint ≤110% minute5, 3 loops, 5 s samples; absolute caps required | [R](RAW_PREVIEW_EXPORT_PARITY.md): 57.38 s run peak RSS 1,064,501,248 B; footprint 4,847,766,120 B. No plateau/leak conclusion; P10 cap/reclaim absent. |
| UX30 | 6B / M4 | PARTIAL | No clipped primary actions/overlap/unintended scroll at 1280×800/1440×900, long names, scale; UX05 | [U](UI_CHECK_REPORT.md) native stills scoped; promotion shift FAIL; reference HTML render blocked and full layout matrix absent. |
| UX31 | 6B / M4 | UNMEASURED | All primary keyboard paths; no precision-only critical task; founder 10-edit discomfort does not increase | [I](perf/product-performance-baseline.md), N: no accepted comfort session. |
| UX32 | 6B / M4 | UNMEASURED | ≥4/5 find edit/Before/undo/export unaided; state-truthful approved copy | [U](UI_CHECK_REPORT.md), N: no cold participants; no simulated ratings. |
| UX33 | 6B / M4 | UNMEASURED | Reduced-motion understandable; focus/selection distinguishable without color | [U](UI_CHECK_REPORT.md), N: no complete accessibility-settings walkthrough. |
| UX34 | 7 / M5 | UNMEASURED | 5/5 tester machines launch intended build/open folder without terminal; dependency recovery; v6 D66 | [Roadmap](/Users/aniketh/.codex/attachments/34dae09b-d2f9-4fc9-b104-b7fe5ea6e372/Pasted%20text.txt): August packaging findings historical; current fresh-machine acceptance absent. |
| UX35 | 7 / M5 | UNMEASURED | Founder 2 real shoots; ≥4/5 cold users complete folder→12-photo set→edit/order/export unaided | [I](perf/product-performance-baseline.md): dogfood not armed; no sessions or participant scores invented. |
| UX36 | 7 / M5 | UNMEASURED | Matched/counterbalanced median active time ≤usual tool; zero loss/mismatch; ≥4/5 confidence ≥4/5 | [U](UI_CHECK_REPORT.md) known display mismatch blocks readiness; human comparison N. Five people are formative evidence. |
| UX37 | 8 / M6 | DEFERRED | Visible scope/change; cancel zero commits; stale refused; batch once/one undo; timeout/concurrent edit/fallback | [Roadmap](/Users/aniketh/.codex/attachments/34dae09b-d2f9-4fc9-b104-b7fe5ea6e372/Pasted%20text.txt): backend scoped evidence only, native approval loop unmeasured; after display/version/undo trust gates. |
| UX38 | 8 / M6 | DEFERRED | 30 held-out frames/≥3 events; blind accept/tie/reject/severe failures; original candidate; prohibited geometry/content unchanged | Q historical ΔE is not preference. Latest-tree blind human evaluation absent; optional experiment does not block manual beta. |

## Performance ledger

All P rows are UNMEASURED: available historical numbers establish neither baseline presentation latency nor accepted memory/energy outcomes. §9 boundaries and preserved conflicts above apply to every row, including background conditions.

| ID | Owner / stage | Status | Proposed criterion and required observation | Actual evidence / gap |
|---|---|---|---|---|
| P01 | 0,6A / M0,M1b | UNMEASURED | Control acknowledgment p95 ≤33 ms; matching warm photo ≤50; last-input exact settle ≤300 incl. debounce, release separate; identity/quality/dimensions | [I](perf/product-performance-baseline.md): drawable acknowledgment lacks requested recipe/selected-image identity; three metrics must stay separate. |
| P02 | 6A / M1b | UNMEASURED | Warm p99 ≤100 ms with ≥1,000 actions/claimed interaction; no >250 ms active gap; >2T <1%; counts/max/hitch durations; UX26 scroll ≤100 ms | [H](ELASTIC_PLAN.md) tick history is not current frame pacing; no accepted tail distribution. Idle no-draw intervals excluded. |
| P03 | 6A / M1b | UNMEASURED | Latest-eligible bounded pending work; no growth/30 s scrub; settle ≤300; queue-wait p95, running/pending/discarded/cancel latency | S has debounce/lanes/generation checks already. Roadmap R1 Before/After bypasses lanes; contention unmeasured. High cancellation alone proves no defect. |
| P04 | 6A / M1b | UNMEASURED | Warm correct asset p95 ≤80 ms; app-cold local Canvas usable ≤500 ms, settled ≤1 s; soft duration/resolution | [I](perf/product-performance-baseline.md): no correlated freshness run. §9 supersedes unsplit 150/500 ms suggestion; prior asset/indefinite low-res cannot PASS. |
| P05 | 3,6A / M2,M1b | UNMEASURED | Supported 1:1 region ≤250 ms; warm pan/crop ≤50; final settle ≤300; exact sample/image coordinates and detail | [U](UI_CHECK_REPORT.md): off-center UI absent and pointer evidence missing; viewport transform alone insufficient. |
| P06 | 4,6A / M3,M1b | UNMEASURED | Selection/select-all/density p95 ≤50 ms on 403/~2,000; batch/undo progress ≤100; final duration; no focus resets from metadata | [H](ELASTIC_PLAN.md) history only; accepted complete batch timing absent. |
| P07 | 4,6A / M3,M1b | UNMEASURED | Mark/edit acknowledgment ≤50 ms during writes; durable p95/backlog; zero lost acknowledged actions on interruption; zero unchanged idle writes | [U](UI_CHECK_REPORT.md) sampled reopen is correctness only; concurrent I/O and durability timing absent. |
| P08 | 5,6B / M3,M4 | UNMEASURED | Progress/cancel acknowledgment ≤100 ms; no next item after observed cancel; fixed 20 JPEG/20 TIFF wall time, s/image, failures, footprint; regression ≤10% unless justified correctness | [U](UI_CHECK_REPORT.md) one TIFF has no throughput/recovery acceptance; noninterruptible encode must be named. |
| P09 | 6A,6B / M1b,M4 | UNMEASURED | Absolute latency gates plus ≤25% degradation vs idle under preparation/export/Auto separately; explicit tested scheduling if infeasible | [I](perf/product-performance-baseline.md) no controlled competition runs; background interference invalidates quiet-baseline claims. |
| P10 | 6A,6B / M1b,M4 | UNMEASURED | Ratify workload/host absolute peak/steady caps; ≥80% evictable bytes reclaimed ≤10 s; no live-resource growth/10 cycles; pressure recovery | [R](RAW_PREVIEW_EXPORT_PARITY.md) RSS/footprint snapshots; no cap/reclaim proof. Separate logical eviction, allocator retention, textures/caches/model/recorder. |
| P11 | 6B / M4 | UNMEASURED | After 60 s quiet: no decode/export/inference/unchanged writes; CPU median <2% of one core/60 s; minute20 vs5 latency ≤20% degradation | [I](perf/product-performance-baseline.md), N; power/thermal convention and independent observer overhead required. |
| P12 | 0,6A / M0,M1b | UNMEASURED | Same optimized build instrumentation on/off and recording on/off; median/p95 overhead ≤5% when resolvable; absolute delta/noise | [I](perf/product-performance-baseline.md): arrays unbounded/repeated serialization, so long capture cannot be assumed free. |
| P13 | 4,6B / M3,M4 | UNMEASURED | Internal SSD/T7/SD independently; connection/cache declarations; RAW/HEIC/JPEG/portrait/large image; same correctness/response gates | [I](perf/product-performance-baseline.md) disposable Sony copies; APFS clones/uncontrolled OS cache, repeated 2,000-card images. No fleet/storage extrapolation. |
| P14 | 0,6B / M0,M4 | UNMEASURED | Process→interactive home p95 ≤1 s; Recent viewport ≤2 s; app-cold local open ≤5 s; 10 starts/condition, ≥30 if unstable/release-critical | [I](perf/product-performance-baseline.md), N; retain v5 <1 s opening constraint; chooser think/OS-dialog time separately. |

## Run record and acceptance protocol

Store machine-readable run results **outside git**, following existing artifact policy. Required schema (all keys present; missing quantities use `null`, never manufactured zeros):

```json
{
  "id": "UX03",
  "status": "UNMEASURED",
  "source_sha": "a6923588dfe3824f3b84556bbcac3d93d8f67876",
  "binary_sha": null,
  "fixture_hash": null,
  "condition": "documentation-only; no runtime run",
  "expected": "Zero wrong-geometry cases at the actual Canvas selection boundary",
  "observed": null,
  "unit": "cases",
  "numerator": null,
  "denominator": null,
  "sample_count": null,
  "evidence_path": null,
  "blocker": "No native run for this source/binary/fixture combination",
  "owner": "prompt 1 / M1a",
  "verified_at": null
}
```

This is a schema example, **not a measurement and not a replacement for UX03's historical FAIL**. Allowed `status`: PASS / FAIL / PARTIAL / UNMEASURED / BLOCKED / DEFERRED. Preserve separate historical records under their actual SHA; a later report/merge SHA never substitutes for the measured source. Use a separate record per metric/condition where a row combines control, photo and settled results. Record fixture content/manifest hashes and actual binary hash in a real run; filenames alone do not freeze inputs.

Run metadata must include run ID, dirty state, binary path/bundle/PID, build configuration/debugger status, host/OS/Xcode, storage, display intervals/scale/window/backing size, power/thermal/model conditions, cache priming and capture settings. Native-input and direct-callback cohorts stay separate. Input timestamp precedes mutation; carry asset ID, recipe fingerprint, generation and quality through request/completion/publication/**actual selected image including fallback**/draw/drawable presentation. Record drawable acquisition separately; GPU completion and host presentation are distinct and neither is optical input-to-photon measurement.

Diagnostic work starts with 20–30 actions or one representative scrub and short trace. Acceptance uses ≥200 applicable short actions/run ×3, ≥1,000/interaction for p99; startup/export/endurance use their row-specific counts. Report per-run p50/p95/max, counts, failures, coalesced inputs, invalid/missing acknowledgements, presented-recipe age, continuous update gaps and exact final settle. Intentionally dropped inputs are counted but not assigned imaginary latency samples. Match before/after conditions and report noise; green timing cannot override wrong pixels, missing outputs, lost state or visible lag.

Memory acceptance: 20-minute fixed loop with 5-second RSS **and** physical-footprint samples; compare stable windows around minutes 5/20, three runs, plus caps/resource accounting/reclamation. Keep recorder allocations separate. Human results require actual sessions/recordings; if access later prevents execution, record the specific BLOCKED prerequisite without replacing missing observations with estimates. No human, runtime, or performance gate was newly passed by producing this ledger.
