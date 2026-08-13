# Legacy shell disposition register (W8)

**Authority:** D38 (doors, not deletions) · D40 retirement plan in `design/checkpoint-sequence-v6.md`.  
**Measured:** 2026-08-13 · branch `cursor/w8-legacy-severance-39dd`.

## Measurement method

| Metric | Rule |
|--------|------|
| **Total Swift** | All `Lumina/**/*.swift` files (includes `Develop/Lab/`). |
| **From `LuminaApp`** | Static symbol-reference BFS seeded at `Lumina/LuminaApp.swift` (`Scripts/harness/lint/swift_reachability.py`). |
| **Legacy-only (31)** | Legacy shell inventory minus files whose primary types are referenced from `Lumina/Views/P0/*.swift` (excluding `P0RootView.swift`) or `P0SessionModel.swift`. |

**Severance change:** `P0RootView` no longer constructs `ProjectViewModel` / `LuminaShellModel` at launch. Legacy models live behind `P0LegacyShellContainer` (`P0LegacyShellDoor.swift`) and construct on first door open only.

## Deleted this session (zero external references)

| File | Primary symbol | External refs (incl. tests) | Action |
|------|----------------|------------------------------|--------|
| `Lumina/Views/Components/DecisionDock.swift` | `DecisionDock` | **0** | **DELETED** — dead view + hover handler (D48). Button styles moved to `Lumina/Views/LuminaButtons.swift`. |

## Legacy-only inventory (31 files before severance → 27 after door file)

Before W8, **31 files / 10,230 lines** in the legacy shell inventory had **zero** type-name references from P0 (excluding `P0RootView.swift`). After severance, `P0LegacyShellDoor.swift` holds the lazy door and references `ProjectViewModel`, `LuminaShellModel`, `LuminaShellView`, and `ImportLoadingView` — those four leave the legacy-only set (**27 files / 7,100 lines** remain door-only).

| File | Lines | Disposition | Owner / reason |
|------|------:|-------------|----------------|
| `Lumina/ContentView.swift` | 264 | **DELETE-AT** post-CP8 | Standalone legacy host; superseded by `P0LegacyShellDoor` path |
| `Lumina/Shell/LuminaShellModel.swift` | 1335 | **KEEP** | Legacy shell state + CP7 staging grammar socket until CP7 ports |
| `Lumina/Shell/LuminaShellView.swift` | 392 | **KEEP** | Legacy route chrome until P0 endgame |
| `Lumina/Shell/WorkbenchSelection.swift` | 274 | **PORT-TO-P0** | **CP7** — staging / propagation selection machine |
| `Lumina/ViewModels/ProjectViewModel.swift` | 1301 | **DELETE-AT** post-CP8 | Legacy project VM; P0 uses `P0SessionModel` |
| `Lumina/Views/ExportPayoffSheet.swift` | 107 | **PORT-TO-P0** | **CP8** — export receipt surface (D34/D61) |
| `Lumina/Views/GridOverviewView.swift` | 41 | **DELETE-AT** post-CP8 | Legacy grid chrome |
| `Lumina/Views/ImportLoadingView.swift` | 102 | **DELETE-AT** post-CP8 | Spinner-style import overlay — banned on P0 failure path (D35) |
| `Lumina/Views/MetalBrowseCanvas.swift` | 309 | **DELETE-AT** post-CP8 | Legacy browse renderer |
| `Lumina/Views/PhotoGridView.swift` | 277 | **DELETE-AT** post-CP8 | Legacy grid |
| `Lumina/Views/ProgressivePhotoWall.swift` | 276 | **DELETE-AT** post-CP8 | Legacy wall |
| `Lumina/Views/SpeedBrowseViewer.swift` | 312 | **DELETE-AT** post-CP8 | Legacy speed browse |
| `Lumina/Views/SpeedContractHUD.swift` | 54 | **DELETE-AT** post-CP8 | Legacy HUD |
| `Lumina/Views/UncertainAndClusterViews.swift` | 446 | **DELETE-AT** post-CP8 | Legacy cluster chrome |
| `Lumina/Views/UnifiedCanvasView.swift` | 37 | **DELETE-AT** post-CP8 | Superseded by `LuminaShellView` |
| `Lumina/Views/Workspace/CommandHandlingModifier.swift` | 422 | **DELETE-AT** post-CP8 | Legacy key owner — P0 uses `P0KeyRoutingModifier` (W5) |
| `Lumina/Views/Workspace/ContextualTreatmentStrip.swift` | 137 | **PORT-TO-P0** | **CP5/CP6** — treatment rail chrome |
| `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` | 1023 | **KEEP** | Legacy table workspace — CP7 propagation host until port |
| `Lumina/Views/Workspace/DockedAdaptChipView.swift` | 51 | **PORT-TO-P0** | **CP7** — provenance chip drag (D16/A5) |
| `Lumina/Views/Workspace/EmergingSetRail.swift` | 190 | **DELETE-AT** post-CP8 | Legacy set rail |
| `Lumina/Views/Workspace/FinishView.swift` | 203 | **PORT-TO-P0** | **CP8** — export finish surface |
| `Lumina/Views/Workspace/FocusOverlayView.swift` | 100 | **DELETE-AT** post-CP8 | Legacy focus overlay |
| `Lumina/Views/Workspace/HomeView.swift` | 326 | **DELETE-AT** post-CP8 | Legacy home — P0 Open replaces |
| `Lumina/Views/Workspace/ShootSelectionView.swift` | 119 | **DELETE-AT** post-CP8 | Legacy shoot picker |
| `Lumina/Views/Workspace/StoryCanvasView.swift` | 159 | **DELETE-AT** post-CP8 | Legacy story canvas |
| `Lumina/Views/Workspace/TableRubberBandOverlay.swift` | 63 | **KEEP** | **Shelved** (D29/D38) — drag-box; port only if un-shelved |
| `Lumina/Views/Workspace/TableTileFramePreference.swift` | 24 | **PORT-TO-P0** | **CP7** — halo / tile geometry helper |
| `Lumina/Views/Workspace/TreatmentFamilyRow.swift` | 472 | **PORT-TO-P0** | **CP7** — row-scoped propagation UI |
| `Lumina/Views/Workspace/TreatmentStageView.swift` | 1001 | **PORT-TO-P0** | **CP6/CP7** — focused edit + develop stage in legacy |
| `Lumina/Views/Workspace/WorkbenchCapture.swift` | 179 | **KEEP** | Headless capture harness — not live UI |
| `Lumina/Views/Workspace/WorkbenchShelf.swift` | 234 | **DELETE-AT** post-CP8 | Legacy shelf chrome |

