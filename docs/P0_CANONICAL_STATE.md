# Lumina P0 — Canonical state

Foundation checkpoint: stable asset identity, one recipe authority, and recoverable shoot persistence. The Workbench / Canvas / Proof shell remains for buildability; the contact-sheet workspace is a later checkpoint.

## Canonical state ownership

| Concern | Owner | Notes |
|---|---|---|
| Shoot catalog | `ShootRecord` | Versioned on-disk authority (`shoot.json`) |
| Per-photo durable state | `AssetRecord` | Identity, source, cull, recipe, caches |
| Cull | `CullDecision` on `AssetRecord` | Independent of edit |
| Edit | `EditRecipe` on `AssetRecord` | Tone + geometry + retouch |
| Final kept order | `FinalSetOrder` | Independent of discovery order |
| Batch apply | `BatchEditCommand` | Exact before/after per recipient; geometry off by default |
| Export history | `ExportRecord` | Does not redefine the kept set |
| Workspace restore | `WorkspaceRestoreState` | Focus, filter, density, scroll, scale, kept-order mode |
| Source / volume | `SourceReference` | Path, bookmark, relative path, availability |
| Runtime UI model | `LuminaProject` / `PhotoRecord` | Adapted from `ShootRecord` via `ShootMigration` |

Multi-selection is transient unless deliberately placed in restore state. Missing originals mark `SourceAvailability.missing` and never delete catalog rows.

## Asset identity

`AssetIdentity` derives a rediscovery key from:

1. Volume identity (UUID or volume name)
2. Path relative to the shoot root (handles identical filenames in nested folders)
3. File size
4. Capture timestamp when known

A deterministic UUID is hashed from that key. IDs already stored in existing projects are preserved on migration and win over the hashed value.

Cached preview paths are keyed by `AssetIdentity.cacheStem(assetID)` (UUID string), not the filename stem. Legacy stem-keyed files are copied once into the identity-keyed location on rediscovery.

## Recipe migration

- **Authoritative persisted recipe:** `EditRecipe` (schema v2 includes retouch).
- **Geometry:** `crop` + `straightenDegrees` participate in serialization and `valueFingerprint` (cache invalidation).
- **Tolerant decode:** accepts v1 EditRecipe JSON and legacy `DevelopRecipe`-shaped blobs (no id / schemaVersion / geometry).
- **Render order unchanged:** decode → downsample → WB → exposure → tone → presence → vibrance → NR → sharpen → straighten/crop → display/export.

`DevelopRecipe` remains as a **taste / XMP / older-UI adapter**. Bridging `EditRecipe → DevelopRecipe` still drops geometry; product persistence must not round-trip through that bridge.

## Persistence and recovery

`ShootStore` (actor) is the narrow repository boundary:

- `loadShoot(id:)`
- `saveShoot(_:)`
- `listRecentShoots()`
- `createOrOpenShoot(from:)`

Writes are serialized per shoot (debounced tasks keyed by shoot name — not one global work item). Save path:

1. Encode sorted JSON to a temp file
2. Promote previous `shoot.json` → `shoot.json.good`
3. Replace with the temp file
4. Refresh the good copy

Corrupt primary recovers from `shoot.json.good`. Legacy `project.json` is still loaded and rewritten as `shoot.json` on the next save. Persistence errors are recorded and surfaced; they are not silently discarded.

`ProjectStore` remains a thin facade for existing call sites.

## Legacy compatibility boundary

| Type | Status | Why it remains |
|---|---|---|
| `LuminaProject` | Runtime + legacy decode | ViewModels / shell still consume it |
| `PhotoRecord` | Runtime adapter | Maps to/from `AssetRecord`; `editRecipe` is canonical, `recipe` is a DevelopRecipe bridge |
| `DevelopRecipe` | Superseded for photo persistence | Taste learning, XMP mean, older slider offsets |
| `EditRecipeStore` / `BatchTreatmentSession` | Lab / batch grammar | Not the shoot catalog; keep for develop lab |
| Workbench / Canvas / Proof shell | Temporary product shell | Superseded later by continuous contact-sheet workspace |

Obsolete architecture notes in `docs/DEVELOP_ENGINE.md` and `BUILD_LOG.md` that claimed EditRecipe was already the stored source of truth are corrected here: that claim is now true for P0 shoot persistence.

## Next checkpoint (contact sheet)

Completed on branch `cursor/p0-contact-sheet` — see `docs/P0_CONTACT_SHEET.md`.

## Next checkpoint (culling)

Start from the contact-sheet branch after merge:

1. Read `docs/P0_CONTACT_SHEET.md` + this doc
2. Mutate `CullDecision` only from the contact sheet (P / X / hold)
3. Keep focus, selection, density, and scroll restore intact
4. Do not open Workbench, AI scoring, or the editing rail yet
