# P8 — Surface sweep (strategy session)

**Branch:** `strategy/p8-surface-sweep` · **Base measured:** `origin/main` @ `a076644` (`docs: one-off queue after cascade`)  
**Session id:** P8.1  
**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests  
**Prior strategy (not on this branch):** `design/strategy/s1-mvp-sharpening.md` on `strategy/s1-mvp-sharpening` @ `ce677f6` (W4) — **UNMEASURED here**; existence/enforcement rows below are re-measured on `a076644` only.  
**Purpose:** Measure what exists on the integration tip, distinguish existence from enforcement (`constitution-coverage.md`), and order what remains for a wave-worthy build. **No code changes this session.**

---

## Measurement protocol

Every status below names the command or tree read that decided it. Claims not run on this host are **UNMEASURED**.

| Command / read | Result on `a076644` (Linux) |
|----------------|----------------------------|
| `git rev-parse --short HEAD` | `a076644` |
| `python3 Scripts/harness/run.py fast` | **INCOMPLETE** 5126ms · **26/27** orchestration · **0** app tests · FAIL: `banned_patterns`, `contract_v6_presence`, `spring_physics_f07`, `constitution_coverage` |
| `test -f Lumina/Design/LuminaSpring.swift` | **NO** |
| `test -f Scripts/harness/tests/test_f07_spring_physics.py` | **NO** |
| `rg 'place_return\|spring_dead_stop' design/tokens.yaml` | **no matches** (version `6.2-batch2`) |
| `rg -l MotionProbeLauncher Lumina/` | `Lumina/LuminaApp.swift` only — **no** `MotionProbeLauncher.swift` / `MotionProbeView.swift` in tree |
| `cat artifacts/harness/tokens.hash` | `c8f75e1a3733ee3209699deb0c2d418318a1b65ca47e46507a88929822c9c9a7` |
| `xcodebuild` / macOS XCUITest | **UNMEASURED** (no macOS host this session) |

**Branch divergence (not counted as shipped on main):** local `spike/b-motion` @ `cf583f8` has `LuminaSpring.swift`, F07 test module, `6.2-motion-seal`, F07.4–F07.6 **PASS** — **not merged** into `origin/main` at time of measurement.

---

## 1. Existence matrix (D / R)

**Legend:** **SHIPPED** = behavior or type on a reachable code path · **PARTIAL** = subset, legacy-only, headless-only, or copy/tokens without UI · **ABSENT** = no corroborating implementation · **SHELVED** = Shelved Register row; code must not expand without ruling · **BANKED** = contract gate (door, not deletion)

**Axis note:** `artifacts/harness/coverage/constitution-coverage.md` reports **30 covered / 7 shelved / 45 NOT-COVERED** (82 entries) — **enforcement** via named harness artifacts. This matrix reports **code existence** on the live P0 path vs legacy shell.

### D1–D40 (contract v5 carry + v6 amendments)

