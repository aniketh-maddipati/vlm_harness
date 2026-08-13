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

- `CullGrammarMachine` — sole cull grammar authority; P0 routes every mark/focus/advance event through it (CP4)
- `CullMutationCommand` + `P0UndoCoordinator` — committed command boundary for journal/undo (one ⌘Z per act)
- `P0SessionModel.pressKeep/pressReject/pointerMarkKeep/pointerMarkReject` — presentation + persistence only
- Legacy Workbench decision undo remains on the old route only

## Next checkpoint (trustworthy single-photo editing)

Completed on branch `cursor/p0-single-photo-editing` — see `docs/P0_EDITING.md`.

## Next checkpoint (deeper Metal)

1. Keep this cull grammar, scale transition, and EditRecipe command boundary
2. Implement honest Whites/Blacks (and optionally clarity/texture) in the render graph
3. Never let edits mutate `CullDecision`
4. Tighten present-time slider-to-photon metrics
5. Still no compare, batch, AI, or export sheet