## Shared legacy support (referenced from P0 graph or services — not door-only)

| File | P0 type refs (excl. `P0RootView`) | Disposition | Owner |
|------|-----------------------------------|-------------|-------|
| `Lumina/Views/P0/P0LegacyShellDoor.swift` | 2 (`ContentViewLegacyHost`, door) | **KEEP** | W8 explicit door — D38 |
| `Lumina/Core/PropagationState.swift` | 0 | **PORT-TO-P0** | **CP7** — propagation rings / exclusions |
| `Lumina/Presentation/PresentationAdapter.swift` | 0 | **PORT-TO-P0** | **CP7/CP8** — presentation builders |
| `Lumina/Develop/CropSession.swift` | 0 | **PORT-TO-P0** | **CP6** — crop latch (A2) |
| `Lumina/Views/Components/LiveDevelopView.swift` | 0 | **PORT-TO-P0** | **CP6** — develop preview surface |
| `Lumina/Views/Components/WorkspaceChrome.swift` | 0 | **PORT-TO-P0** | **CP7** — workspace chrome |
| `Lumina/Views/Components/FloatingDecisionShelf.swift` | 0 | **DELETE-AT** post-CP4 | Legacy decision shelf — P0 cull is live |
| `Lumina/Views/LuminaAtmosphere.swift` | 2 | **DELETE-AT** post-CP8 | Legacy atmosphere helper |

## Live-path bridge (must not delete before ports)

| File | Disposition | Notes |
|------|-------------|-------|
| `Lumina/Views/P0/P0RootView.swift` | **KEEP** | Live root — legacy branch delegates to door only |
| `Lumina/ViewModels/P0SessionModel.swift` | **KEEP** | Canonical P0 session state |

## CP7 propagation set — DO NOT DELETE before port

These files are the **only** in-tree implementation of wholesale propagation grammar (D13–D19). D38 forbids deletion; disposition is **PORT-TO-P0 CP7**:

- `Lumina/Shell/WorkbenchSelection.swift`
- `Lumina/Views/Workspace/TreatmentFamilyRow.swift`
- `Lumina/Views/Workspace/TreatmentStageView.swift`
- `Lumina/Views/Workspace/DockedAdaptChipView.swift`
- `Lumina/Views/Workspace/TableRubberBandOverlay.swift` *(shelved — keep as door)*
- `Lumina/Views/Workspace/TableTileFramePreference.swift`
- `Lumina/Views/Workspace/ContinuousWorkspaceView.swift` *(host — KEEP until CP7 lands on P0)*
- `Lumina/Core/PropagationState.swift`

## Conflict block (harness / instinct)

Any lint or gate that proposes deleting propagation surfaces before CP7 ports them is a **CONFLICT** — disposition wins over deletion.