| ID | Title (abbrev.) | Existence | Evidence |
|----|-----------------|-----------|----------|
| **D1** | Table with photographs | **PARTIAL** | Live: `P0RootView` → `P0ContactSheetView` (grid contact sheet, not row/table). Legacy table: `ContinuousWorkspaceView`, `TableLayout`. |
| **D2** | Agentic-quiet | **PARTIAL** | P0 path has no AI/chat UI. Legacy arrangement: `EmbeddingService`, `PhotoAgentOrchestrator`, `TasteIndex` — not on `P0RootView` route. |
| **D3** | Arranges, never judges | **PARTIAL** | P0 cull user-driven: `P0SessionModel.applyCullToggle`. Legacy auto-cull: `PeerCullEngine` / `CullEngine`. |
| **D4** | Positioning copy | **ABSENT** | Tagline not wired in app chrome; design-only. |
| **D5** | Row loop edit→cull | **PARTIAL** | P0: cull on sheet + edit in `P0SinglePhotoEditor`; no row-scoped adapt/propagate on live path. |
| **D6** | Watched tidy | **PARTIAL** | Legacy: `ImportPipeline` → clustering. P0: `P0GroupingView` stub. `CopyContract.groupingVisibleMotion` sealed. |
| **D7** | Quantized spacing | **PARTIAL** | Tokens: `HiFiTokens.Grid.burstGap`, `sceneGap`. Legacy: `TableLayout`. P0 grid uses density columns, not burst/scene vocabulary. |
| **D8** | Five laws | **PARTIAL** | Headless: `CullGrammarMachine`, `CullGrammarTests.testHoldKeysTrackMomentaryState`. P0 partial (hold-B in editor). |
| **D9** | Holds vs latches | **PARTIAL** | Hold-B: `P0SinglePhotoEditor` key monitor. Crop/staging latches: legacy `LuminaShellModel` / `CropSession` only. |
| **D10** | P/X decide + advance | **PARTIAL** | P0: `P0ContactSheetView` P/X → `pressKeep`/`pressReject`; same-mark: `CullMutationCommand.resolveToggle` — **no focus advance** after mark on P0 (`P0SessionModel.applyCullToggle`). Headless advance: `CullGrammarMachine`. Legacy still routes `p,s,m,x` (`CommandHandlingModifier`). |
| **D11** | ⏎ doctrine | **PARTIAL** | Headless: `CullGrammarTests`, `CommandChordTests`. P0 Return opens inspection, not wholesale commit. |
| **D12** | ⇧/⌥ temperaments | **ABSENT** | No ⌥-fine rail detents on P0 live path. |
| **D13** | Release never commits | **SHIPPED** (logic) | `CullGrammarTests.testD11D13_*`, `CommandChordTests.testHeldReturnCannotDoubleCommit`. |
| **D14** | Halo propose→stage→commit | **PARTIAL** | Legacy: `LuminaShellModel` staging + `PropagationState`. **Absent on P0 live path.** |
| **D15** | Exceptions / Edited | **PARTIAL** | `ProjectViewModel.wholesaleExcludedPhotoIDs`, `PropagationState.excludedIDs`, `PropagationTests` — legacy shell. |
| **D16** | Adapt, never copy | **SHIPPED** (copy/logic) | `CopyContract.adaptBanner`; `copy_contract_diff` lint; `P0LogicTests.testA1FormatterSamplesInCopyContract`. |
| **D17** | Scope = row | **PARTIAL** | `PropagationState.ring` default `.row`, `PropagationTests`. Not exercised on P0. |
| **D18** | Four exposures + chips | **PARTIAL** | Fragments: `TreatmentFidelity`, `RecoveryFactsChip`. Not complete four-exposure grammar on P0. |
| **D19** | Count invariant + receipt | **SHIPPED** (logic) | `StagingCopySnapshot`, `P0LogicTests.testA1Invariant*`, `PropagationTests.testA1AtShootRingWithExclusions`. |
| **D20** | Fidelity contract | **PARTIAL** | `DevelopRenderGraph`, `PreviewSpine.Tier`, `StablePhotoView.Fidelity`. No full embedded→proxy→RAW chip ladder on P0; no in-shader histogram (SPIKE A gap). |
| **D21** | Truth-at-a-glance | **PARTIAL** | P0: 1:1 toggle, offline chip. **Hold-J ABSENT** (token: `HiFiTokens.Grammar.clippingGrammar`). Histogram: CPU `DevelopHistogram.compute`. |
| **D22** | Sharpness loupe/1:1 only | **PARTIAL** | `P0SinglePhotoEditor` 1:1; `DevelopRenderGraph.oneToOneRAW`. |
| **D23** | Ten controls + crop | **PARTIAL** | P0: `P0AdjustmentRail` (accordion, >10 fields). Legacy: `EditRailLayout.rowLabels` (10), `TreatmentStageView`, `CropSession`. |
| **D24** | Arming / value-echo | **PARTIAL** | Token: `HiFiTokens.Grammar.valueEcho`. Headless arming: `CullGrammarMachine`. No arming ring UI on P0 rail. |
| **D25** | Detents / slider anatomy | **PARTIAL** | `P0EditSlider` step ranges; thumb tokens in `HiFiTokens.Layout` not fully consumed on P0. |
| **D26** | Hero + strip + rail | **PARTIAL** | P0 layout: `P0SinglePhotoEditor`. Legacy: `TreatmentStageView`. |
| **D27** | Motion/fade law | **PARTIAL** | `LuminaTokens.Motion` ease curves; token `photo_birth` in yaml. **No owned spring on main** (`LuminaSpring.swift` absent). |
| **D28** | Elasticity exact-at-rest | **PARTIAL** | Token `HiFiTokens.Grid.elasticityStepsPx`. No `LuminaSpring` / motion probe on this tree. |
| **D29** | Multi-select | **SHELVED** | Register honored. **Legacy code remains:** `TableRubberBandOverlay`, `ContinuousWorkspaceView.twoUp`, `WorkbenchSelection.rubberBand`. |
| **D30** | Trackpad map | **ABSENT** | No pinch-density / glide on P0 path. |
| **D31** | Card-in import | **PARTIAL** | `IngestOrchestrator`, `ImportPipeline`; P0 folder drop `P0RootView.onDrop`. Not full card-stream UX on P0. |
| **D32** | Tier 0 / success test | **BANKED** (Tier 1) | Tier 1/A-ladder banked (D46). `AutoDevelop` partial; success test not instrumented. |
| **D33** | Within-shoot memory | **PARTIAL** | `ShootRecord.wholesaleExcludedPhotoIDs` via `ShootStore` / `ShootMigration`. |
| **D34** | Export = receipts | **PARTIAL** | `ExportService`, `ExportPayoffSheet` (legacy `ProjectViewModel`). P0 export count only; not full one-recipe inline CP8. |
| **D35** | Failure-mode law | **SHIPPED** (logic) | `P0StateTests`, `MissingOriginalsTests`, `RecoveryFactsChip`, offline chips in P0 editor. |
| **D36** | Anti-irritant + Trash | **PARTIAL** | **Violation:** catalog `shoot.json` via `ShootStore.saveShoot` (`Lumina/Services/ShootStore.swift:102`). Trash: `CopyContract.rejectsToTrashTemplate` only — **no UI/action**. |
| **D37** | Visual language | **PARTIAL** | `HiFiTokens`/`LuminaTokens`, `token_lint` OK. **D48 debt:** `P0SinglePhotoEditor.swift:356` `.onHover`. |
| **D38** | MVP knife | **SHELVED** (register) | Shelved items in contract §Shelved Register; legacy retains shelved surfaces. |
| **D39** | Efficiency / resume | **PARTIAL** | Copy: `CopyContract.cullHeaderResume`. **No** resume-first-undecided in `P0SessionModel` (grep `advanceFocus` / `firstUndecided` on P0 path: **no hits**). |
| **D40** | Engineering reconciliation | **PARTIAL** | Live entry `LuminaApp` → `P0RootView`. Legacy quarantined behind `showLegacyShell`. **Broken DEBUG refs:** `MotionProbeLauncher`/`MotionProbeView` in `LuminaApp.swift` — sources **absent**. |

