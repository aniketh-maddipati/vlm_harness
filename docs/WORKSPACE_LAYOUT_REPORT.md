# Lumina Continuous Workspace — Layout Report

**Version:** Continuous workspace iteration (Aug 2026)  
**Primary view:** `ContinuousWorkspaceView`  
**Branch:** `cursor/ethereal-ui`

---

## 1. Executive summary

The cull surface is now **one continuous photographic workspace** with three spatial stages that share selection, scroll anchors, and project state:

| Stage | Role | Approx. layout @ 1440×900 |
|-------|------|---------------------------|
| **Workbench** | Compare families, preview treatment, route to set | ~75% ledger + ~25% emerging-set rail (320 pt) |
| **Canvas** | Editorial draft of kept photographs | ~220 pt source rail + remaining canvas |
| **Proof** | Chrome-free reading of the same canvas sequence | Full window |

These are **not separate routes** — `LuminaShellModel.workspaceStage` morphs proportions inside `route == .workspace`.

---

## 2. Workbench

### Row design
- **Max 8 photographs** per comparison family (adaptive time bucketing).
- **Capture-time order** — no quality-score reshuffling.
- **Suggested start** — first undecided frame, quiet outline + label (not a giant hero).
- **Inactive row:** 4–8 thumbnails, title, time span, routed/folded counts.
- **Expanded row:** equal-size grid (up to 4×2), contextual treatment strip below.
- **Sibling continuation** — when one cluster splits into adjacent buckets, a left bracket + “continued · N of M” cue links them.

### Treatment strip (contextual, not sidebar)
Under the expanded active row only:
- Original / Auto / Current
- Exposure, Warmth, Shadows
- More… (remaining develop sliders)
- Preview across row (shared treatment — explicitly not per-frame adaptive AI)

The fixed 380 pt develop sidebar is **removed** from the default Workbench.

### Emerging-set rail
- “The set so far” + kept count
- Vertical thumbnails in **draft capture-time order**
- Open canvas affordance
- **@ width < 1100:** collapses to compact `Set · N` tab (click → Canvas)

---

## 3. Canvas & Proof

### Canvas
- Source rail (~220 pt) keeps active row visible
- `StoryCanvasView` — vertical editorial sequence, mixed scales, aspect-fit only
- Header: “Draft order · capture time” (honest — no persisted story order yet)
- Narrative placeholder block (disabled prototype)
- Proof button → Proof stage

### Proof
- Same sequence, no chrome, no badges
- Esc → Canvas at preserved scroll anchor
- Quiet “Esc to return” hint (auto-fades)

---

## 4. Keyboard (workspace)

| Input | Action |
|-------|--------|
| ↑ / ↓ | Previous / next row |
| ← / → | Previous / next photograph in row |
| Return | Expand / collapse active row |
| Space | High-resolution Focus overlay |
| S | Send to emerging set (Keep) |
| X | Fold (Reject) |
| M | Hold (Maybe / flagged) |
| A | Preview Auto treatment |
| E | Toggle detailed edit controls |
| ⌘1 / ⌘2 / ⌘3 | Workbench / Canvas / Proof |
| Esc | One spatial level back |

Subject/Time lens switching remains in the toolbar (no longer ⌘1/⌘2).

**Not implemented:** ⌘Z undo (documented debt). Destructive swipe gestures removed.

---

## 5. Color & typography

Unchanged porcelain editorial tokens (`LuminaTokens`):
- porcelain work surface, rail grey structure, well insets
- Iowan shoot titles, SF Pro controls
- hairlines, no heavy cards, photographs supply color

---

## 6. Architecture

```
ProjectViewModel
  → PresentationAdapter (≤8 photo buckets, capture order)
  → LuminaShellModel (workspaceStage, selection, develop offsets, scroll anchors)
  → ContinuousWorkspaceView
       ├─ WorkbenchLedgerView + TreatmentFamilyRow
       ├─ ContextualTreatmentStrip
       ├─ EmergingSetRail
       ├─ WorkbenchSourceRail (Canvas)
       └─ StoryCanvasView / StoryProofView
```

Presentation snapshots still cached by fingerprint; selection overlays without group rebuild.

---

## 7. Intentional debt (not in this iteration)

- True treatment-compatible grouping
- Intelligent per-frame treatment adaptation
- Persisted story ordering / drag reorder
- Separate Lightroom-invest state
- Crop, noise removal, object removal
- XMP Lightroom round-trip
- Full undo stack
- Agentic Canvas proposals
- Resume verification beyond existing project store

---

## 8. File reference

| File | Role |
|------|------|
| `ContinuousWorkspaceView.swift` | Stage orchestrator |
| `WorkbenchLedgerView.swift` | Row scroll + treatment strip |
| `TreatmentFamilyRow.swift` | Comparison family UI |
| `ContextualTreatmentStrip.swift` | Develop controls |
| `EmergingSetRail.swift` | Kept-photo receipt |
| `StoryCanvasView.swift` | Editorial canvas + proof |
| `LuminaShellModel.swift` | `WorkspaceStage`, anchors, develop |
| `PresentationAdapter.swift` | 8-photo adaptive time buckets |

Legacy (pruned in P0 foundation): former `CullWorkspaceView`, `DevelopSidePane`, `PaletteWorkspaceView`, and related unwired shells were removed. Runtime shell remains `ContinuousWorkspaceView` until the contact-sheet checkpoint.
