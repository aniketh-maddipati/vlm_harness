# Lumina P0 — Culling grammar

Checkpoint after contact sheet (`docs/P0_CONTACT_SHEET.md`). Implements P/X decisions, undo, and exact enter/exit of a single-photograph placeholder — without editing controls.

## Cull mutations

| Key | Behavior |
|---|---|
| `P` | Keep focused photograph; repeat clears to unreviewed |
| `X` | Reject focused photograph; repeat clears to unreviewed |
| `⌘Z` | Undo most recent cull via `P0UndoCoordinator` |

Invariants:

- Persist immediately through `ShootStore`
- Rejected remain visible and recoverable
- Never touch `EditRecipe` / taste / ranking / audit / peer cuts
- Never change selection implicitly
- `FinalSetOrder` mutates only via kept-membership reconciliation when custom order is active
- Export count = complete kept set (`cull == .keep`)

## Visual marks

| State | Treatment |
|---|---|
| Focused | Warm-charcoal outline |
| Unreviewed | No mark |
| Kept | Small ✓ chip |
| Rejected | ~50% dim + ✕ chip |
| Selected | Warm accent outline (distinct from focus) |
| Edited | Small adjustment bar |
| Ordered | Number only in kept-order mode |

## Scale transition

Return / double-click → single-photo placeholder (filmstrip navigation, no editing rail).  
Escape / Grid → contact sheet with same focus + approximate scroll restore. Selection preserved. P/X work at both scales.

## Architecture

- `CullMutationCommand` + `P0UndoCoordinator` — shared command boundary for later edit/batch
- `P0SessionModel.pressKeep/pressReject/undoLastCull` — sole P0 cull path
- Legacy Workbench decision undo remains on the old route only

## Next checkpoint (trustworthy single-photo editing)

1. Keep this cull grammar and scale transition
2. Add adjustment controls on the single-photo surface bound to `EditRecipe` only
3. Never let edits mutate `CullDecision`
4. Push edit commands onto the same `P0UndoCoordinator`
5. Still no compare, batch, AI, or export sheet