### D41–D66 (v6 additions)

| ID | Title (abbrev.) | Existence | Evidence |
|----|-----------------|-----------|----------|
| **D41** | Consequence chips (R-5.1) | **PARTIAL** | `CopyContract.sharpnessNotFinal`; not wired as fidelity chip on P0. |
| **D42** | Hold-J clipping (R-5.2) | **ABSENT** (UI) | `CullHoldKey.j` in grammar tests only; no overlay on P0. |
| **D43** | Settle-as-confirmation (R-5.3) | **PARTIAL** | Token `settle_positive_signal`; crossfade tokens; no end-to-end settle gate on P0. |
| **D44** | ⌥⌘E recipe re-entry (R-8.1) | **PARTIAL** | `CopyContract.exportRecipeHint`; legacy `ContentView` chord comment. |
| **D45** | Diagnostics local-only (R-9.1) | **SHIPPED** (socket) | `BetaDiagnosticsSocket.activeKind = nil`; `zero_egress_audit` lint. |
| **D46** | Develop gate (R-A.1) | **BANKED** | Tier 1 banked; `TasteIndex` legacy only. |
| **D47** | Pointer cull marks (A3) | **PARTIAL** | Headless: `CullGrammarMachine.pointerMarkKeep/Reject`, `CullGrammarTests.testD47A3_*`. **No ✓/✕ UI** on focused frame. Tokens: `grammar.pointer_cull_*`. |
| **D48** | Hover deleted (R-X.1) | **PARTIAL** | Lint targets hover; **live violation** `P0SinglePhotoEditor:356`; legacy `DecisionDock`, `ContinuousWorkspaceView`. |
| **D49** | Layout quantized (R-X.2) | **PARTIAL** | `HiFiTokens.Layout`, `EditRailLayout`; hand literal `EditRailLayout.railWidth = 324`. |
| **D50** | Developer ID (R-I.1) | **SHELVED** | MAS/deferred socket; F11 scripts exist. |
| **D51** | Silent updates (R-I.2) | **PARTIAL** | `heavy_job_registry` lint; no updater machinery. |
| **D52** | Offline licensing (R-I.3) | **SHELVED** | Token `betaLicensing: none`; post-test pre-launch door. |
| **D53** | Device-plug ingest (R-M.2) | **PARTIAL** | `IngestOrchestrator`, `MediaFormats`. |
| **D54** | Sample shoot (R-M.3) | **ABSENT** | `CopyContract.sampleShootReplaces` only; no bundled fixture in app. |
| **D55** | Share destination (R-M.4) | **PARTIAL** | `copy_table_lint`; no share-sheet wiring on P0. |
| **D56** | Videos copied not shown (R-M.5) | **PARTIAL** | `MediaFormats.videoExtensions`; ingest skip logic. |
| **D57** | 90 px / PERSUADE (R-Q.1) | **PARTIAL** | Tokens `stripEvidenceHeight: 90`, halo 1.5pt; no PERSUADE evidence ledger. |
| **D58** | Halo 1.5 pt | **PARTIAL** | `HiFiTokens.Ring.haloWidth`; legacy halo views. |
| **D59** | Same-mark clears | **SHIPPED** (logic) | `CullGrammarTests.testD59_*`, `P0LogicTests.testCullToggleGrammar`. |
| **D60** | Return-release gate | **SHIPPED** (logic) | `CullGrammarTests.testD11D13_*`, `CommandChordTests.testHeldReturnCannotDoubleCommit`. |
| **D61** | Export three-state | **ABSENT** (P0) | Token enum only; legacy export UI partial. |
| **D62** | Post-commit focus advance | **ABSENT** (P0) | Oracle/tests for grammar; not wired in `P0SessionModel`. |
| **D63** | Crop latch keys (A2) | **PARTIAL** | Legacy: `CropSession`, `LuminaShellModel.enterCrop`, `CropTests`. P0: `P0CropControls` panel — **not** work-state latch. |
| **D64** | Swim lanes shelved (A6) | **SHELVED** | Register row; `swimlane_fill_opacity` socket in tokens only. |
| **D65** | MVP test fleet (A1) | **PARTIAL** | `unit_lane_guards` lint; six-body fleet in `design/fixture-manifest.md` — **UNMEASURED** complete. |
| **D66** | Beta distribution (A12) | **PARTIAL** | F11 release lane scripts; `f11_a7_expiry`, `f11_no_licensing` PASS on Linux FAST. |

