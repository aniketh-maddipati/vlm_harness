# F07 motion inventory — Lumina/ animation call sites

Authority: `design/contract-v5.md` §7 (D27, D28) · interim durations from `design/tokens.yaml` `motion:`.

| # | File | Line(s) | Current | Target token | Routable |
|---|------|---------|---------|--------------|----------|
| 1 | `Lumina/Design/LuminaTokens.swift` | 152–173 | `Animation.ease*` defs | all `LuminaSpringToken` | yes (hub) |
| 2 | `Lumina/Views/LuminaButtons.swift` | 10,33,44 | `Motion.control` | `travel` | yes |
| 3 | `Lumina/Views/Workspace/WorkbenchShelf.swift` | 157 | `Motion.control` | `travel` | yes |
| 4 | `Lumina/Views/Components/FloatingDecisionShelf.swift` | 110 | `Motion.control` | `travel` | yes |
| 5 | ~~`Lumina/Views/Components/WorkspaceCommandBar.swift`~~ | — | deleted (zero callers) | — | — |
| 6 | `Lumina/Views/Components/DecisionDock.swift` | 107–108 | `Motion.control` ×2 | `travel` | **CONFLICT D28** (dual modifiers) |
| 7 | `Lumina/Shell/LuminaShellView.swift` | 53–54 | `Motion.route` ×2 | `chromeFadeOut` | **CONFLICT D28** (route+lens) |
| 8 | `Lumina/Shell/LuminaShellView.swift` | 82 | `.easeOut(0.18)` | `travel` | yes |
| 9 | `Lumina/Shell/LuminaShellModel.swift` | 500,727 | `Motion.photo` | `placeReturn` | yes |
| 10 | `Lumina/Views/Components/WorkspaceChrome.swift` | 145 | `Motion.photo` | `placeReturn` | yes |
| 11 | `Lumina/Views/P0/P0ContactSheetView.swift` | 84 | `Motion.route` | `chromeFadeOut` | yes |
| 12 | `Lumina/Views/Workspace/StoryCanvasView.swift` | 35,151 | `selection` / `control` | `stage` / `travel` | yes |
| 13 | `Lumina/Views/Workspace/TreatmentStageView.swift` | 267 | `Motion.selection` | `stage` | yes |
| 14 | `Lumina/Views/Workspace/TreatmentStageView.swift` | 318 | `Motion.stage` | `stage` | yes |
| 15 | `Lumina/Views/Workspace/TreatmentStageView.swift` | 491 | `fidelityCrossfade` | `fidelityCrossfade` | yes |
| 16 | `Lumina/Views/Workspace/TreatmentStageView.swift` | 691 | `.easeOut(0.25)` | `chromeFadeOut` | yes |
| 17 | `Lumina/Views/Workspace/TreatmentStageView.swift` | 705,712,715 | default `withAnimation` + sleep chain | — | **CONFLICT D28** |
| 18 | `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 141 | `Motion.control` | `travel` | yes |
| 19 | `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 432 | `Motion.shelfIn` | `shelfIn` | yes |
| 20 | `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 462 | `Motion.stage` | `stage` | yes |
| 21 | `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 841 | hover in/out tokens | `warmInCrossfade` / `chromeFadeOut` | yes (direction picks token) |
| 22 | `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 847 | `Motion.selection` | `stage` | yes |
| 23 | `Lumina/Views/Workspace/TreatmentFamilyRow.swift` | 229 | `Motion.selection` | `stage` | yes |
| 24 | `Lumina/Views/Workspace/TreatmentFamilyRow.swift` | 339–340 | `lift` + `stage`/`keyline` | — | **CONFLICT D28** |
| 25 | `Lumina/Views/SpeedBrowseViewer.swift` | 47–67 | condense/dissolve | `travel` | yes |
| 26 | `Lumina/Views/SpeedBrowseViewer.swift` | 196 | `Motion.reveal` → photo | `photoBirth` token ms | yes (alias) |
| 27 | `Lumina/Views/SpeedBrowseViewer.swift` | 297 | dissolve | `travel` | yes |
| 28 | `Lumina/Views/ImportLoadingView.swift` | 50,56,72 | reveal/condense/settle | `photoBirth`/`travel`/`chromeFadeOut` | yes |
| 29 | `Lumina/Views/UncertainAndClusterViews.swift` | 95,178 | bloom/settle | `chromeFadeOut`/`travel` | yes |
| 30 | `Lumina/Views/CompareAndSoftViews.swift` | 14,26 | `Motion.photo` (`DynamicSortBar`) | `placeReturn` | yes |
| 31 | ~~`Lumina/Views/CompareAndSoftViews.swift` GradedCompareView~~ | — | deleted (zero callers) | — | — |
| 32 | ~~`Lumina/Views/PhotoImageView.swift`~~ | — | deleted (zero callers) | — | — |
| 33 | `Lumina/Views/ProgressivePhotoWall.swift` | 167,204 | `.easeOut(0.2/0.25)` | `travel` / `chromeFadeOut` | yes |
| 34 | `Lumina/ViewModels/ProjectViewModel.swift` | 389,409,425,442 | `.easeInOut(0.55/0.4/0.35)` | — | **CONFLICT D28** (no token duration; chained import phases) |
| 35 | `Lumina/Views/Components/StablePhotoView.swift` | 237–241 | birth crossfade + photoBirth | — | **CONFLICT D27+D28** |
| 36 | `Lumina/Views/Components/StablePhotoView.swift` | 254,269,361 | fidelity crossfade/fidelity | token mapped | partial (361 ok; 254 chain) |
| 37 | `Lumina/Views/Components/StablePhotoView.swift` | 82–84 | opacity birth on photograph | — | **CONFLICT D27** |
| 38 | `Lumina/Views/Components/StablePhotoView.swift` | 354 | silhouette `.opacity` transition | — | **CONFLICT D27** |
| 39 | `Lumina/Views/Components/GradedPhotoView.swift` | 49,100 | develop opacity | — | **CONFLICT D27** |
| 40 | `Lumina/Views/Components/ShortcutsGlanceOverlay.swift` | 39 | opacity transition | `warmInCrossfade` | yes (chrome) |
| 41 | `Lumina/Shell/LuminaShellView.swift` | 51 | opacity+scale transition | — | **CONFLICT D28** |
| 42 | `Lumina/ContentView.swift` | 55,70 | opacity(+scale) transitions | chrome | **CONFLICT D28** (#55 combined) |
| 43 | `Lumina/Views/P0/P0ContactSheetView.swift` | 26 | opacity+scale | — | **CONFLICT D28** |
| 44 | `Lumina/Views/Workspace/FocusOverlayView.swift` | 61 | opacity+move | — | **CONFLICT D28** |
| 45 | `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 431 | opacity+move shelf | — | **CONFLICT D28** |
| 46 | `Lumina/Views/UncertainAndClusterViews.swift` | 94 | opacity+scale | — | **CONFLICT D28** |
| 47 | Transitions-only (opacity, no explicit Animation) | various | implicit with parent `.animation` | inherits parent spring | yes |

