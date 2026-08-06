# Lumina P0 — Contact sheet

Checkpoint after canonical state (`docs/P0_CANONICAL_STATE.md`). Implements **Open a shoot** and the **contact-sheet** scale of the continuous workspace.

## Product surfaces

1. **Open** — choose folder, whole-window drop, recent shoots, reopen without rediscovery.
2. **Contact sheet** — incremental, virtualized browsing of embedded previews.

Not in this checkpoint: P/X cull mutations, editing rail, compare, batch apply, kept-set reorder, export, SD copy, AI.

Legacy Workbench / Canvas / Proof remains reachable from Open → “Legacy shell”.

## Incremental preparation

`ContactSheetPreparation` sequence:

1. Discover recursively (`MediaFormats.discoverPhotos`) → stable `AssetRecord` IDs via `AssetIdentity`
2. Emit `.opened` and enter the contact sheet **before** previews finish
3. Prepare visible / near-visible embedded previews first (Identity-keyed cache)
4. Continue remaining previews in the background
5. EXIF dates asynchronously; merge + chronological re-sort **without** changing IDs, focus, selection, or decisions

Does **not** run: tier assignment, taste, faces, aesthetics, grouping, or `CIRAWFilter` browse demosaic.

## UI

| Piece | Role |
|---|---|
| `P0RootView` | Product root (Open ↔ Contact sheet) |
| `P0OpenView` | Choose / drop / recent |
| `P0ContactSheetView` | Toolbar + keyboard + inspect placeholder |
| `ContactSheetCollectionController` | `NSCollectionView` virtualization |
| `ContactSheetLayout` | Mixed aspect row packing (no uniform crop) |
| `P0SessionModel` | Focus ≠ selection, density, restore, marks |

Marks (Kept / Out / Edit / Ord) are derived from orthogonal `CullDecision` / `EditRecipe` / `FinalSetOrder` / selection — slots only.

## Cache

Preview / grid paths use `AssetIdentity.cacheStem(assetID)`. Legacy stem-keyed files are copied once into the identity path.

## Instrumentation keys

- `p0.folder_to_first_paint`
- `p0.first_usable_preview`
- `p0.visible_cell_cache`
- `p0.focus_to_preview`

Headless bench: `swift Scripts/p0_contact_sheet_bench.swift FOLDER [limit]`

## Next checkpoint (culling)

1. Keep this contact sheet as the browse surface
2. Implement P / X (and hold) mutations on `CullDecision` only — never touch `EditRecipe`
3. Wire selection count + keyboard cull without opening Workbench
4. Persist decisions through `ShootStore`; restore focus/filter/density/scroll from `WorkspaceRestoreState`
5. Do not add AI scoring or treatment families yet