### Rulings (R-*)

| Ruling | Binds | Existence | Evidence |
|--------|-------|-----------|----------|
| **R-5.1** | D41 | **PARTIAL** | Exemplar string sealed; not shipped as chip |
| **R-5.2** | D21/D42 | **ABSENT** (UI) | Hold-J grammar in tokens/tests only |
| **R-5.3** | D43 | **PARTIAL** | Token + crossfade constants |
| **R-8.1** | D44 | **PARTIAL** | Copy + legacy chord comment |
| **R-9.1** | D45 | **SHIPPED** | Null diagnostics socket, egress lint |
| **R-A.1** | D32/D46 | **BANKED** | Tier 1 gated |
| **R-A.2** | D47 | **PARTIAL** | Headless parity only; no pointer UI |
| **R-A.3** | D67 (proposed) | **NOT RATIFIED** | `grep '\bD67\b' design/contract-v6.md` → **no matches**; proposal on `constitution/batch-3-propagation` only — **UNMEASURED on this branch** |
| **R-I.1** | D50 | **SHELVED** | Contract presence lint |
| **R-I.2** | D51 | **PARTIAL** | Registry lint; no updater |
| **R-I.3** | D52 | **SHELVED** | Token `betaLicensing: none` |
| **R-I.4** | D66 | **PARTIAL** | F11 release scripts; no stapled ship artifact (**UNMEASURED** notarize) |
| **R-M.1** | D36 | **ABSENT** | Copy template only |
| **R-M.2** | D53 | **PARTIAL** | `IngestOrchestrator` |
| **R-M.3** | D54 | **ABSENT** | Copy only |
| **R-M.4** | D55 | **PARTIAL** | `copy_table_lint` |
| **R-M.5** | D56 | **PARTIAL** | `MediaFormats`, ingest tests |
| **R-Q.1** | D57 | **PARTIAL** | Tokens; no ledger |
| **R-X.1** | D24/D37/D48 | **PARTIAL** | Lint + tokens; hover on live P0 |
| **R-X.2** | D49 | **PARTIAL** | Layout tokens + `magic_numbers` lint |