Token ms mapping (`design/tokens.yaml`):

| Token | ms | D27/D28 role |
|-------|-----|--------------|
| `warmInCrossfade` | 120 | chrome in |
| `fidelityCrossfade` | 120 | chrome crossfade |
| `shelfIn` | 120 | chrome shelf |
| `bannerIn` | 120 | chrome banner |
| `photoBirth` | 340 | table landing (opacity-only note in tokens — **D27 conflict at photograph layer**) |
| `lift` | 100 | grab |
| `travel` | 180 | default travel |
| `travelFast` | 90 | fast-run travel |
| `stage` | 140 | staging ripple |
| `reduceMotionKeyline` | 90 | reduced-motion keyline |
| `chromeFadeOut` | 250 | chrome out (D27) |
| `placeReturn` | 200 | place/return spring ≤2% overshoot (D27) |

Legacy `LuminaTokens.Motion.*` → token:

| Motion constant | Was (s) | Token |
|-----------------|---------|-------|
| control | 0.18 | travel |
| photo | 0.28 | placeReturn |
| selection | 0.32 | stage |
| develop | 0.55 | *(no yaml ms — keep ease, CONFLICT)* |
| route | 0.24 | chromeFadeOut |
| fidelity | 0.22 | travel |
| reveal | 0.34 | photoBirth |
| lift | 0.10 | lift |
| travel | 0.18 | travel |
| travelFast | 0.09 | travelFast |
| stage | 0.14 | stage |
| shelfIn | 0.12 | shelfIn |
| fidelityCrossfade | 0.12 | fidelityCrossfade |
| reduceMotionKeyline | 0.09 | reduceMotionKeyline |
| tableHoverIn | 0.12 | warmInCrossfade |
| tableHoverOut | 0.25 | chromeFadeOut |
| photoBirth | 0.34 | photoBirth |