### Shelved Register (existence of code vs register)

| Register item | Register status | Code on tree | Verdict |
|---------------|-----------------|--------------|---------|
| Tier 1 / Develop critical path | Banked (D46) | `TasteIndex`, legacy develop | **Door** — must not ungate without taste proof |
| Multi-select + two-up | Shelved (D29/D38) | `TableRubberBandOverlay`, `twoUp` | **Code exceeds shelf** — narrowing requires ruling, not silent delete |
| Pointer cull marks | **Un-shelved MVP** (D47/A3) | Grammar only | **PARTIAL** — UI absent |
| Swim-lane plates | Shelved (D64/A6) | Token socket only | **Honors shelf** |
| ⇧P/⇧X, gather-drag, cross-row compat, seam, etc. | Shelved | Legacy remnants | **Do not expand** without register amendment |

---

## 2. Checkpoints (Layer-2 sequence)

Evidence from `design/checkpoint-sequence-v6.md` cross-checked against **this tree only** (`a076644`). BUILD_LOG claims used only when corroborated.

| Step | Status | Evidence that decided | BUILD_LOG trust |
|------|--------|----------------------|-----------------|
| **SPIKE A** — Fidelity ladder | **PARTIAL** | **SHIPPED fragments:** `PreviewSpine.swift`, `DevelopRenderGraph.swift`, `DevelopRenderScheduler.swift`, `MetalPreviewPool.swift`, `DevelopLabLauncher` + `DevelopLabView` (`Lumina/Develop/Lab/`). **Gaps:** histogram CPU `DevelopHistogram.swift` (not in-shader); no 90/120/140 px evidence ledger (R-Q.1); live signpost gate **UNMEASURED** (macOS). | Prior SPIKE A rows **UNMEASURED** on Linux |
| **SPIKE B** — Table physics / F07 | **NOT STARTED on main** | **Absent:** `LuminaSpring.swift`, `test_f07_spring_physics.py`, motion seal keys in `tokens.yaml`, `Lumina/Testing/MotionProbe/`. FAST `spring_physics_f07` **FAIL** (missing test file). `LuminaApp.swift` references missing `MotionProbeLauncher`/`MotionProbeView`. | BUILD_LOG 2026-08-12 seal claim **not corroborated on main**. Unmerged `spike/b-motion` @ `cf583f8` has seal + F07 **PASS** — treat as **branch work**, not landed |
| **CP1** — Layout pure function | **PARTIAL** | **SHIPPED:** `EditRailLayout.swift`, `HiFiTokens.Layout`, `P0LogicTests.testEditRailLayoutMinWindow`. Legacy: `TableLayout.swift`. Live P0 ≠ full table layout grammar (D1/D49). | CP1 “landed” claims **overstated** for P0 path |
| **CP2** — Journal + sidecars + kill-fuzz | **NOT STARTED** | `ShootStore.saveShoot` → `shoot.json` catalog (`ShootStore.swift:102`). Sidecar write on export/handoff only (`ExportService`, `LightroomHandoffService`). No continuous open-XMP beside files; no kill-fuzz job; F06 prompt **absent** from `design/build-prompts/`. | RESUME CP2 “NOT BUILT” **corroborated** |
| **CP3** — Ingest for real | **PARTIAL** | `IngestOrchestrator`, `ImportPipeline`, `MediaFormats` (HEIC/video skip). P0 folder drop. Six-body fleet: fixture manifest only — **UNMEASURED** e2e. Sample shoot **ABSENT**. | Partial ingest **corroborated** |
| **CP4** — Cull hot loop + pointer marks | **PARTIAL** | **P0 SHIPPED:** P/X, same-mark (`P0SessionModel`, `P0ContactSheetView`). **Missing:** advance-after-mark on P0, pointer ✓/✕ UI (D47), resume-first-undecided (D39). Legacy cull uses pre-contract S/M/X. | “SHIPPED” in W4 **overstates** P0 completeness |
| **CP5** — Rail (10 controls, arming, echo) | **PARTIAL** | P0: `P0AdjustmentRail`, `P0EditSlider`. Legacy: `TreatmentStageView` closer to contract rail. Hover debt (D48). Pixel golden exists under **stale** tokens-hash (see §3). | Chrome golden **stale** vs current hash |
| **CP6** — Focused edit + crop latch | **PARTIAL** | **P0 SHIPPED:** `P0SinglePhotoEditor`, RAW edit path. **Missing:** `CropSession` latch on P0, Hold-J/clipping overlay, full ten-control flat rail. Legacy: `CropSession`, `TreatmentStageView`. | P0 edit **SHIPPED**; crop latch **legacy only** |
| **CP7** — Hero / propagation | **PARTIAL** (legacy) | **SHIPPED in legacy shell:** `PropagationState.swift`, `WorkbenchSelection.stageTreat`, `LuminaShellModel` staging, `PropagationTests`. **Not on P0 live path.** D67 / Batch 3 **NOT RATIFIED**. | CP7 code exists; law for intent propagation **NOT IN FORCE** |
| **CP8** — Open / export / endgame | **PARTIAL** | **SHIPPED fragments:** `P0OpenView`, `ExportService`, `ExportPayoffSheet` (legacy). **Missing:** sample shoot, three-state export UI (D61), rejects-to-Trash action (R-M.1), share destination, F12 bug-report bundle. | Endgame **not wave-complete** |

**S19 (Develop Lab):** **LANDED on main** — `DevelopLabLauncher.swift`, `DevelopLabView.swift`, `hook_inventory.yaml` `s19_playground`.  
**S18 / S20 / MotionProbe:** **UNMEASURED** — no BUILD_LOG row with tree evidence; MotionProbe sources **ABSENT**.

---

## 3. Sealed vs tuned

| Surface / artifact | State | Holder | Evidence |
|--------------------|-------|--------|----------|
| **`design/tokens.yaml`** | **Sealed** (partial) | version `6.2-batch2` | `token_lint.py` OK; **no** SPIKE B spring block on main |
| **`tokens.hash`** | **Sealed** | `c8f75e1a3733…` | `artifacts/harness/tokens.hash`; matches `HiFiTokens.generated.swift` header |
| **`HiFiTokens.generated.swift`** | **Generated, consumed** | codegen | Ring, halo, gaps, crop grammar, export states; used in `EditRailLayout`, tests |
| **`design/copy-contract.txt`** | **Sealed** | lint | `copy_contract_diff.sh` OK; D59/D60 verbatim strings |
| **Chrome metrics golden** | **Stale** | old hash | Approved under `4165261bd21cd…` ≠ current `c8f75e1a…` — `unit_golden` passes service bookkeeping only |
| **Spring trajectory golden** | **ABSENT on main** | — | No `spring_trajectory_place_return` under current hash (exists only on unmerged `spike/b-motion`) |
| **Motion timings in UI** | **Tuned in place** | `LuminaTokens.Motion` | Hardcoded `Animation.easeOut` / `easeInOut` durations — **not** routed through owned spring on main |
| **Layout literals** | **Tuned in place** | allowlist | e.g. `EditRailLayout.railWidth = 324`, `railFooterHeight = 118`; `magic_numbers.sh` OK via allowlist |
| **P0 contact sheet / editor layout** | **Tuned in place** | SwiftUI | No pixel golden keyed to current hash for P0 surfaces |
| **Develop render / fidelity** | **Tuned in place** | `DevelopRenderGraph`, `PreviewSpine` | No sealed trajectory or signpost ledger on main |
| **Constitution coverage artifact** | **Stale** | registry | FAST `constitution_coverage` **FAIL** — matrix not regenerated after registry drift |

**Rule:** A token or golden **holds** a surface only when hash-aligned and referenced by a passing gate. Everything else is still **tuned in place** and drifts silently.

---

## 4. What remains for a wave-worthy build

Ordered by blocker severity. **Must-ship** = blocks a honest wave demo or ship gate. **Can-ship-later** = door preserved (D38). Each deferral names its **door**.

### Must-ship (blockers)

| # | Item | Blocker | Door / session type |
|---|------|---------|---------------------|
| **M1** | **macOS automation mode** | Every app-coupled assertion UNMEASURED; FAST 0/7 app tests on Linux. Failed twice per RESUME — no BUILD_LOG repro row. | **Diagnostic session** — `UITestLaunch`, probe visibility, one `P0Fast` flow green on idle Mac |
| **M2** | **Merge or reconcile SPIKE B** | Main: F07 test missing, MotionProbe refs broken, no motion seal. Unmerged `spike/b-motion` has green F07 + `6.2-motion-seal` → **`tokensHash` move** invalidates F11.4, F04.1 cache, goldens. | **Merge spike/b-motion** then re-measure all hash-keyed artifacts |
| **M3** | **CP2 persistence** | D36 violation: `ShootStore` → `shoot.json` catalog vs open-XMP beside files. Blocks “files stay put / delete Lumina loses nothing” and LR handoff honesty. | **CP2 checkpoint session** (journal + sidecars + kill-fuzz); F06 prompt emission |
| **M4** | **P0 path vs contract surface** | Live demo is contact sheet + single-photo edit; table loop, propagation, crop latch, full rail live in **legacy shell only** (`showLegacyShell`). Wave story requires explicit promotion or P0 wiring decision. | **Product ruling:** wire CP6/7 onto P0 vs demo legacy (not assumed in this doc) |
| **M5** | **D48 hover on live P0** | FAST `banned_patterns` **FAIL**: `P0SinglePhotoEditor.swift:356`. | **CP5/CP6 hygiene session** — remove hover; no new features |
| **M6** | **D67 / Batch 3 ratification** | CP7 propagation code **SHIPPED** in legacy; law **NOT IN FORCE** (`grep D67 contract-v6` empty). | **Constitution session** — ratify or reject `proposal-batch-3.md`; narrow code if rejected |
| **M7** | **Harness honesty** | FAST red: `contract_v6_presence`, `constitution_coverage`, `spring_physics_f07`. | **Harness hygiene** — regenerate coverage; fix A7 expiry lint text; land F07 with M2 |

### Can-ship-later (doors, not deletions)

| # | Item | Why deferrable | Door |
|---|------|----------------|------|
| **L1** | SPIKE A full seal (in-shader histogram, R-Q.1 ledger) | Tier 0 edit usable without PERSUADE ledger | SPIKE A completion session after M2 |
| **L2** | CP3 six-body fleet + sample shoot (D54) | Folder drop works for early testers | CP3 session + fixture manifest |
| **L3** | CP8 rejects-to-Trash UI (R-M.1) | X never touches FS; export can ship without Trash offer | CP8 endgame session after ✓ path proven |
| **L4** | CP8 three-state export (D61) + share sheet (D55) | Partial export exists in legacy | CP8 |
| **L5** | D47 pointer ✓/✕ UI on P0 | Keyboard P/X works; pointer path is additive (A3) | CP4 follow-up |
| **L6** | D62 post-commit focus advance on P0 | Grammar tests exist headless | CP4 polish |
| **L7** | D42 Hold-J clipping overlay | Token + grammar ready | CP6 after crop latch |
| **L8** | Tier 1 / Develop taste model (D46) | Banked on A10 proof schedule | Wave two / v1.1 after consented eval set |
| **L9** | Shelved surfaces (two-up, multi-select, gather-drag) | Register doors | Explicit register amendment only |
| **L10** | F11.3 notarize + staple, F11.6 betaDiagnostics assert | Ship integrity follow-ups | macOS ship host after M1 |
| **L11** | F12 bug-report bundle | Behind CP2 | CP2 → F12 chain per RESUME |
| **L12** | Chrome / P0 pixel goldens under new hash | Bookkeeping after token seal | Re-propose after M2 merge |

### Suggested wave order (measurement-derived — subordinate to §5 operator invariants)

```
M1 macOS automation diagnostic
  → M7 harness hygiene (parallel on Linux)
  → P7 (SPIKE B seal — moves tokensHash)
  → R3 (F11 release + fresh manifest — re-run before Wave 0)
  → Wave 0 (first DMG / ship cut — manifest fields current)
  → … checkpoint work …
  → P5 (CP2 persistence — “nothing lost” becomes test result)
  → Wave 1 (gated on P5 only)
```

Legacy measurement order (§4 M-items) remains valid for **engineering** sequencing inside Wave 0 prep; **distribution** sequencing is fixed by §5.

**One-checkpoint rule** (`checkpoint-sequence-v6.md`): do not span two checkpoints in one build session.

---

## 5. Operator wave invariants (true regardless of P8 findings)

*Recorded 2026-08-13 from operator ruling. These override ad-hoc “ship now” shortcuts in §4.*

### Session map (operator labels)

| Label | Maps to | What it proves |
|-------|---------|----------------|
| **P7** | SPIKE B motion seal (`design/tokens.yaml` §motion → `6.2-motion-seal` or successor) | **`tokensHash` moves** — F07.4–F07.6 green; codegen `--check`; spring trajectory golden under new hash. Unmerged work: `spike/b-motion` @ `cf583f8` (**UNMEASURED on main**). |
| **R3** | F11 release integrity + manifest embed + promote | **`run_f11_release.py`** (F11.1–F11.7) + **`write_build_manifest.py`** + optional **`retain_shipped_artifact.py promote`**. macOS only (`PLATFORM-UNAVAILABLE` on Linux — **UNMEASURED** here). |
| **P5** | CP2 checkpoint (journal + sidecars + crash-only startup + kill-fuzz) | D36 “nothing you did is ever lost” stops being a **claim** and becomes a **test result** (F06 / HEAVY kill-fuzz / LR round-trip — **NOT BUILT** on `a076644`; `ShootStore.saveShoot` → `shoot.json` still live). |
| **Wave 0** | First wave-worthy DMG / ship cut to testers | First distribution artifact after P7 + R3. |
| **Wave 1** | Second wave distribution | **Gated on P5** — do not ship Wave 1 until CP2 persistence is measured green. |

### Manifest stale rule (P7 → R3 → Wave 0)

**P7 moves `tokensHash`.** Any DMG cut packaged **before** P7 lands embeds stale values in **two** `LuminaBuildManifest.json` fields (written by `Scripts/harness/release/write_build_manifest.py`):

| Field | Source at build time | Goes stale when |
|-------|---------------------|-----------------|
| **`tokensHash`** | `artifacts/harness/tokens.hash` | Any `design/tokens.yaml` edit (P7 §motion seal) |
| **`contractVersion`** | `design/tokens.yaml` `version` key | Same bump (e.g. `6.2-batch2` → `6.2-motion-seal`) |

Measured stale example on main @ `a076644`: embedded BUILD_LOG cites `tokensHash: 7b0c1552…` / `contractVersion: 6.2-motion-seal` while live tree has `c8f75e1a…` / `6.2-batch2` — **contradiction proves pre-P7 cuts lie about law.**

**Corollary:** **`R3` must complete after P7 and before Wave 0** — rebuild Release `.app`, re-embed manifest, re-run `f11_read_manifest.py --check`, then promote (`F11.5`). Install-page `bugReportLine` and tester bug citations inherit both fields (`docs/release/install-page-content-spec.md` Surface 1).

Also invalidated by P7 (re-measure, not just manifest): F04.1 build-cache key (`<source12>-<tokens12>`), spring trajectory golden, chrome goldens under old hash (`artifacts/harness/goldens/<hash>/…`).

### Wave gates (fixed)

| Wave | Gate | Blocker if skipped |
|------|------|-------------------|
| **Wave 0** | P7 closed + **R3 re-run** on macOS | Ship artifact cites wrong `tokensHash` / `contractVersion`; rollback manifest (`F11.5 previous/`) also stale |
| **Wave 1** | **P5 closed** (CP2 measured) | “Nothing you did is ever lost” remains marketing copy; D36 catalog violation (`shoot.json`) live |

**Wave 1 is not gated on Wave 0 completion** — it is gated on **P5**. Wave 0 may ship a narrower surface; Wave 1 assumes persistence law is enforced by tests, not prose.

---

## FOLLOW-UPS (adjacent — not proposed for this wave)

- Named pinch density steps token seal (D49 OPEN)
- R-5.1 additional consequence-class chips beyond `sharpness not final`
- D51 update channel vs zero-egress ideal
- D55 share destination field labels
- MotionProbe S18/S20 live driver (sources absent; hook registered)
- Close superseded PRs #36–#39 (operator action; integration lacks `closePullRequest`)
- Promote `design/strategy/s1-mvp-sharpening.md` merge so W4 matrices live beside this doc on main

---

## Summary counts (existence axis, D1–D66 + key R)

| Status | Count (approx.) |
|--------|-----------------|
| SHIPPED | 6 (headless/copy/socket clusters) |
| PARTIAL | 48 |
| ABSENT | 10 |
| SHELVED / BANKED | 8 register rows |
| NOT RATIFIED | R-A.3 / proposed D67 |

**Wave-worthy today:** **No** — M1–M7 block an honest Wave 0 on `origin/main` @ `a076644`. Unmerged SPIKE B work reduces physics gap but does not clear M1, M3, M4, or M6. **Even if M-items green:** Wave 0 still requires **P7 → R3**; Wave 1 still requires **P5** (§5).
